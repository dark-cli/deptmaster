use serde::{Deserialize, Deserializer};
use uuid::Uuid;
use super::super::super::domain::DomainEvent;

/// Custom deserializer for UUID strings - validates format
fn deserialize_uuid_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    // Validate that it's a valid UUID format
    Uuid::parse_str(&s).map_err(serde::de::Error::custom)?;
    Ok(s)
}

/// Custom deserializer for aggregate_type - validates against allowed values
fn deserialize_aggregate_type<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    match s.as_str() {
        "contact" | "transaction" | "permission" => Ok(s),
        _ => Err(serde::de::Error::custom(format!(
            "Invalid aggregate_type '{}'. Must be one of: contact, transaction, permission",
            s
        ))),
    }
}

/// Custom deserializer for event_type - validates against allowed values
fn deserialize_event_type<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    match s.as_str() {
        // Contact/Transaction events
        "CREATED" | "UPDATED" | "DELETED" | "UNDO" => Ok(s),
        // Permission events
        "WALLET_USER_ADDED" | "WALLET_USER_ROLE_CHANGED" | "WALLET_USER_REMOVED"
        | "USER_GROUP_CREATED" | "USER_GROUP_RENAMED" | "USER_GROUP_DELETED"
        | "USER_GROUP_MEMBER_ADDED" | "USER_GROUP_MEMBER_REMOVED"
        | "CONTACT_GROUP_CREATED" | "CONTACT_GROUP_RENAMED" | "CONTACT_GROUP_DELETED"
        | "CONTACT_GROUP_MEMBER_ADDED" | "CONTACT_GROUP_MEMBER_REMOVED"
        | "PERMISSION_MATRIX_SET" => Ok(s),
        _ => Err(serde::de::Error::custom(format!(
            "Invalid event_type '{}'. Must be a valid event type (CREATED, UPDATED, DELETED, UNDO, or permission event)",
            s
        ))),
    }
}

/// Custom deserializer for RFC3339 timestamp - validates format
fn deserialize_timestamp<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    // Validate that it's a valid RFC3339 timestamp
    chrono::DateTime::parse_from_rfc3339(&s)
        .map_err(|_| serde::de::Error::custom("Invalid RFC3339 timestamp format"))?;
    Ok(s)
}

/// Sync event request with validation at deserialization boundary.
/// Invalid data is rejected during JSON parsing, before any handler logic.
/// This struct REPLACES the old SyncEventRequest with runtime validation.
#[derive(Debug, Clone, Deserialize)]
pub struct SyncEventRequest {
    #[serde(deserialize_with = "deserialize_uuid_string")]
    pub id: String,
    #[serde(deserialize_with = "deserialize_aggregate_type")]
    pub aggregate_type: String,
    #[serde(deserialize_with = "deserialize_uuid_string")]
    pub aggregate_id: String,
    #[serde(deserialize_with = "deserialize_event_type")]
    pub event_type: String,
    pub event_data: serde_json::Value,
    #[serde(deserialize_with = "deserialize_timestamp")]
    pub timestamp: String,
    pub version: i32,
}

