use uuid::Uuid;
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct User {
    pub id: Uuid,
    pub email: Option<String>,
    pub username: String,
    pub password_hash: String,
    pub created_at: NaiveDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct UserSettings {
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    pub default_contact_group_ids: Vec<Uuid>,
    pub default_transaction_group_ids: Vec<Uuid>,
}
