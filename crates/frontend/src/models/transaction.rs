use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TransactionType {
    Money,
    Item,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TransactionDirection {
    Owed,
    Lent,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct Transaction {
    pub id: String,
    pub contact_id: String,
    #[serde(rename = "type")]
    pub type_: TransactionType,
    pub direction: TransactionDirection,
    pub amount: i64,
    pub currency: String,
    pub description: Option<String>,
    pub transaction_date: chrono::NaiveDate,
    pub due_date: Option<chrono::NaiveDate>,
    pub image_paths: Vec<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub is_synced: bool,
    pub wallet_id: Option<String>,
}

impl Transaction {
    pub fn formatted_amount(&self) -> String {
        let formatted = self.amount.abs().to_string();
        let with_commas = format_number_with_commas(&formatted);
        format!("{} IQD", with_commas)
    }
}

fn format_number_with_commas(s: &str) -> String {
    let mut result = String::new();
    let chars: Vec<char> = s.chars().collect();
    let len = chars.len();
    for (i, c) in chars.into_iter().enumerate() {
        if i > 0 && (len - i) % 3 == 0 {
            result.push(',');
        }
        result.push(c);
    }
    result
}
