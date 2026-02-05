use axum::{
    extract::{Path, State, Extension},
    http::{StatusCode, HeaderMap},
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use chrono::Utc;
use crate::AppState;
use crate::websocket;
use crate::middleware::wallet_context::WalletContext;

/// Calculate total debt (sum of all contact balances) at current time for a wallet
async fn calculate_total_debt(state: &AppState, wallet_id: Uuid) -> i64 {
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
        WHERE c.is_deleted = false AND c.wallet_id = $1 AND (t.wallet_id = $1 OR t.wallet_id IS NULL)
        "#
    )
    .bind(wallet_id)
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

#[derive(Serialize)]
pub struct ContactResponse {
    pub id: String,
    pub name: String,
    pub username: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub balance: i64,
    pub is_deleted: bool,
    pub created_at: chrono::NaiveDateTime,
}

impl<'r> sqlx::FromRow<'r, sqlx::postgres::PgRow> for ContactResponse {
    fn from_row(row: &'r sqlx::postgres::PgRow) -> Result<Self, sqlx::Error> {
        Ok(Self {
            id: row.try_get::<uuid::Uuid, _>("id")?.to_string(),
            name: row.try_get("name")?,
            username: row.try_get("username").ok(),
            email: row.try_get("email").ok(),
            phone: row.try_get("phone").ok(),
            balance: row.try_get("balance")?,
            is_deleted: row.try_get("is_deleted")?,
            created_at: row.try_get("created_at")?,
        })
    }
}

pub async fn create_contact(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    headers: HeaderMap,
    Json(payload): Json<CreateContactRequest>,
) -> Result<(StatusCode, Json<CreateContactResponse>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
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
        "wallet_id": wallet_id.to_string(),
        "user_id": user_id.to_string(),
        "name": payload.name,
        "username": payload.username,
        "phone": payload.phone,
        "email": payload.email,
        "notes": payload.notes,
        "comment": payload.comment, // Required: user's explanation for this action
        "timestamp": Utc::now().to_rfc3339() // When the action was performed
    });

    // Check if event already exists (idempotency check using PostgreSQL)
    let existing_event = sqlx::query_as::<_, (Uuid,)>(
        r#"
        SELECT aggregate_id FROM events 
        WHERE idempotency_key = $1 AND aggregate_type = 'contact' AND event_type = 'CONTACT_CREATED'
        LIMIT 1
        "#
    )
    .bind(idempotency_key.to_string())
    .fetch_optional(&*state.db_pool)
        .await
        .map_err(|e| {
        tracing::error!("Error checking idempotency: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to check idempotency"})),
            )
        })?;

    if let Some((existing_contact_id,)) = existing_event {
        // Event already exists, return existing contact
        tracing::info!("Idempotent request detected, returning existing contact");
        // Read existing contact from projection
        let contact = sqlx::query_as::<_, (Uuid, String, i64)>(
            "SELECT id, name, COALESCE((SELECT SUM(CASE WHEN direction = 'lent' THEN amount ELSE -amount END) FROM transactions_projection WHERE contact_id = contacts_projection.id AND is_deleted = false AND wallet_id = $2), 0) as balance FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
        )
        .bind(existing_contact_id)
        .bind(wallet_id)
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

    // Create projection FIRST
    sqlx::query(
        r#"
        INSERT INTO contacts_projection 
        (id, user_id, wallet_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, NOW(), NOW(), 0)
        "#
    )
    .bind(contact_id)
    .bind(user_id)
    .bind(wallet_id)
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
    let total_debt_after = calculate_total_debt(&state, wallet_id).await;
    event_data["total_debt"] = serde_json::json!(total_debt_after);
    
    // Write to PostgreSQL events table with total_debt included (AFTER the action)
    let event_id = sqlx::query_scalar::<_, i64>(
        r#"
        INSERT INTO events (user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, idempotency_key, created_at)
        VALUES ($1, $2, 'contact', $3, 'CONTACT_CREATED', 1, $4, $5, NOW())
        RETURNING id
        "#
    )
    .bind(user_id)
    .bind(wallet_id)
    .bind(contact_id)
    .bind(&event_data)
    .bind(idempotency_key.to_string())
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
        "UPDATE contacts_projection SET last_event_id = $1 WHERE id = $2 AND wallet_id = $3"
    )
    .bind(event_id)
    .bind(contact_id)
    .bind(wallet_id)
    .execute(&*state.db_pool)
    .await
    .ok(); // Non-blocking update

    let response = CreateContactResponse {
        id: contact_id.to_string(),
        name: payload.name.clone(),
        balance: 0, // New contact starts with zero balance
    };

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_id,
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
    Extension(wallet_context): Extension<WalletContext>,
    Json(payload): Json<UpdateContactRequest>,
) -> Result<(StatusCode, Json<UpdateContactResponse>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
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
        "SELECT name, username, phone, email, notes FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_uuid)
    .bind(wallet_id)
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
        "wallet_id": wallet_id.to_string(),
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

    // Get current version for optimistic concurrency
    let current_version = sqlx::query_scalar::<_, i32>(
        "SELECT version FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_uuid)
    .bind(wallet_id)
    .fetch_optional(&*state.db_pool)
        .await
        .map_err(|e| {
        tracing::error!("Error getting contact version: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to get contact version"})),
            )
        })?;

    let current_version = current_version.unwrap_or(1);
    let new_version = current_version + 1;

    // Update projection FIRST with version increment
    sqlx::query(
        r#"
        UPDATE contacts_projection 
        SET name = $1, username = $2, phone = $3, email = $4, notes = $5, updated_at = NOW(), version = $6
        WHERE id = $7 AND wallet_id = $8 AND version = $9
        "#
    )
    .bind(new_name)
    .bind(new_username)
    .bind(new_phone)
    .bind(new_email)
    .bind(new_notes)
    .bind(new_version)
    .bind(contact_uuid)
    .bind(wallet_id)
    .bind(current_version)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error updating contact projection: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update contact"})),
        )
    })?;

    // Check if update actually happened (optimistic locking)
    let rows_affected = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM contacts_projection WHERE id = $1 AND wallet_id = $2 AND version = $3"
    )
    .bind(contact_uuid)
    .bind(wallet_id)
    .bind(new_version)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking update result: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to verify update"})),
        )
    })?;

    if rows_affected == 0 {
        return Err((
            StatusCode::CONFLICT,
            Json(serde_json::json!({"error": "Contact was modified by another request. Please refresh and try again."})),
        ));
    }

    // Calculate total debt AFTER updating the contact (contact update doesn't change debt, but we record the state AFTER the action)
    let total_debt_after = calculate_total_debt(&state, wallet_id).await;
    let mut event_data_with_debt = event_data.clone();
    event_data_with_debt["total_debt"] = serde_json::json!(total_debt_after);
    
    // Write to PostgreSQL events table
    let event_id = sqlx::query_scalar::<_, i64>(
        r#"
        INSERT INTO events (user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ((SELECT id FROM users_projection LIMIT 1), $1, 'contact', $2, 'CONTACT_UPDATED', $3, $4, NOW())
        RETURNING id
        "#
    )
    .bind(wallet_id)
    .bind(contact_uuid)
    .bind(new_version)
    .bind(&event_data_with_debt)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating update event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create update event"})),
        )
    })?;

    // Update projection with event_id
    sqlx::query(
        "UPDATE contacts_projection SET last_event_id = $1 WHERE id = $2"
    )
    .bind(event_id)
    .bind(contact_uuid)
    .execute(&*state.db_pool)
    .await
    .ok(); // Non-blocking update

    let response = UpdateContactResponse {
        id: contact_id.clone(),
        message: "Contact updated successfully".to_string(),
    };

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_id,
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
    Extension(wallet_context): Extension<WalletContext>,
    Json(payload): Json<DeleteContactRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    let contact_uuid = Uuid::parse_str(&contact_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid contact_id: {}", e)})),
        )
    })?;

    // Check if contact exists in this wallet
    let contact_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND wallet_id = $2 AND is_deleted = false)"
    )
    .bind(contact_uuid)
    .bind(wallet_id)
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
        "SELECT name, username, phone, email, notes FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_uuid)
    .bind(wallet_id)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching contact data: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;
    
    // Prepare delete event data with full audit trail
    let event_data = serde_json::json!({
        "wallet_id": wallet_id.to_string(),
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

    // Get current version for optimistic concurrency
    let current_version = sqlx::query_scalar::<_, i32>(
        "SELECT version FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
    )
    .bind(contact_uuid)
    .bind(wallet_id)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error getting contact version: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to get contact version"})),
        )
    })?;

    let current_version = current_version.unwrap_or(1);
    let new_version = current_version + 1;

    // Soft delete in projection FIRST (set is_deleted = true)
    sqlx::query(
        r#"
        UPDATE contacts_projection 
        SET is_deleted = true, updated_at = NOW(), version = $1
        WHERE id = $2 AND wallet_id = $3 AND version = $4
        "#
    )
    .bind(new_version)
    .bind(contact_uuid)
    .bind(wallet_id)
    .bind(current_version)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error deleting contact projection: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to delete contact"})),
        )
    })?;

    // Check if delete actually happened (optimistic locking)
    let rows_affected = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM contacts_projection WHERE id = $1 AND wallet_id = $2 AND version = $3"
    )
    .bind(contact_uuid)
    .bind(wallet_id)
    .bind(new_version)
    .fetch_one(&*state.db_pool)
            .await
    .map_err(|e| {
        tracing::error!("Error checking delete result: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to verify delete"})),
        )
    })?;

    if rows_affected == 0 {
        return Err((
            StatusCode::CONFLICT,
            Json(serde_json::json!({"error": "Contact was modified by another request. Please refresh and try again."})),
        ));
    }

    // Calculate total debt AFTER deleting the contact (contact deletion doesn't change debt if balance is 0, but we record the state AFTER the action)
    let total_debt_after = calculate_total_debt(&state, wallet_id).await;
    let mut event_data_with_debt = event_data.clone();
    event_data_with_debt["total_debt"] = serde_json::json!(total_debt_after);
    
    // Write to PostgreSQL events table
    let event_id = sqlx::query_scalar::<_, i64>(
        r#"
        INSERT INTO events (user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ((SELECT id FROM users_projection LIMIT 1), $1, 'contact', $2, 'CONTACT_DELETED', $3, $4, NOW())
        RETURNING id
        "#
    )
    .bind(wallet_id)
    .bind(contact_uuid)
    .bind(new_version)
    .bind(&event_data_with_debt)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating delete event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create delete event"})),
        )
    })?;

    // Update projection with event_id
    sqlx::query(
        "UPDATE contacts_projection SET last_event_id = $1 WHERE id = $2"
    )
    .bind(event_id)
    .bind(contact_uuid)
    .execute(&*state.db_pool)
    .await
    .ok(); // Non-blocking update

    let response = serde_json::json!({
        "id": contact_id,
        "message": "Contact deleted successfully"
    });

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_id,
        "contact_deleted",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::OK,
        Json(response),
    ))
}

pub async fn get_contacts(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
) -> Result<Json<Vec<ContactResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = wallet_context.wallet_id;
    
    let contacts = sqlx::query_as::<_, ContactResponse>(
        r#"
        SELECT 
            c.id,
            c.name,
            c.username,
            c.email,
            c.phone,
            COALESCE(SUM(
                CASE 
                    WHEN t.direction = 'lent' THEN t.amount
                    WHEN t.direction = 'owed' THEN -t.amount
                    ELSE 0
                END
            )::BIGINT, 0) as balance,
            c.is_deleted,
            c.created_at
        FROM contacts_projection c
        LEFT JOIN transactions_projection t ON t.contact_id = c.id AND t.is_deleted = false AND t.wallet_id = $1
        WHERE c.is_deleted = false AND c.wallet_id = $1
        GROUP BY c.id, c.name, c.username, c.email, c.phone, c.is_deleted, c.created_at
        ORDER BY c.name
        "#
    )
    .bind(wallet_id)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching contacts: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;

    Ok(Json(contacts))
}
