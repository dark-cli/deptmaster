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
    
    // Filter by event_type (case-insensitive)
    if let Some(event_type) = &params.event_type {
        if !event_type.is_empty() {
            query_builder.push(" AND UPPER(event_type) = UPPER(");
            query_builder.push_bind(event_type);
            query_builder.push(")");
        }
    }
    
    // Filter by aggregate_type
    if let Some(aggregate_type) = &params.aggregate_type {
        if !aggregate_type.is_empty() {
            query_builder.push(" AND aggregate_type = ");
            query_builder.push_bind(aggregate_type);
        }
    }
    
    // Filter by user_id
    if let Some(user_id) = &params.user_id {
        if !user_id.is_empty() {
            query_builder.push(" AND user_id::text = ");
            query_builder.push_bind(user_id);
        }
    }
    
    // Filter by date range
    if let Some(date_from) = &params.date_from {
        if !date_from.is_empty() {
            query_builder.push(" AND created_at >= ");
            query_builder.push_bind(date_from);
        }
    }
    
    if let Some(date_to) = &params.date_to {
        if !date_to.is_empty() {
            query_builder.push(" AND created_at <= ");
            query_builder.push_bind(date_to);
        }
    }
    
    // Search in event_data (comment, name, etc.)
    if let Some(search) = &params.search {
        if !search.is_empty() {
            let search_pattern = format!("%{}%", search);
            query_builder.push(" AND (event_data::text ILIKE ");
            query_builder.push_bind(search_pattern.clone());
            query_builder.push(" OR event_type ILIKE ");
            query_builder.push_bind(search_pattern.clone());
            query_builder.push(" OR aggregate_type ILIKE ");
            query_builder.push_bind(search_pattern);
            query_builder.push(")");
        }
    }
    
    query_builder.push(" ORDER BY created_at DESC LIMIT ");
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

#[derive(Serialize)]
pub struct EventStoreEventResponse {
    pub stream_name: String,
    pub event_id: String,
    pub event_type: String,
    pub data: serde_json::Value,
    pub metadata: Option<serde_json::Value>,
    pub stream_version: i64,
}

#[derive(Deserialize)]
pub struct EventStoreQuery {
    stream_name: Option<String>,
    limit: Option<u64>,
}

pub async fn get_eventstore_events(
    Query(params): Query<EventStoreQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<EventStoreEventResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let limit = params.limit.unwrap_or(100);
    
    if let Some(stream_name) = params.stream_name {
        // Get events from specific stream
        let events = state.eventstore
            .read_events(&stream_name, 0, Some(limit))
            .await
            .map_err(|e| {
                let error_msg = format!("{}", e);
                tracing::error!("Error reading EventStore events from stream '{}': {:?}", stream_name, e);
                (
                    StatusCode::SERVICE_UNAVAILABLE,
                    Json(serde_json::json!({
                        "error": format!("EventStore error: {}", error_msg),
                        "hint": "Make sure EventStore is running: docker-compose up -d eventstore"
                    })),
                )
            })?;
        
        // Get stream version
        let stream_version = state.eventstore
            .get_stream_version(&stream_name)
            .await
            .ok()
            .flatten()
            .unwrap_or(-1);
        
        let mut result = Vec::new();
        for (idx, event) in events.iter().enumerate() {
            let data: serde_json::Value = serde_json::from_str(&event.data)
                .unwrap_or_else(|_| serde_json::json!({"raw": event.data}));
            
            let metadata: Option<serde_json::Value> = event.metadata.as_ref()
                .and_then(|m| serde_json::from_str(m).ok());
            
            result.push(EventStoreEventResponse {
                stream_name: stream_name.clone(),
                event_id: event.event_id.clone(),
                event_type: event.event_type.clone(),
                data,
                metadata,
                stream_version: stream_version - (events.len() as i64 - idx as i64 - 1),
            });
        }
        
        Ok(Json(result))
    } else {
        // Get all streams (simplified - just return empty for now)
        // In a real implementation, you'd list all streams from EventStore
        Ok(Json(Vec::new()))
    }
}

#[derive(Serialize)]
pub struct StreamInfo {
    pub stream_name: String,
    pub version: Option<i64>,
    pub event_count: usize,
}

pub async fn get_eventstore_streams(
    State(state): State<AppState>,
) -> Result<Json<Vec<StreamInfo>>, (StatusCode, Json<serde_json::Value>)> {
    // Get all contact and transaction streams from projections
    let contact_streams: Vec<(uuid::Uuid,)> = sqlx::query_as(
        "SELECT id FROM contacts_projection WHERE is_deleted = false"
    )
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching contact streams: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;
    
    let transaction_streams: Vec<(uuid::Uuid,)> = sqlx::query_as(
        "SELECT id FROM transactions_projection WHERE is_deleted = false"
    )
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching transaction streams: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {}", e)})),
        )
    })?;
    
    let mut streams = Vec::new();
    
    // Get contact streams
    for (id,) in contact_streams {
        let stream_name = format!("contact-{}", id);
        let version = state.eventstore
            .get_stream_version(&stream_name)
            .await
            .ok()
            .flatten();
        
        let event_count = if let Ok(events) = state.eventstore
            .read_events(&stream_name, 0, None)
            .await
        {
            events.len()
        } else {
            0
        };
        
        streams.push(StreamInfo {
            stream_name,
            version,
            event_count,
        });
    }
    
    // Get transaction streams
    for (id,) in transaction_streams {
        let stream_name = format!("transaction-{}", id);
        let version = state.eventstore
            .get_stream_version(&stream_name)
            .await
            .ok()
            .flatten();
        
        let event_count = if let Ok(events) = state.eventstore
            .read_events(&stream_name, 0, None)
            .await
        {
            events.len()
        } else {
            0
        };
        
        streams.push(StreamInfo {
            stream_name,
            version,
            event_count,
        });
    }
    
    Ok(Json(streams))
}
