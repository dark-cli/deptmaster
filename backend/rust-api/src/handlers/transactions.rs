use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use chrono::Utc;
use crate::AppState;
use crate::websocket;

#[derive(Deserialize)]
pub struct CreateTransactionRequest {
    pub contact_id: String,
    pub r#type: String, // "money" or "item"
    pub direction: String, // "owed" or "lent"
    pub amount: i64,
    pub currency: Option<String>,
    pub description: Option<String>,
    pub transaction_date: String, // ISO date string
    pub due_date: Option<String>, // Optional ISO date string
}

#[derive(Deserialize)]
pub struct UpdateTransactionRequest {
    pub contact_id: Option<String>,
    pub r#type: Option<String>,
    pub direction: Option<String>,
    pub amount: Option<i64>,
    pub currency: Option<String>,
    pub description: Option<String>,
    pub transaction_date: Option<String>,
    pub due_date: Option<String>,
}

#[derive(Serialize)]
pub struct CreateTransactionResponse {
    pub id: String,
    pub contact_id: String,
}

#[derive(Serialize)]
pub struct UpdateTransactionResponse {
    pub id: String,
    pub message: String,
}

#[derive(Serialize)]
pub struct TransactionResponse {
    pub id: String,
    pub contact_id: String,
    pub r#type: String,
    pub direction: String,
    pub amount: i64,
    pub currency: Option<String>,
    pub description: Option<String>,
    pub transaction_date: chrono::NaiveDate,
    pub due_date: Option<chrono::NaiveDate>,
    pub created_at: chrono::NaiveDateTime,
    pub updated_at: chrono::NaiveDateTime,
}

impl<'r> sqlx::FromRow<'r, sqlx::postgres::PgRow> for TransactionResponse {
    fn from_row(row: &'r sqlx::postgres::PgRow) -> Result<Self, sqlx::Error> {
        Ok(Self {
            id: row.try_get::<uuid::Uuid, _>("id")?.to_string(),
            contact_id: row.try_get::<uuid::Uuid, _>("contact_id")?.to_string(),
            r#type: row.try_get("type")?,
            direction: row.try_get("direction")?,
            amount: row.try_get("amount")?,
            currency: row.try_get("currency").ok(),
            description: row.try_get("description").ok(),
            transaction_date: row.try_get("transaction_date")?,
            due_date: row.try_get("due_date").ok(),
            created_at: row.try_get("created_at")?,
            updated_at: row.try_get("updated_at")?,
        })
    }
}

pub async fn get_transactions(
    State(state): State<AppState>,
) -> Result<Json<Vec<TransactionResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let transactions = sqlx::query_as::<_, TransactionResponse>(
        r#"
        SELECT 
            id,
            contact_id,
            type,
            direction,
            amount,
            currency,
            description,
            transaction_date,
            due_date,
            created_at,
            updated_at
        FROM transactions_projection
        WHERE is_deleted = false
        ORDER BY transaction_date DESC
        "#
    )
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching transactions: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    Ok(Json(transactions))
}

pub async fn create_transaction(
    State(state): State<AppState>,
    Json(payload): Json<CreateTransactionRequest>,
) -> Result<(StatusCode, Json<CreateTransactionResponse>), (StatusCode, Json<serde_json::Value>)> {
    // Validate contact exists
    let contact_uuid = Uuid::parse_str(&payload.contact_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid contact_id: {}", e)})),
        )
    })?;

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

    // Generate transaction ID
    let transaction_id = Uuid::new_v4();
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

    // Parse transaction date
    let transaction_date = chrono::NaiveDate::parse_from_str(&payload.transaction_date, "%Y-%m-%d")
        .map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid date format: {}", e)})),
            )
        })?;

    // Get currency value (clone to avoid move)
    let currency = payload.currency.as_deref().unwrap_or("USD").to_string();
    
    // Parse due date if provided
    let due_date = payload.due_date.as_ref()
        .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok());
    
    // Create event data
    let event_data = serde_json::json!({
        "contact_id": payload.contact_id,
        "type": payload.r#type,
        "direction": payload.direction,
        "amount": payload.amount,
        "currency": currency,
        "description": payload.description,
        "transaction_date": payload.transaction_date,
        "due_date": payload.due_date
    });

    // Create event in event store
    let event_id = sqlx::query_scalar::<_, i64>(
        r#"
        INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ($1, 'transaction', $2, 'TRANSACTION_CREATED', 1, $3, NOW())
        RETURNING id
        "#
    )
    .bind(user_id)
    .bind(transaction_id)
    .bind(&event_data)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create transaction event"})),
        )
    })?;

    // Create projection
    sqlx::query(
        r#"
        INSERT INTO transactions_projection 
        (id, user_id, contact_id, type, direction, amount, currency, description, transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false, NOW(), NOW(), $11)
        "#
    )
    .bind(transaction_id)
    .bind(user_id)
    .bind(contact_uuid)
    .bind(&payload.r#type)
    .bind(&payload.direction)
    .bind(payload.amount)
    .bind(payload.currency.as_deref().unwrap_or("USD"))
    .bind(payload.description.as_deref())
    .bind(transaction_date)
    .bind(due_date)
    .bind(event_id)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating transaction projection: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create transaction"})),
        )
    })?;

    let response = CreateTransactionResponse {
        id: transaction_id.to_string(),
        contact_id: payload.contact_id.clone(),
    };

    // Broadcast change via WebSocket
    websocket::broadcast_change(
        &state.broadcast_tx,
        "transaction_created",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::CREATED,
        Json(response),
    ))
}

