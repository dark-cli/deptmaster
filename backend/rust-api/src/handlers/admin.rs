use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{Json, Html},
};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Row, postgres::PgRow, QueryBuilder};
use crate::AppState;

#[derive(Deserialize)]
pub struct EventQuery {
    limit: Option<i64>,
    offset: Option<i64>,
    event_type: Option<String>,
    aggregate_type: Option<String>,
    user_id: Option<String>,
    search: Option<String>, // Search in event_data (comment, name, etc.)
    date_from: Option<String>, // ISO date string
    date_to: Option<String>, // ISO date string
}

#[derive(Serialize)]
pub struct EventResponse {
    pub event_id: String,
    pub aggregate_type: String,
    pub event_type: String,
    pub user_id: String,
    pub user_email: Option<String>, // User email for display
    pub created_at: chrono::NaiveDateTime,
    pub event_data: serde_json::Value,
}

impl<'r> FromRow<'r, PgRow> for EventResponse {
    fn from_row(row: &'r PgRow) -> Result<Self, sqlx::Error> {
        Ok(Self {
            event_id: row.try_get::<uuid::Uuid, _>("event_id")?.to_string(),
            aggregate_type: row.try_get("aggregate_type")?,
            event_type: row.try_get("event_type")?,
            user_id: row.try_get::<uuid::Uuid, _>("user_id")?.to_string(),
            user_email: row.try_get("user_email").ok(),
            created_at: row.try_get("created_at")?,
            event_data: row.try_get("event_data")?,
        })
    }
}

#[derive(Serialize)]
pub struct ContactResponse {
    pub id: String,
    pub name: String,
    pub username: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub balance: i64,  // Net balance: positive = they owe you, negative = you owe them
    pub is_deleted: bool,
    pub created_at: chrono::NaiveDateTime,
}

impl<'r> FromRow<'r, PgRow> for ContactResponse {
    fn from_row(row: &'r PgRow) -> Result<Self, sqlx::Error> {
        Ok(Self {
            id: row.try_get::<uuid::Uuid, _>("id")?.to_string(),
            name: row.try_get("name")?,
            username: row.try_get("username").ok(),
            email: row.try_get("email")?,
            phone: row.try_get("phone")?,
            balance: row.try_get("balance")?,
            is_deleted: row.try_get("is_deleted")?,
            created_at: row.try_get("created_at")?,
        })
    }
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

impl<'r> FromRow<'r, PgRow> for TransactionResponse {
    fn from_row(row: &'r PgRow) -> Result<Self, sqlx::Error> {
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

#[derive(Serialize)]
pub struct ProjectionStatus {
    pub last_event_id: Option<i64>,
    pub projections_updated: Option<bool>,
    pub last_update: Option<chrono::DateTime<chrono::Utc>>,
}

pub async fn admin_panel() -> Html<&'static str> {
    Html(include_str!("../../static/admin/index.html"))
}

pub async fn get_events(
    Query(params): Query<EventQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<EventResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let limit = params.limit.unwrap_or(100);
    let offset = params.offset.unwrap_or(0);

    // Build dynamic query with filters using QueryBuilder (join with users to get email)
    let mut query_builder: QueryBuilder<'_, sqlx::Postgres> = QueryBuilder::new(
        "SELECT e.event_id, e.aggregate_type, e.event_type, e.user_id, u.email as user_email, e.created_at, e.event_data FROM events e LEFT JOIN users_projection u ON e.user_id = u.id WHERE 1=1"
    );
    
    // Filter by event_type (case-insensitive, supports both CREATED/DELETED and TRANSACTION_CREATED/TRANSACTION_DELETED formats)
    if let Some(event_type) = &params.event_type {
        if !event_type.is_empty() {
            // Use LIKE pattern matching to handle both formats:
            // - "CREATED" matches both "CREATED" and "TRANSACTION_CREATED", "CONTACT_CREATED"
            // - "DELETED" matches both "DELETED" and "TRANSACTION_DELETED", "CONTACT_DELETED"
            // - "UPDATED" matches both "UPDATED" and "TRANSACTION_UPDATED", "CONTACT_UPDATED"
            query_builder.push(" AND (UPPER(e.event_type) = UPPER(");
            query_builder.push_bind(event_type);
            query_builder.push(") OR UPPER(e.event_type) LIKE UPPER(");
            query_builder.push_bind(format!("%_{}", event_type));
            query_builder.push("))");
        }
    }
    
    // Filter by aggregate_type
    if let Some(aggregate_type) = &params.aggregate_type {
        if !aggregate_type.is_empty() {
            query_builder.push(" AND e.aggregate_type = ");
            query_builder.push_bind(aggregate_type);
        }
    }
    
