use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use crate::AppState;
use crate::websocket;

#[derive(Deserialize)]
pub struct CreateContactRequest {
    pub name: String,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub notes: Option<String>,
}

#[derive(Deserialize)]
pub struct UpdateContactRequest {
    pub name: Option<String>,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub notes: Option<String>,
}

#[derive(Serialize)]
pub struct CreateContactResponse {
    pub id: String,
    pub name: String,
    pub balance: i64,
}

#[derive(Serialize)]
pub struct UpdateContactResponse {
    pub id: String,
    pub message: String,
}

pub async fn create_contact(
    State(state): State<AppState>,
    Json(payload): Json<CreateContactRequest>,
) -> Result<(StatusCode, Json<CreateContactResponse>), (StatusCode, Json<serde_json::Value>)> {
    // Validate name
    if payload.name.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Name is required"})),
        ));
    }

    // Get user ID
    let user_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM users_projection LIMIT 1"
    )
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    // Generate contact ID
    let contact_id = Uuid::new_v4();

    // Create event data
    let event_data = serde_json::json!({
        "name": payload.name,
        "phone": payload.phone,
        "email": payload.email,
        "notes": payload.notes
    });

    // Create event in event store
    let event_id = sqlx::query_scalar::<_, i64>(
        r#"
        INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ($1, 'contact', $2, 'CONTACT_CREATED', 1, $3, NOW())
        RETURNING id
        "#
    )
    .bind(user_id)
    .bind(contact_id)
    .bind(&event_data)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create contact event"})),
        )
    })?;

    // Create projection
    sqlx::query(
        r#"
        INSERT INTO contacts_projection 
        (id, user_id, name, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
        VALUES ($1, $2, $3, $4, $5, $6, false, NOW(), NOW(), $7)
        "#
    )
    .bind(contact_id)
    .bind(user_id)
    .bind(payload.name.trim())
    .bind(payload.phone.as_deref())
    .bind(payload.email.as_deref())
    .bind(payload.notes.as_deref())
    .bind(event_id)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating contact projection: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create contact"})),
        )
    })?;

    let response = CreateContactResponse {
        id: contact_id.to_string(),
        name: payload.name.clone(),
        balance: 0, // New contact starts with zero balance
    };

    // Broadcast change via WebSocket
    websocket::broadcast_change(
        &state.broadcast_tx,
        "contact_created",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::CREATED,
        Json(response),
    ))
}

pub async fn update_contact(
    Path(contact_id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateContactRequest>,
) -> Result<(StatusCode, Json<UpdateContactResponse>), (StatusCode, Json<serde_json::Value>)> {
    let contact_uuid = Uuid::parse_str(&contact_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid contact_id: {}", e)})),
        )
    })?;

    // Check if contact exists
    let contact_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND is_deleted = false)"
    )
    .bind(contact_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking contact: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if !contact_exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Contact not found"})),
        ));
    }

    let user_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM users_projection LIMIT 1"
    )
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    // Get current contact data
    let current = sqlx::query(
        "SELECT name, phone, email, notes FROM contacts_projection WHERE id = $1"
    )
    .bind(contact_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching contact: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let current_name: String = current.get::<String, _>("name");
    let current_phone: Option<String> = current.get::<Option<String>, _>("phone");
    let current_email: Option<String> = current.get::<Option<String>, _>("email");
    let current_notes: Option<String> = current.get::<Option<String>, _>("notes");

    // Use new values or keep current
    let new_name = payload.name.as_ref().map(|s| s.trim()).filter(|s| !s.is_empty()).unwrap_or(&current_name);
    let new_phone = payload.phone.as_ref().or(current_phone.as_ref());
    let new_email = payload.email.as_ref().or(current_email.as_ref());
    let new_notes = payload.notes.as_ref().or(current_notes.as_ref());

    // Create event data
    let event_data = serde_json::json!({
        "name": new_name,
        "phone": new_phone,
        "email": new_email,
        "notes": new_notes
    });

    // Create update event
    let event_id = sqlx::query_scalar::<_, i64>(
        r#"
        INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ($1, 'contact', $2, 'CONTACT_UPDATED', 2, $3, NOW())
        RETURNING id
        "#
    )
    .bind(user_id)
    .bind(contact_uuid)
    .bind(&event_data)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating update event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update contact event"})),
        )
    })?;

    // Update projection
    sqlx::query(
        r#"
        UPDATE contacts_projection 
        SET name = $1, phone = $2, email = $3, notes = $4, updated_at = NOW(), last_event_id = $5
        WHERE id = $6
        "#
    )
    .bind(new_name)
    .bind(new_phone)
    .bind(new_email)
    .bind(new_notes)
    .bind(event_id)
    .bind(contact_uuid)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error updating contact projection: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update contact"})),
        )
    })?;

    let response = UpdateContactResponse {
        id: contact_id.clone(),
        message: "Contact updated successfully".to_string(),
    };

    // Broadcast change via WebSocket
    websocket::broadcast_change(
        &state.broadcast_tx,
        "contact_updated",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::OK,
        Json(response),
    ))
}

pub async fn delete_contact(
    Path(contact_id): Path<String>,
    State(state): State<AppState>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let contact_uuid = Uuid::parse_str(&contact_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid contact_id: {}", e)})),
        )
    })?;

    // Check if contact exists
    let contact_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND is_deleted = false)"
    )
    .bind(contact_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking contact: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if !contact_exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Contact not found"})),
        ));
    }

    let user_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM users_projection LIMIT 1"
    )
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    // Create delete event
    let event_id = sqlx::query_scalar::<_, i64>(
        r#"
        INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ($1, 'contact', $2, 'CONTACT_DELETED', 3, '{}', NOW())
        RETURNING id
        "#
    )
    .bind(user_id)
    .bind(contact_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating delete event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to delete contact event"})),
        )
    })?;

    // Soft delete in projection (set is_deleted = true)
    sqlx::query(
        r#"
        UPDATE contacts_projection 
        SET is_deleted = true, updated_at = NOW(), last_event_id = $1
        WHERE id = $2
        "#
    )
    .bind(event_id)
    .bind(contact_uuid)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error deleting contact projection: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to delete contact"})),
        )
    })?;

    let response = serde_json::json!({
        "id": contact_id,
        "message": "Contact deleted successfully"
    });

    // Broadcast change via WebSocket
    websocket::broadcast_change(
        &state.broadcast_tx,
        "contact_deleted",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::OK,
        Json(response),
    ))
}