impl SyncEventRequest {
    /// Convert to DomainEvent with context information
    pub fn to_domain_event(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<DomainEvent, String> {

        let created_at = chrono::DateTime::parse_from_rfc3339(&self.timestamp)
            .map_err(|e| format!("Invalid timestamp: {}", e))?
            .with_timezone(&chrono::Utc);

        let id_uuid = Uuid::parse_str(&self.id)
            .map_err(|_| "Invalid 'id' UUID".to_string())?;
        let aggregate_id_uuid = Uuid::parse_str(&self.aggregate_id)
            .map_err(|_| "Invalid 'aggregate_id' UUID".to_string())?;

        match (self.aggregate_type.as_str(), self.event_type.as_str()) {
            ("contact", "CREATED") => {
                let name = self
                    .event_data
                    .get("name")
                    .and_then(|v| v.as_str())
                    .ok_or("CREATED contact requires 'name' field")?
                    .to_string();

                Ok(DomainEvent::ContactCreated {
                    id: id_uuid,
                    aggregate_id: aggregate_id_uuid,
                    wallet_id,
                    user_id,
                    created_at,
                    version: self.version,
                    idempotency_key: None,
                    name,
                    username: self.event_data.get("username").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    phone: self.event_data.get("phone").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    email: self.event_data.get("email").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    notes: self.event_data.get("notes").and_then(|v| v.as_str()).map(|s| s.to_string()),
                })
            }
            ("contact", "UPDATED") => {
                Ok(DomainEvent::ContactUpdated {
                    id: id_uuid,
                    aggregate_id: aggregate_id_uuid,
                    wallet_id,
                    user_id,
                    created_at,
                    version: self.version,
                    idempotency_key: None,
                    name: self.event_data.get("name").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    username: self.event_data.get("username").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    phone: self.event_data.get("phone").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    email: self.event_data.get("email").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    notes: self.event_data.get("notes").and_then(|v| v.as_str()).map(|s| s.to_string()),
                })
            }
            ("contact", "DELETED") => {
                Ok(DomainEvent::ContactDeleted {
                    id: id_uuid,
                    aggregate_id: aggregate_id_uuid,
                    wallet_id,
                    user_id,
                    created_at,
                    version: self.version,
                    idempotency_key: None,
                    comment: self.event_data.get("comment").and_then(|v| v.as_str()).map(|s| s.to_string()),
                })
            }
            ("contact", "UNDO") => {
                let undone_event_id_str = self
                    .event_data
                    .get("undone_event_id")
                    .and_then(|v| v.as_str())
                    .ok_or("UNDO event requires 'undone_event_id' field")?;
                let undone_uuid = Uuid::parse_str(undone_event_id_str)
                    .map_err(|_| "Invalid 'undone_event_id' UUID".to_string())?;

                Ok(DomainEvent::ContactUndone {
                    id: id_uuid,
                    aggregate_id: aggregate_id_uuid,
                    wallet_id,
                    user_id,
                    created_at,
                    version: self.version,
                    idempotency_key: None,
                    undone_event_id: undone_uuid,
                })
            }
            ("transaction", "CREATED") => {
                let contact_id_str = self
                    .event_data
                    .get("contact_id")
                    .and_then(|v| v.as_str())
                    .ok_or("CREATED transaction requires 'contact_id' field")?;
                let contact_uuid = Uuid::parse_str(contact_id_str)
                    .map_err(|_| "Invalid 'contact_id' UUID".to_string())?;

                let amount = self
                    .event_data
                    .get("amount")
                    .and_then(|v| v.as_i64())
                    .ok_or("CREATED transaction requires 'amount' field")?;

                let direction = self
                    .event_data
                    .get("direction")
                    .and_then(|v| v.as_str())
                    .ok_or("CREATED transaction requires 'direction' field")?;
                if direction != "lent" && direction != "owed" {
                    return Err("Direction must be 'lent' or 'owed'".to_string());
                }

                Ok(DomainEvent::TransactionCreated {
                    id: id_uuid,
                    aggregate_id: aggregate_id_uuid,
                    wallet_id,
                    user_id,
                    created_at,
                    version: self.version,
                    idempotency_key: None,
                    contact_id: contact_uuid,
                    amount,
                    direction: direction.to_string(),
                    transaction_type: self.event_data.get("transaction_type").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    currency: self.event_data.get("currency").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    description: self.event_data.get("description").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    transaction_date: self.event_data.get("transaction_date").and_then(|v| v.as_str()).and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok()).map(|dt| dt.with_timezone(&chrono::Utc)),
                    due_date: self.event_data.get("due_date").and_then(|v| v.as_str()).and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok()).map(|dt| dt.with_timezone(&chrono::Utc)),
                })
            }
            ("transaction", "UPDATED") => {
                let direction_val = self.event_data.get("direction").and_then(|v| v.as_str());
                if let Some(dir) = direction_val {
                    if dir != "lent" && dir != "owed" {
                        return Err("Direction must be 'lent' or 'owed'".to_string());
                    }
                }

                Ok(DomainEvent::TransactionUpdated {
                    id: id_uuid,
                    aggregate_id: aggregate_id_uuid,
                    wallet_id,
                    user_id,
                    created_at,
                    version: self.version,
                    idempotency_key: None,
                    contact_id: self.event_data.get("contact_id").and_then(|v| v.as_str()).and_then(|s| Uuid::parse_str(s).ok()),
                    amount: self.event_data.get("amount").and_then(|v| v.as_i64()),
                    direction: direction_val.map(|s| s.to_string()),
                    transaction_type: self.event_data.get("transaction_type").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    currency: self.event_data.get("currency").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    description: self.event_data.get("description").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    transaction_date: self.event_data.get("transaction_date").and_then(|v| v.as_str()).and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok()).map(|dt| dt.with_timezone(&chrono::Utc)),
                    due_date: self.event_data.get("due_date").and_then(|v| v.as_str()).and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok()).map(|dt| dt.with_timezone(&chrono::Utc)),
                })
            }
            ("transaction", "DELETED") => {
                Ok(DomainEvent::TransactionDeleted {
                    id: id_uuid,
                    aggregate_id: aggregate_id_uuid,
                    wallet_id,
                    user_id,
                    created_at,
                    version: self.version,
                    idempotency_key: None,
                    comment: self.event_data.get("comment").and_then(|v| v.as_str()).map(|s| s.to_string()),
                })
            }
            ("transaction", "UNDO") => {
                let undone_event_id_str = self
                    .event_data
                    .get("undone_event_id")
                    .and_then(|v| v.as_str())
                    .ok_or("UNDO event requires 'undone_event_id' field")?;
                let undone_uuid = Uuid::parse_str(undone_event_id_str)
                    .map_err(|_| "Invalid 'undone_event_id' UUID".to_string())?;

                Ok(DomainEvent::TransactionUndone {
                    id: id_uuid,
                    aggregate_id: aggregate_id_uuid,
                    wallet_id,
                    user_id,
                    created_at,
                    version: self.version,
                    idempotency_key: None,
                    undone_event_id: undone_uuid,
                })
            }
            _ => Err(format!("Unsupported event: {} {}", self.aggregate_type, self.event_type)),
        }
    }
}

