//! Data models for contacts, transactions, events, wallets.
//! Wire format uses strings for IDs and dates (FFI/JSON). Use ids.rs and Currency for validation internally.

use serde::{Deserialize, Serialize};

/// Supported currencies. UI passes the chosen code (e.g. "IQD"); no default in Rust.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "UPPERCASE")]
pub enum Currency {
    #[default]
    IQD,
    USD,
    EUR,
    GBP,
    JPY,
    CHF,
    CAD,
    AUD,
    CNY,
    INR,
    SAR,
    AED,
    EGP,
    TRY,
    BRL,
    MXN,
    KRW,
    ZAR,
    RUB,
}

impl Currency {
    pub fn as_str(&self) -> &'static str {
        match self {
            Currency::IQD => "IQD",
            Currency::USD => "USD",
            Currency::EUR => "EUR",
            Currency::GBP => "GBP",
            Currency::JPY => "JPY",
            Currency::CHF => "CHF",
            Currency::CAD => "CAD",
            Currency::AUD => "AUD",
            Currency::CNY => "CNY",
            Currency::INR => "INR",
            Currency::SAR => "SAR",
            Currency::AED => "AED",
            Currency::EGP => "EGP",
            Currency::TRY => "TRY",
            Currency::BRL => "BRL",
            Currency::MXN => "MXN",
            Currency::KRW => "KRW",
            Currency::ZAR => "ZAR",
            Currency::RUB => "RUB",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "IQD" => Some(Currency::IQD),
            "USD" => Some(Currency::USD),
            "EUR" => Some(Currency::EUR),
            "GBP" => Some(Currency::GBP),
            "JPY" => Some(Currency::JPY),
            "CHF" => Some(Currency::CHF),
            "CAD" => Some(Currency::CAD),
            "AUD" => Some(Currency::AUD),
            "CNY" => Some(Currency::CNY),
            "INR" => Some(Currency::INR),
            "SAR" => Some(Currency::SAR),
            "AED" => Some(Currency::AED),
            "EGP" => Some(Currency::EGP),
            "TRY" => Some(Currency::TRY),
            "BRL" => Some(Currency::BRL),
            "MXN" => Some(Currency::MXN),
            "KRW" => Some(Currency::KRW),
            "ZAR" => Some(Currency::ZAR),
            "RUB" => Some(Currency::RUB),
            _ => None,
        }
    }
}

impl std::fmt::Display for Currency {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Contact (wire format: strings for IDs and dates for JSON/FFI).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct Contact {
    pub id: String,
    pub name: String,
    pub username: Option<String>,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub notes: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub is_synced: bool,
    #[serde(default)]
    pub balance: i64,
    pub wallet_id: Option<String>,
}

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

/// Transaction (wire format). Currency is enum; dates/IDs remain string for compatibility.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct Transaction {
    pub id: String,
    pub contact_id: String,
    #[serde(rename = "type")]
    pub type_: TransactionType,
    pub direction: TransactionDirection,
    pub amount: i64,
    pub currency: Currency,
    pub description: Option<String>,
    pub transaction_date: String,
    pub due_date: Option<String>,
    pub image_paths: Vec<String>,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub is_synced: bool,
    pub wallet_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Event {
    pub id: String,
    pub aggregate_type: String,
    pub aggregate_id: String,
    pub event_type: String,
    pub event_data: serde_json::Value,
    pub timestamp: String,
    pub version: i32,
    pub synced: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct Wallet {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub is_active: bool,
    pub created_by: Option<String>,
}