    // Filter by user_id
    if let Some(user_id) = &params.user_id {
        if !user_id.is_empty() {
            query_builder.push(" AND e.user_id::text = ");
            query_builder.push_bind(user_id);
        }
    }
    
    // Filter by date range
    if let Some(date_from) = &params.date_from {
        if !date_from.is_empty() {
            query_builder.push(" AND e.created_at >= ");
            query_builder.push_bind(date_from);
            query_builder.push("::timestamp");
        }
    }
    
    if let Some(date_to) = &params.date_to {
        if !date_to.is_empty() {
            query_builder.push(" AND e.created_at <= ");
            query_builder.push_bind(date_to);
            query_builder.push("::timestamp");
        }
    }
    
    // Search in event_data (comment, name, etc.)
    if let Some(search) = &params.search {
        if !search.is_empty() {
            let search_pattern = format!("%{}%", search);
            query_builder.push(" AND (e.event_data::text ILIKE ");
            query_builder.push_bind(search_pattern.clone());
            query_builder.push(" OR e.event_type ILIKE ");
            query_builder.push_bind(search_pattern.clone());
            query_builder.push(" OR e.aggregate_type ILIKE ");
            query_builder.push_bind(search_pattern);
            query_builder.push(")");
        }
    }
    
    query_builder.push(" ORDER BY e.created_at DESC LIMIT ");
    query_builder.push_bind(limit);
    query_builder.push(" OFFSET ");
    query_builder.push_bind(offset);
    
    let query = query_builder.build_query_as::<EventResponse>();
    let events = query.fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching events: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;

    Ok(Json(events))
}

// Get the latest event ID for change detection
pub async fn get_latest_event_id(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let latest_id = sqlx::query_scalar::<_, Option<i64>>(
        "SELECT MAX(id) FROM events"
    )
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching latest event ID: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;

    Ok(Json(serde_json::json!({
        "latest_event_id": latest_id,
        "timestamp": chrono::Utc::now().to_rfc3339()
    })))
}

// Delete an event if it's less than 5 seconds old (for undo functionality)
#[derive(Deserialize)]
pub struct DeleteEventRequest {
    event_id: String,
}

pub async fn delete_event(
    axum::extract::Path(event_id): axum::extract::Path<String>,
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let event_uuid = uuid::Uuid::parse_str(&event_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid event ID: {}", e)})),
        )
    })?;

    // Check if event exists and get its creation time
    let event_row = sqlx::query(
        "SELECT created_at FROM events WHERE event_id = $1"
    )
    .bind(event_uuid)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching event: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if let Some(row) = event_row {
        let created_at: chrono::NaiveDateTime = row.get("created_at");
        let now = chrono::Utc::now().naive_utc();
        let age_seconds = (now - created_at).num_seconds();

        // Only allow deletion if event is less than 5 seconds old
        if age_seconds >= 5 {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "error": "Event is too old to delete",
                    "age_seconds": age_seconds
                })),
            ));
        }

        // Delete the event
        let deleted = sqlx::query(
            "DELETE FROM events WHERE event_id = $1"
        )
        .bind(event_uuid)
        .execute(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Error deleting event: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?;

        if deleted.rows_affected() == 0 {
            return Err((
                StatusCode::NOT_FOUND,
                Json(serde_json::json!({"error": "Event not found"})),
            ));
        }

        // Rebuild projections since we deleted an event
        // Note: This is a simplified approach - in production you might want to rebuild more carefully
        tokio::spawn(async move {
            if let Err(e) = crate::handlers::sync::rebuild_projections_from_events(&state).await {
                tracing::error!("Error rebuilding projections after event deletion: {:?}", e);
            }
        });

        Ok(Json(serde_json::json!({
            "success": true,
            "message": "Event deleted successfully"
        })))
    } else {
        Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Event not found"})),
        ))
    }
}