impl SyncEventRequest {
    /// Validate event data (for events created programmatically, not deserialized from JSON)
    /// Events from JSON are already validated by serde deserializers.
    pub fn validate_data(&self) -> Option<String> {
        match (self.aggregate_type.as_str(), self.event_type.as_str()) {
            ("contact", "UNDO") | ("transaction", "UNDO") => {
                if self.event_data.get("undone_event_id").and_then(|v| v.as_str()).is_none() {
                    return Some("UNDO events must have 'undone_event_id' in event_data".to_string());
                }
                if let Some(undone_id) = self.event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                    if Uuid::parse_str(undone_id).is_err() {
                        return Some("UNDO event 'undone_event_id' must be a valid UUID".to_string());
                    }
                }
            }
            ("contact", "CREATED") => {
                if self.event_data.get("name").and_then(|v| v.as_str()).is_none() {
                    return Some("CREATED contact events must have 'name' in event_data".to_string());
                }
            }
            ("transaction", "CREATED") => {
                if self.event_data.get("amount").and_then(|v| v.as_i64()).is_none() {
                    return Some("CREATED transaction must have 'amount'".to_string());
                }
                if self.event_data.get("direction").and_then(|v| v.as_str()).is_none() {
                    return Some("CREATED transaction must have 'direction'".to_string());
                }
                if self.event_data.get("contact_id").and_then(|v| v.as_str()).is_none() {
                    return Some("CREATED transaction must have 'contact_id'".to_string());
                }
            }
            _ => {}
        }
        None
    }

    /// Get required permissions for this event
    pub fn required_permissions(&self) -> Vec<(super::super::super::permissions::Action, super::super::super::permissions::Resource)> {
        use super::super::super::permissions::{Action, Resource};

        match (self.aggregate_type.as_str(), self.event_type.as_str()) {
            // Contact events
            ("contact", "CREATED") => vec![(Action::ContactCreate, Resource::AllContacts)],
            ("contact", "UPDATED") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::ContactUpdate, Resource::Contact(id))]
                } else {
                    vec![]
                }
            }
            ("contact", "DELETED") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::ContactDelete, Resource::Contact(id))]
                } else {
                    vec![]
                }
            }
            ("contact", "UNDO") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::ContactUpdate, Resource::Contact(id))]
                } else {
                    vec![]
                }
            }
            // Transaction events
            ("transaction", "CREATED") => vec![(Action::TransactionCreate, Resource::AllTransactions)],
            ("transaction", "UPDATED") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::TransactionUpdate, Resource::Transaction(id))]
                } else {
                    vec![]
                }
            }
            ("transaction", "DELETED") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::TransactionClose, Resource::Transaction(id))]
                } else {
                    vec![]
                }
            }
            ("transaction", "UNDO") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::TransactionUpdate, Resource::Transaction(id))]
                } else {
                    vec![]
                }
            }
            _ => vec![],
        }
    }
}
