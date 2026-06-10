use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Transaction {
    pub id: Uuid,
    pub from_contact_id: Uuid,
    pub to_contact_id: Uuid,
    pub amount: i64,
    pub description: Option<String>,
    pub wallet_id: Uuid,
    pub due_date: Option<NaiveDate>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub version: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct TransactionProjection {
    pub id: Uuid,
    pub from_contact_id: Uuid,
    pub to_contact_id: Uuid,
    pub amount: i64,
    pub description: Option<String>,
    pub wallet_id: Uuid,
    pub due_date: Option<NaiveDate>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub version: i32,
}
