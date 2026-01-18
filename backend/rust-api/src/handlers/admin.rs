use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{Json, Html},
};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Row, postgres::PgRow};
use crate::AppState;

#[derive(Deserialize)]
pub struct EventQuery {
    limit: Option<i64>,
    offset: Option<i64>,
}

#[derive(Serialize)]
pub struct EventResponse {
    pub event_id: String,
    pub aggregate_type: String,
    pub event_type: String,
    pub user_id: String,
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
            created_at: row.try_get("created_at")?,
            event_data: row.try_get("event_data")?,
        })
    }
}

#[derive(Serialize)]
pub struct ContactResponse {
    pub id: String,
    pub name: String,
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

    let events = sqlx::query_as::<_, EventResponse>(
        r#"
        SELECT 
            event_id,
            aggregate_type,
            event_type,
            user_id,
            created_at,
            event_data
        FROM events
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
        "#
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(&*state.db_pool)
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

pub async fn get_contacts(
    State(state): State<AppState>,
) -> Result<Json<Vec<ContactResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let contacts = sqlx::query_as::<_, ContactResponse>(
        r#"
        SELECT 
            c.id,
            c.name,
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
        GROUP BY c.id, c.name, c.email, c.phone, c.is_deleted, c.created_at
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
