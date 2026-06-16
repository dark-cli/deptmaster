//! Transaction-level domain types: direction, type, currency.
//!
//! These mirror the client's existing typed enums (formerly in
//! `client::models`) but live here so both the server and the applier
//! can speak them directly. The serde rename rules are the wire format —
//! changing them is a wire-protocol break.

use serde::{Deserialize, Serialize};
use std::fmt;

// ============ DIRECTION ============

/// Which way a debt flows. Used as the SIGN of a transaction's amount in
/// the projection. Wire format: lowercase (`"owed"` / `"lent"`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TransactionDirection {
    /// The contact owes us money (we are the lender).
    Owed,
    /// We owe the contact money (we are the borrower).
    Lent,
}

impl TransactionDirection {
    pub fn as_str(&self) -> &'static str {
        match self {
            TransactionDirection::Owed => "owed",
            TransactionDirection::Lent => "lent",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "owed" => Some(TransactionDirection::Owed),
            "lent" => Some(TransactionDirection::Lent),
            _ => None,
        }
    }

    /// Multiplier applied to the raw amount when computing a contact's
    /// balance: positive when the contact owes us, negative when we owe
    /// them. Centralizing the sign here keeps every balance / SUM in
    /// lockstep across server + client.
    pub fn sign(&self) -> i64 {
        match self {
            TransactionDirection::Owed => 1,
            TransactionDirection::Lent => -1,
        }
    }
}

impl fmt::Display for TransactionDirection {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

// ============ TYPE ============

/// What kind of obligation the transaction represents. Wire format:
/// lowercase (`"money"` / `"item"`). The DB column is named `type`
/// (reserved word in many SQL dialects but quoted in the schema).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TransactionType {
    Money,
    Item,
}

impl TransactionType {
    pub fn as_str(&self) -> &'static str {
        match self {
            TransactionType::Money => "money",
            TransactionType::Item => "item",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "money" => Some(TransactionType::Money),
            "item" => Some(TransactionType::Item),
            _ => None,
        }
    }
}

impl fmt::Display for TransactionType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

// ============ CURRENCY ============

/// Supported currency codes (ISO-4217). Wire format: UPPERCASE.
/// Variant list is the closed set the UI currently exposes; expanding it
/// is a coordinated wire change.
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

impl fmt::Display for Currency {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn direction_roundtrip() {
        for d in [TransactionDirection::Owed, TransactionDirection::Lent] {
            assert_eq!(TransactionDirection::from_str(d.as_str()), Some(d));
        }
    }

    #[test]
    fn direction_sign() {
        assert_eq!(TransactionDirection::Owed.sign(), 1);
        assert_eq!(TransactionDirection::Lent.sign(), -1);
    }

    #[test]
    fn direction_serde_lowercase() {
        let json = serde_json::to_string(&TransactionDirection::Owed).unwrap();
        assert_eq!(json, "\"owed\"");
        let parsed: TransactionDirection = serde_json::from_str("\"lent\"").unwrap();
        assert_eq!(parsed, TransactionDirection::Lent);
    }

    #[test]
    fn type_roundtrip() {
        for t in [TransactionType::Money, TransactionType::Item] {
            assert_eq!(TransactionType::from_str(t.as_str()), Some(t));
        }
    }

    #[test]
    fn currency_uppercases_from_str() {
        assert_eq!(Currency::from_str("usd"), Some(Currency::USD));
        assert_eq!(Currency::from_str("iqd"), Some(Currency::IQD));
        assert_eq!(Currency::from_str("xxx"), None);
    }

    #[test]
    fn currency_default_is_iqd() {
        assert_eq!(Currency::default(), Currency::IQD);
    }
}
