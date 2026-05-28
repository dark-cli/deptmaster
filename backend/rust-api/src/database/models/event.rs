use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct EventRow {
    pub id: i64,
    pub event_id: Uuid,
    pub aggregate_id: Uuid,
    pub aggregate_type: String,
    pub event_type: String,
    pub data: serde_json::Value,
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub version: i32,
    pub idempotency_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub id: Uuid,
    pub aggregate_id: Uuid,
    pub aggregate_type: String,
    pub event_type: String,
    pub data: serde_json::Value,
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub version: i32,
    pub idempotency_key: Option<String>,
}

impl From<EventRow> for Event {
    fn from(row: EventRow) -> Self {
        Self {
            id: row.event_id,
            aggregate_id: row.aggregate_id,
            aggregate_type: row.aggregate_type,
            event_type: row.event_type,
            data: row.data,
            wallet_id: row.wallet_id,
            user_id: row.user_id,
            created_at: row.created_at,
            version: row.version,
            idempotency_key: row.idempotency_key,
        }
    }
}
