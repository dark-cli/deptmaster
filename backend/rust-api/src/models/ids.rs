//! Type aliases for entity IDs. All are UUIDs; validation happens at parse boundaries (e.g. Uuid::parse_str).
//! Use these for clarity and to avoid passing raw strings where an ID is required.

#![allow(dead_code)]

use uuid::Uuid;

pub type UserId = Uuid;
pub type WalletId = Uuid;
pub type ContactId = Uuid;
pub type TransactionId = Uuid;
pub type EventId = Uuid;

/// Parse a string into a UUID or return an error message. Use at API boundaries.
pub fn parse_uuid(id: &str, name: &str) -> Result<Uuid, String> {
    Uuid::parse_str(id).map_err(|e| format!("Invalid {}: {}", name, e))
}
