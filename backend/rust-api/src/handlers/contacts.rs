use axum::{
    extract::{Path, State},
    http::{StatusCode, HeaderMap},
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use chrono::Utc;
use crate::AppState;
use crate::websocket;

/// Calculate total debt (sum of all contact balances) at current time
async fn calculate_total_debt(state: &AppState) -> i64 {
    sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COALESCE(SUM(
            CASE 
                WHEN t.direction = 'lent' THEN t.amount
                WHEN t.direction = 'owed' THEN -t.amount
                ELSE 0
            END
        )::BIGINT, 0)
        FROM contacts_projection c
        LEFT JOIN transactions_projection t ON t.contact_id = c.id AND t.is_deleted = false
        WHERE c.is_deleted = false
        "#
    )
    .fetch_one(&*state.db_pool)
    .await
    .unwrap_or(0)
}

#[derive(Deserialize)]
pub struct CreateContactRequest {
    pub name: String,
    pub username: Option<String>,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub notes: Option<String>,
    pub comment: String, // Required: explanation for why this contact is being created
}

#[derive(Deserialize)]
pub struct UpdateContactRequest {
    pub name: Option<String>,
    pub username: Option<String>,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub notes: Option<String>,
    pub comment: String, // Required: explanation for why this contact is being updated
}

