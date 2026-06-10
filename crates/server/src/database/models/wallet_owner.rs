use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct WalletOwner {
    pub id: Uuid,
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    pub created_at: NaiveDateTime,
}