// Backfill events for transactions that don't have events
pub async fn backfill_transaction_events(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    // Get user ID
    let user_id = sqlx::query_scalar::<_, uuid::Uuid>(
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

    // Get all transactions that don't have events
    let transactions = sqlx::query(
        r#"
        SELECT t.id, t.user_id, t.contact_id, t.type, t.direction, t.amount, 
               t.currency, t.description, t.transaction_date, t.due_date, t.created_at
        FROM transactions_projection t
        WHERE t.is_deleted = false
        AND NOT EXISTS (
            SELECT 1 FROM events e 
            WHERE e.aggregate_type = 'transaction' 
            AND e.aggregate_id = t.id
            AND e.event_type = 'TRANSACTION_CREATED'
        )
        ORDER BY t.created_at
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

    if transactions.is_empty() {
        return Ok(Json(serde_json::json!({
            "message": "All transactions already have events",
            "created": 0
        })));
    }

    let total_count = transactions.len();
    tracing::info!("Backfilling {} transaction events", total_count);

    let mut created_count = 0;
    let mut error_count = 0;

    for row in transactions {
        let txn_id: uuid::Uuid = row.get("id");
        let contact_id: uuid::Uuid = row.get("contact_id");
        let txn_type: String = row.get("type");
        let direction: String = row.get("direction");
        let amount: i64 = row.get("amount");
        let currency: Option<String> = row.get("currency");
        let description: Option<String> = row.get("description");
        let txn_date: chrono::NaiveDate = row.get("transaction_date");
        let due_date: Option<chrono::NaiveDate> = row.get("due_date");
        let created_at: chrono::NaiveDateTime = row.get("created_at");

        // Create event data
        let event_data = serde_json::json!({
            "contact_id": contact_id.to_string(),
            "type": txn_type,
            "direction": direction,
            "amount": amount,
            "currency": currency.unwrap_or_else(|| "USD".to_string()),
            "description": description,
            "transaction_date": txn_date.format("%Y-%m-%d").to_string(),
            "due_date": due_date.map(|d| d.format("%Y-%m-%d").to_string()),
            "comment": format!("Backfilled event for existing transaction - Created: {}", created_at.format("%Y-%m-%d %H:%M:%S")),
            "timestamp": created_at.format("%Y-%m-%dT%H:%M:%S%.fZ").to_string()
        });

        // Insert event
        let event_id = sqlx::query_scalar::<_, i64>(
            r#"
            INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
            VALUES ($1, 'transaction', $2, 'TRANSACTION_CREATED', 1, $3, $4)
            RETURNING id
            "#
        )
        .bind(user_id)
        .bind(txn_id)
        .bind(&event_data)
        .bind(created_at)
        .fetch_one(&*state.db_pool)
        .await;

        match event_id {
            Ok(eid) => {
                // Update transaction's last_event_id
                let _ = sqlx::query(
                    r#"
                    UPDATE transactions_projection 
                    SET last_event_id = $1 
                    WHERE id = $2
                    "#
                )
                .bind(eid)
                .bind(txn_id)
                .execute(&*state.db_pool)
                .await;

                created_count += 1;
            }
            Err(e) => {
                tracing::error!("Error creating event for transaction {}: {:?}", txn_id, e);
                error_count += 1;
            }
        }
    }

    Ok(Json(serde_json::json!({
        "message": "Backfill complete",
        "created": created_count,
        "errors": error_count,
        "total_processed": total_count
    })))
}

pub async fn get_contacts(
    State(state): State<AppState>,
) -> Result<Json<Vec<ContactResponse>>, (StatusCode, Json<serde_json::Value>)> {
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
        LEFT JOIN transactions_projection t ON t.contact_id = c.id AND t.is_deleted = false
        WHERE c.is_deleted = false
        GROUP BY c.id, c.name, c.username, c.email, c.phone, c.is_deleted, c.created_at
        ORDER BY ABS(COALESCE(SUM(
            CASE 
                WHEN t.direction = 'lent' THEN t.amount
                WHEN t.direction = 'owed' THEN -t.amount
                ELSE 0
            END
        )::BIGINT, 0)) DESC, c.name
        "#
    )
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

#[allow(dead_code)]
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
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;

    Ok(Json(transactions))
}

pub async fn get_projection_status(
    State(state): State<AppState>,
) -> Result<Json<ProjectionStatus>, (StatusCode, Json<serde_json::Value>)> {
    let last_event = sqlx::query_scalar::<_, Option<i64>>(
        "SELECT MAX(id) FROM events"
    )
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching projection status: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;

    Ok(Json(ProjectionStatus {
        last_event_id: last_event,
        projections_updated: Some(true),
        last_update: Some(chrono::Utc::now()),
    }))
}

/// Rebuild projections from all events
pub async fn rebuild_projections(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    use crate::handlers::sync::rebuild_projections_from_events;
    
    match rebuild_projections_from_events(&state).await {
        Ok(_) => Ok(Json(serde_json::json!({
            "message": "Projections rebuilt successfully"
        }))),
        Err(e) => {
            tracing::error!("Error rebuilding projections: {:?}", e);
            Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Failed to rebuild projections: {}", e)})),
            ))
        }
    }
}