pub async fn update_transaction(
    Path(transaction_id): Path<String>,
    State(state): State<AppState>,
    Json(payload): Json<UpdateTransactionRequest>,
) -> Result<(StatusCode, Json<UpdateTransactionResponse>), (StatusCode, Json<serde_json::Value>)> {
    let transaction_uuid = Uuid::parse_str(&transaction_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid transaction_id: {}", e)})),
        )
    })?;

    // Check if transaction exists
    let transaction_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM transactions_projection WHERE id = $1 AND is_deleted = false)"
    )
    .bind(transaction_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking transaction: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if !transaction_exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Transaction not found"})),
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

    // Get current transaction data
    let current = sqlx::query(
        "SELECT contact_id, type, direction, amount, currency, description, transaction_date, due_date FROM transactions_projection WHERE id = $1"
    )
    .bind(transaction_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching transaction: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let contact_id: Uuid = current.get::<Uuid, _>("contact_id");
    let current_type: String = current.get::<String, _>("type");
    let current_direction: String = current.get::<String, _>("direction");
    let current_amount: i64 = current.get::<i64, _>("amount");
    let current_currency: Option<String> = current.get::<Option<String>, _>("currency");
    let current_description: Option<String> = current.get::<Option<String>, _>("description");
    let current_date: chrono::NaiveDate = current.get::<chrono::NaiveDate, _>("transaction_date");
    let current_due_date: Option<chrono::NaiveDate> = current.get::<Option<chrono::NaiveDate>, _>("due_date");

    // Use new values or keep current
    let new_contact_id = payload.contact_id.as_ref()
        .and_then(|s| Uuid::parse_str(s).ok())
        .unwrap_or(contact_id);
    let new_type = payload.r#type.as_ref().unwrap_or(&current_type);
    let new_direction = payload.direction.as_ref().unwrap_or(&current_direction);
    let new_amount = payload.amount.unwrap_or(current_amount);
    let current_currency_str = current_currency.as_ref().map(|s| s.as_str()).unwrap_or("USD");
    let new_currency = payload.currency.as_ref().map(|s| s.as_str()).unwrap_or(current_currency_str);
    let new_description = payload.description.as_ref().or(current_description.as_ref());
    let new_date = payload.transaction_date.as_ref()
        .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
        .unwrap_or(current_date);
    let new_due_date = payload.due_date.as_ref()
        .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
        .or(current_due_date);

    // Validate new contact if changed
    if new_contact_id != contact_id {
        let contact_exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND is_deleted = false)"
        )
        .bind(new_contact_id)
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
    }

    // Create event data
    let event_data = serde_json::json!({
        "contact_id": new_contact_id.to_string(),
        "type": new_type,
        "direction": new_direction,
        "amount": new_amount,
        "currency": new_currency,
        "description": new_description,
        "transaction_date": new_date.format("%Y-%m-%d").to_string(),
        "due_date": new_due_date.map(|d| d.format("%Y-%m-%d").to_string())
    });

    // Create update event
    let event_id = sqlx::query_scalar::<_, i64>(
        r#"
        INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
        VALUES ($1, 'transaction', $2, 'TRANSACTION_UPDATED', 2, $3, NOW())
        RETURNING id
        "#
    )
    .bind(user_id)
    .bind(transaction_uuid)
    .bind(&event_data)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating update event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update transaction event"})),
        )
    })?;

    // Update projection
    sqlx::query(
        r#"
        UPDATE transactions_projection 
        SET contact_id = $1, type = $2, direction = $3, amount = $4, currency = $5, 
            description = $6, transaction_date = $7, due_date = $8, updated_at = NOW(), last_event_id = $9
        WHERE id = $10
        "#
    )
    .bind(new_contact_id)
    .bind(new_type)
    .bind(new_direction)
    .bind(new_amount)
    .bind(new_currency)
    .bind(new_description)
    .bind(new_date)
    .bind(new_due_date)
    .bind(event_id)
    .bind(transaction_uuid)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error updating transaction projection: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update transaction"})),
        )
    })?;

    let response = UpdateTransactionResponse {
        id: transaction_id,
        message: "Transaction updated successfully".to_string(),
    };

    // Broadcast change via WebSocket
    websocket::broadcast_change(
        &state.broadcast_tx,
        "transaction_updated",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::OK,
        Json(response),
    ))
}

pub async fn delete_transaction(
    Path(transaction_id): Path<String>,
    State(state): State<AppState>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let transaction_uuid = Uuid::parse_str(&transaction_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid transaction_id: {}", e)})),
        )
    })?;

    // Check if transaction exists
    let transaction_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM transactions_projection WHERE id = $1 AND is_deleted = false)"
    )
    .bind(transaction_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking transaction: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if !transaction_exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Transaction not found"})),
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
        VALUES ($1, 'transaction', $2, 'TRANSACTION_DELETED', 3, '{}', NOW())
        RETURNING id
        "#
    )
    .bind(user_id)
    .bind(transaction_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating delete event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to delete transaction event"})),
        )
    })?;

    // Soft delete in projection (set is_deleted = true)
    sqlx::query(
        r#"
        UPDATE transactions_projection 
        SET is_deleted = true, updated_at = NOW(), last_event_id = $1
        WHERE id = $2
        "#
    )
    .bind(event_id)
    .bind(transaction_uuid)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error deleting transaction projection: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to delete transaction"})),
        )
    })?;

    let response = serde_json::json!({
        "id": transaction_id,
        "message": "Transaction deleted successfully"
    });

    // Broadcast change via WebSocket
    websocket::broadcast_change(
        &state.broadcast_tx,
        "transaction_deleted",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::OK,
        Json(response),
    ))
}
