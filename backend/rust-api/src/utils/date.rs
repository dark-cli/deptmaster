//! Serde helpers for chrono date types (use data types, not raw strings).

use chrono::NaiveDate;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

const DATE_FORMAT: &str = "%Y-%m-%d";

/// Serialize NaiveDate as "YYYY-MM-DD". Used with #[serde(with = "crate::utils::date")].
#[allow(dead_code)]
pub fn serialize<S>(date: &NaiveDate, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    date.format(DATE_FORMAT).to_string().serialize(serializer)
}

/// Deserialize NaiveDate from "YYYY-MM-DD" string.
pub fn deserialize<'de, D>(deserializer: D) -> Result<NaiveDate, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    NaiveDate::parse_from_str(&s, DATE_FORMAT).map_err(serde::de::Error::custom)
}

/// Deserialize Option<NaiveDate> from null or "YYYY-MM-DD" string.
pub fn deserialize_opt<'de, D>(deserializer: D) -> Result<Option<NaiveDate>, D::Error>
where
    D: Deserializer<'de>,
{
    let opt = Option::<String>::deserialize(deserializer)?;
    match opt {
        None => Ok(None),
        Some(s) if s.is_empty() => Ok(None),
        Some(s) => NaiveDate::parse_from_str(&s, DATE_FORMAT)
            .map(Some)
            .map_err(serde::de::Error::custom),
    }
}