#[derive(Deserialize)]
pub struct DeleteContactRequest {
    pub comment: String, // Required: explanation for why this contact is being deleted
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
    headers: HeaderMap,
    Json(payload): Json<CreateContactRequest>,
) -> Result<(StatusCode, Json<CreateContactResponse>), (StatusCode, Json<serde_json::Value>)> {
    // Validate name
    if payload.name.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Name is required"})),
        ));
    }
    
    // Validate comment is required for create operations
    if payload.comment.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Comment is required. Please explain why you are creating this contact."})),
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

    // Get or generate idempotency key
    let idempotency_key = headers
        .get("Idempotency-Key")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
        .unwrap_or_else(|| Uuid::new_v4());

    // Create event data with full audit trail information (without total_debt initially)
    let mut event_data = serde_json::json!({
        "user_id": user_id.to_string(),
        "name": payload.name,
        "username": payload.username,
        "phone": payload.phone,
        "email": payload.email,
        "notes": payload.notes,
        "comment": payload.comment, // Required: user's explanation for this action
        "timestamp": Utc::now().to_rfc3339() // When the action was performed
    });

    // Write event to EventStore
    let stream_name = format!("contact-{}", contact_id);
    
    // Check if event already exists (idempotency)
    let event_exists = state.eventstore
        .check_event_exists(&stream_name, &idempotency_key)
        .await
        .map_err(|e| {
            tracing::error!("Error checking event existence: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to check idempotency"})),
            )
        })?;

    if event_exists {
        // Event already exists, return existing contact
        tracing::info!("Idempotent request detected, returning existing contact");
        // Read existing contact from projection
        let contact = sqlx::query_as::<_, (Uuid, String, i64)>(
            "SELECT id, name, COALESCE((SELECT SUM(CASE WHEN direction = 'lent' THEN amount ELSE -amount END) FROM transactions_projection WHERE contact_id = contacts_projection.id AND is_deleted = false), 0) as balance FROM contacts_projection WHERE id = $1"
        )
        .bind(contact_id)
        .fetch_optional(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Error fetching existing contact: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?;

        if let Some((id, name, balance)) = contact {
            return Ok((
                StatusCode::OK,
                Json(CreateContactResponse {
                    id: id.to_string(),
                    name,
                    balance,
                }),
            ));
        }
    }

    // Write to EventStore (expected version -1 for new stream)
    match state.eventstore
        .write_event(
            &stream_name,
            "ContactCreated",
            idempotency_key,
            event_data.clone(),
            -1, // New stream
        )
        .await
    {
        Ok(version) => {
            tracing::info!("EventStore event written successfully to stream {} at version {}", stream_name, version);
        }
        Err(e) => {
            tracing::warn!("EventStore write failed (non-blocking): {:?}. Contact will still be created.", e);
            // Continue with contact creation even if EventStore fails
        }
    }

    // Create projection FIRST
    sqlx::query(
        r#"
        INSERT INTO contacts_projection 
        (id, user_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7, false, NOW(), NOW(), 0)
        "#
    )
    .bind(contact_id)
    .bind(user_id)
    .bind(payload.name.trim())
    .bind(payload.username.as_deref())
    .bind(payload.phone.as_deref())
    .bind(payload.email.as_deref())
    .bind(payload.notes.as_deref())
    .execute(&*state.db_pool)
        .await
        .map_err(|e| {
        tracing::error!("Error creating contact projection: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create contact"})),
            )
        })?;

    // Calculate total debt AFTER creating the contact (contact creation doesn't change debt, but we record the state AFTER the action)
    let total_debt_after = calculate_total_debt(&state).await;
    event_data["total_debt"] = serde_json::json!(total_debt_after);
    
    // Also write to PostgreSQL events table with total_debt included (AFTER the action)
    // TODO: Remove this once fully migrated to EventStore
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
        tracing::error!("Error creating event in PostgreSQL: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create contact event"})),
        )
    })?;

    // Update projection with event_id
    sqlx::query(
        "UPDATE contacts_projection SET last_event_id = $1 WHERE id = $2"
    )
    .bind(event_id)
    .bind(contact_id)
    .execute(&*state.db_pool)
    .await
    .ok(); // Non-blocking update

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

    let _user_id = sqlx::query_scalar::<_, Uuid>(
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
        "SELECT name, username, phone, email, notes FROM contacts_projection WHERE id = $1"
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
    let current_username: Option<String> = current.get::<Option<String>, _>("username");
    let current_phone: Option<String> = current.get::<Option<String>, _>("phone");
    let current_email: Option<String> = current.get::<Option<String>, _>("email");
    let current_notes: Option<String> = current.get::<Option<String>, _>("notes");

    // Use new values or keep current
    let new_name = payload.name.as_ref().map(|s| s.trim()).filter(|s| !s.is_empty()).unwrap_or(&current_name);
    let new_username = payload.username.as_ref().or(current_username.as_ref());
    let new_phone = payload.phone.as_ref().or(current_phone.as_ref());
    let new_email = payload.email.as_ref().or(current_email.as_ref());
    let new_notes = payload.notes.as_ref().or(current_notes.as_ref());

    // Create event data with full audit trail
    let event_data = serde_json::json!({
        "name": new_name,
        "username": new_username,
        "phone": new_phone,
        "email": new_email,
        "notes": new_notes,
        "comment": payload.comment, // Required comment
        "timestamp": Utc::now().to_rfc3339(), // When the action was performed
        "previous_values": { // Track what changed
            "name": current_name,
            "username": current_username,
            "phone": current_phone,
            "email": current_email,
            "notes": current_notes
        }
    });

    // Write event to EventStore
    let stream_name = format!("contact-{}", contact_uuid);
    let event_id = Uuid::new_v4();
    
    // Get current stream version for optimistic concurrency
    let current_version = state.eventstore
        .get_stream_version(&stream_name)
        .await
        .map_err(|e| {
            tracing::error!("Error getting stream version: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to get stream version"})),
            )
        })?;

    // Append event to EventStore (use -1 if stream doesn't exist, otherwise use current version)
    let expected_version = current_version.unwrap_or(-1);
    let stream_version = state.eventstore
        .write_event(
            &stream_name,
            "ContactUpdated",
            event_id,
            event_data.clone(),
            expected_version, // Expected version for optimistic concurrency
        )
        .await
        .map_err(|e| {
            tracing::error!("Error writing event to EventStore: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to update contact event"})),
            )
        })?;

    // Update projection FIRST
    sqlx::query(
        r#"
        UPDATE contacts_projection 
        SET name = $1, username = $2, phone = $3, email = $4, notes = $5, updated_at = NOW(), last_event_id = $6
        WHERE id = $7
        "#
    )
    .bind(new_name)
    .bind(new_username)
    .bind(new_phone)
    .bind(new_email)
    .bind(new_notes)
    .bind(stream_version) // Use stream version from EventStore
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

    // Calculate total debt AFTER updating the contact (contact update doesn't change debt, but we record the state AFTER the action)
    let total_debt_after = calculate_total_debt(&state).await;
    let mut event_data_with_debt = event_data.clone();
    event_data_with_debt["total_debt"] = serde_json::json!(total_debt_after);
    
    // Also write to PostgreSQL events table with total_debt included (AFTER the action)
    sqlx::query(
        r#"
        INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ((SELECT id FROM users_projection LIMIT 1), 'contact', $1, 'CONTACT_UPDATED', 1, $2, NOW())
        "#
    )
    .bind(contact_uuid)
    .bind(&event_data_with_debt)
    .execute(&*state.db_pool)
    .await
    .ok(); // Non-blocking update

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
    Json(payload): Json<DeleteContactRequest>,
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

    let _user_id = sqlx::query_scalar::<_, Uuid>(
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

    // Get contact data before deletion for audit trail
    let contact_data = sqlx::query(
        "SELECT name, username, phone, email, notes FROM contacts_projection WHERE id = $1"
    )
    .bind(contact_uuid)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching contact data: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;
    
    // Write delete event to EventStore with full audit trail
    let stream_name = format!("contact-{}", contact_uuid);
    let event_id = Uuid::new_v4();
    let event_data = serde_json::json!({
        "comment": payload.comment,
        "timestamp": Utc::now().to_rfc3339(),
        "deleted_contact": contact_data.map(|row| serde_json::json!({
            "name": row.get::<String, _>("name"),
            "username": row.get::<Option<String>, _>("username"),
            "phone": row.get::<Option<String>, _>("phone"),
            "email": row.get::<Option<String>, _>("email"),
            "notes": row.get::<Option<String>, _>("notes")
        }))
    });

    // Soft delete in projection FIRST (set is_deleted = true)
    // We do this first so the delete succeeds even if EventStore fails
    sqlx::query(
        r#"
        UPDATE contacts_projection 
        SET is_deleted = true, updated_at = NOW()
        WHERE id = $1
        "#
    )
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

    // Write delete event to EventStore (non-blocking - don't fail if EventStore is down)
    let eventstore_clone = state.eventstore.clone();
    let stream_name_clone = stream_name.clone();
    let event_id_clone = event_id;
    let event_data_clone = event_data.clone();
    
    tokio::spawn(async move {
        // Get current stream version for optimistic concurrency
        let current_version = eventstore_clone
            .get_stream_version(&stream_name_clone)
            .await;
        
        let expected_version = current_version.unwrap_or(Some(-1)).unwrap_or(-1);
        match eventstore_clone
            .write_event(
                &stream_name_clone,
                "ContactDeleted",
                event_id_clone,
                event_data_clone,
                expected_version,
            )
            .await
        {
            Ok(version) => {
                tracing::info!("EventStore delete event written successfully to stream {} at version {}", stream_name_clone, version);
            }
            Err(e) => {
                tracing::warn!("EventStore write failed (non-blocking): {:?}. Contact deletion still succeeded.", e);
                // Continue - contact deletion already succeeded in PostgreSQL
            }
        }
    });

    // Calculate total debt AFTER deleting the contact (contact deletion doesn't change debt if balance is 0, but we record the state AFTER the action)
    let total_debt_after = calculate_total_debt(&state).await;
    let mut event_data_with_debt = event_data.clone();
    event_data_with_debt["total_debt"] = serde_json::json!(total_debt_after);
    
    // Also write to PostgreSQL events table with total_debt included (AFTER the action)
    sqlx::query(
        r#"
        INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ((SELECT id FROM users_projection LIMIT 1), 'contact', $1, 'CONTACT_DELETED', 1, $2, NOW())
        "#
    )
    .bind(contact_uuid)
    .bind(&event_data_with_debt)
    .execute(&*state.db_pool)
    .await
    .ok(); // Non-blocking update

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
