use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct User {
    pub id: Uuid,
    pub email: Option<String>,
    pub username: String,
    pub password_hash: String,
    pub created_at: NaiveDateTime,
}

// User-scoped preferences (global settings, not wallet-specific)
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct UserSettings {
    pub user_id: Uuid,
    pub dark_mode: bool,
    pub default_direction: String,
    pub flip_colors: bool,
    pub due_date_enabled: bool,
    pub default_due_date_days: i32,
    pub default_due_date_switch: bool,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

impl Default for UserSettings {
    fn default() -> Self {
        Self {
            user_id: Uuid::nil(),
            dark_mode: true,
            default_direction: "give".to_string(),
            flip_colors: false,
            due_date_enabled: false,
            default_due_date_days: 30,
            default_due_date_switch: false,
            created_at: chrono::Local::now().naive_local(),
            updated_at: chrono::Local::now().naive_local(),
        }
    }
}

// Wallet-scoped default group selections for a user
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct WalletUserSettings {
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    pub default_contact_group_ids: Vec<Uuid>,
    pub default_transaction_group_ids: Vec<Uuid>,
}
