//! Strongly-typed IDs with UUID validation. Use these instead of raw strings.

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::fmt;
use std::str::FromStr;
use uuid::Uuid;

fn validate_uuid(s: &str) -> Result<String, String> {
    Uuid::parse_str(s).map_err(|e| format!("Invalid UUID: {}", e))?;
    Ok(s.to_string())
}

/// User ID (UUID). Validated on construction via `parse`/`from_str`. Inner field pub for FFI codegen.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct UserId(pub String);

/// Wallet ID (UUID). Validated on construction via `parse`/`from_str`. Inner field pub for FFI codegen.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct WalletId(pub String);

/// Contact ID (UUID). Validated on construction via `parse`/`from_str`. Inner field pub for FFI codegen.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ContactId(pub String);

/// Transaction ID (UUID). Validated on construction via `parse`/`from_str`. Inner field pub for FFI codegen.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct TransactionId(pub String);

/// Event ID (UUID). Validated on construction via `parse`/`from_str`. Inner field pub for FFI codegen.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct EventId(pub String);

macro_rules! id_serde {
    ($name:ident) => {
        impl Serialize for $name {
            fn serialize<S: Serializer>(&self, ser: S) -> Result<S::Ok, S::Error> {
                ser.serialize_str(&self.0)
            }
        }
        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D: Deserializer<'de>>(de: D) -> Result<Self, D::Error> {
                let s = String::deserialize(de)?;
                Self::from_str(&s).map_err(serde::de::Error::custom)
            }
        }
    };
}
id_serde!(UserId);
id_serde!(WalletId);
id_serde!(ContactId);
id_serde!(TransactionId);
id_serde!(EventId);

macro_rules! id_type {
    ($name:ident) => {
        impl $name {
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }
        impl FromStr for $name {
            type Err = String;
            fn from_str(s: &str) -> Result<Self, Self::Err> {
                Ok(Self(validate_uuid(s)?))
            }
        }
        impl From<$name> for String {
            fn from(id: $name) -> Self {
                id.0
            }
        }
        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                write!(f, "{}", self.0)
            }
        }
    };
}
id_type!(UserId);
id_type!(WalletId);
id_type!(ContactId);
id_type!(TransactionId);
id_type!(EventId);

impl UserId {
    pub fn parse(s: impl AsRef<str>) -> Result<Self, String> {
        Self::from_str(s.as_ref())
    }
}
impl WalletId {
    pub fn parse(s: impl AsRef<str>) -> Result<Self, String> {
        Self::from_str(s.as_ref())
    }
}
impl ContactId {
    pub fn parse(s: impl AsRef<str>) -> Result<Self, String> {
        Self::from_str(s.as_ref())
    }
}
impl TransactionId {
    pub fn parse(s: impl AsRef<str>) -> Result<Self, String> {
        Self::from_str(s.as_ref())
    }
}
impl EventId {
    pub fn parse(s: impl AsRef<str>) -> Result<Self, String> {
        Self::from_str(s.as_ref())
    }
}
