use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct Contact {
    pub id: String,
    pub name: String,
    pub username: Option<String>,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub notes: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    #[serde(default)]
    pub is_synced: bool,
    /// Net balance: positive = they owe you, negative = you owe them (in smallest currency unit)
    #[serde(default)]
    pub balance: i64,
    pub wallet_id: Option<String>,
}

impl Contact {
    pub fn copy_with(
        &self,
        name: Option<&str>,
        username: Option<Option<&str>>,
        phone: Option<Option<&str>>,
        email: Option<Option<&str>>,
        notes: Option<Option<&str>>,
        balance: Option<i64>,
        wallet_id: Option<Option<&str>>,
    ) -> Self {
        Contact {
            name: name.unwrap_or(&self.name).to_string(),
            username: username.unwrap_or(self.username.as_deref()).map(String::from),
            phone: phone.unwrap_or(self.phone.as_deref()).map(String::from),
            email: email.unwrap_or(self.email.as_deref()).map(String::from),
            notes: notes.unwrap_or(self.notes.as_deref()).map(String::from),
            balance: balance.unwrap_or(self.balance),
            wallet_id: wallet_id.unwrap_or(self.wallet_id.as_deref()).map(String::from),
            ..self.clone()
        }
    }
}
