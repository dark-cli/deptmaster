//! Supported currencies. UI passes the chosen code (e.g. "IQD"); no default constant in Rust.
//! Must stay in sync with client (debitum_client_core::models::Currency).

use serde::{Deserialize, Serialize};

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
