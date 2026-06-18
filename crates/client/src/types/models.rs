//! Data models for contacts, transactions, events, wallets.
//! Wire format uses strings for IDs and dates (FFI/JSON). Use ids.rs and
//! `domain::Currency` for validation internally.
//!
//! `Currency` / `TransactionType` / `TransactionDirection` are defined
//! here AND in `domain` — they're identical in serde shape, but the
//! flutter_rust_bridge codegen impls traits on these types and the orphan
//! rule forbids us from doing that on types declared in another crate.
//! Internal logic uses `domain::*` exclusively; the FFI wire layer uses
//! the local types and converts at the trait boundary (see
//! `impl From<...>` blocks below).

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
        domain::Currency::from(*self).as_str()
    }

    pub fn from_str(s: &str) -> Option<Self> {
        domain::Currency::from_str(s).map(Currency::from)
    }
}

impl std::fmt::Display for Currency {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

// ---------- conversions between FFI-layer and domain enums ----------
//
// Identity shape, so the converts are exhaustive matches the compiler
// keeps in lockstep when either side grows a variant.

impl From<Currency> for domain::Currency {
    fn from(c: Currency) -> Self {
        match c {
            Currency::IQD => domain::Currency::IQD,
            Currency::USD => domain::Currency::USD,
            Currency::EUR => domain::Currency::EUR,
            Currency::GBP => domain::Currency::GBP,
            Currency::JPY => domain::Currency::JPY,
            Currency::CHF => domain::Currency::CHF,
            Currency::CAD => domain::Currency::CAD,
            Currency::AUD => domain::Currency::AUD,
            Currency::CNY => domain::Currency::CNY,
            Currency::INR => domain::Currency::INR,
            Currency::SAR => domain::Currency::SAR,
            Currency::AED => domain::Currency::AED,
            Currency::EGP => domain::Currency::EGP,
            Currency::TRY => domain::Currency::TRY,
            Currency::BRL => domain::Currency::BRL,
            Currency::MXN => domain::Currency::MXN,
            Currency::KRW => domain::Currency::KRW,
            Currency::ZAR => domain::Currency::ZAR,
            Currency::RUB => domain::Currency::RUB,
        }
    }
}

impl From<domain::Currency> for Currency {
    fn from(c: domain::Currency) -> Self {
        match c {
            domain::Currency::IQD => Currency::IQD,
            domain::Currency::USD => Currency::USD,
            domain::Currency::EUR => Currency::EUR,
            domain::Currency::GBP => Currency::GBP,
            domain::Currency::JPY => Currency::JPY,
            domain::Currency::CHF => Currency::CHF,
            domain::Currency::CAD => Currency::CAD,
            domain::Currency::AUD => Currency::AUD,
            domain::Currency::CNY => Currency::CNY,
            domain::Currency::INR => Currency::INR,
            domain::Currency::SAR => Currency::SAR,
            domain::Currency::AED => Currency::AED,
            domain::Currency::EGP => Currency::EGP,
            domain::Currency::TRY => Currency::TRY,
            domain::Currency::BRL => Currency::BRL,
            domain::Currency::MXN => Currency::MXN,
            domain::Currency::KRW => Currency::KRW,
            domain::Currency::ZAR => Currency::ZAR,
            domain::Currency::RUB => Currency::RUB,
        }
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

impl From<TransactionType> for domain::TransactionType {
    fn from(t: TransactionType) -> Self {
        match t {
            TransactionType::Money => domain::TransactionType::Money,
            TransactionType::Item => domain::TransactionType::Item,
        }
    }
}

impl From<domain::TransactionType> for TransactionType {
    fn from(t: domain::TransactionType) -> Self {
        match t {
            domain::TransactionType::Money => TransactionType::Money,
            domain::TransactionType::Item => TransactionType::Item,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TransactionDirection {
    Owed,
    Lent,
}

impl From<TransactionDirection> for domain::TransactionDirection {
    fn from(d: TransactionDirection) -> Self {
        match d {
            TransactionDirection::Owed => domain::TransactionDirection::Owed,
            TransactionDirection::Lent => domain::TransactionDirection::Lent,
        }
    }
}

impl From<domain::TransactionDirection> for TransactionDirection {
    fn from(d: domain::TransactionDirection) -> Self {
        match d {
            domain::TransactionDirection::Owed => TransactionDirection::Owed,
            domain::TransactionDirection::Lent => TransactionDirection::Lent,
        }
    }
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
