use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize};
use uuid::Uuid;

/// Strongly-typed domain events replacing generic Event struct
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DomainEvent {
    // Contact events
    ContactCreated {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        name: String,
        #[serde(default)]
        username: Option<String>,
        #[serde(default)]
        phone: Option<String>,
        #[serde(default)]
        email: Option<String>,
        #[serde(default)]
        notes: Option<String>,
    },
    ContactUpdated {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        username: Option<String>,
        #[serde(default)]
        phone: Option<String>,
        #[serde(default)]
        email: Option<String>,
        #[serde(default)]
        notes: Option<String>,
    },
    ContactDeleted {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        comment: Option<String>,
    },
    ContactUndone {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        undone_event_id: Uuid,
    },

    // Transaction events
    TransactionCreated {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        contact_id: Uuid,
        amount: i64,
        direction: String, // "lent" or "owed"
        #[serde(default)]
        transaction_type: Option<String>,
        #[serde(default)]
        currency: Option<String>,
        #[serde(default)]
        description: Option<String>,
        #[serde(default)]
        transaction_date: Option<DateTime<Utc>>,
        #[serde(default)]
        due_date: Option<DateTime<Utc>>,
    },
    TransactionUpdated {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        contact_id: Option<Uuid>,
        #[serde(default)]
        amount: Option<i64>,
        #[serde(default)]
        direction: Option<String>,
        #[serde(default)]
        transaction_type: Option<String>,
        #[serde(default)]
        currency: Option<String>,
        #[serde(default)]
        description: Option<String>,
        #[serde(default)]
        transaction_date: Option<DateTime<Utc>>,
        #[serde(default)]
        due_date: Option<DateTime<Utc>>,
    },
    TransactionDeleted {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        comment: Option<String>,
    },
    TransactionUndone {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        undone_event_id: Uuid,
    },

    // Permission events
    WalletUserAdded {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    WalletUserRoleChanged {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    WalletUserRemoved {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupCreated {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupRenamed {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupDeleted {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupMemberAdded {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupMemberRemoved {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupCreated {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupRenamed {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupDeleted {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupMemberAdded {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupMemberRemoved {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
    PermissionMatrixSet {
        id: Uuid,
        aggregate_id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
        version: i32,
        idempotency_key: Option<String>,
        #[serde(default)]
        data: serde_json::Value,
    },
}

impl DomainEvent {
    /// Get the aggregate type (contact, transaction, permission)
    pub fn aggregate_type(&self) -> &'static str {
        match self {
            DomainEvent::ContactCreated { .. }
            | DomainEvent::ContactUpdated { .. }
            | DomainEvent::ContactDeleted { .. }
            | DomainEvent::ContactUndone { .. } => "contact",
            DomainEvent::TransactionCreated { .. }
            | DomainEvent::TransactionUpdated { .. }
            | DomainEvent::TransactionDeleted { .. }
            | DomainEvent::TransactionUndone { .. } => "transaction",
            _ => "permission",
        }
    }

    /// Get the event type string
    pub fn event_type(&self) -> &'static str {
        match self {
            DomainEvent::ContactCreated { .. } => "CREATED",
            DomainEvent::ContactUpdated { .. } => "UPDATED",
            DomainEvent::ContactDeleted { .. } => "DELETED",
            DomainEvent::ContactUndone { .. } => "UNDO",
            DomainEvent::TransactionCreated { .. } => "CREATED",
            DomainEvent::TransactionUpdated { .. } => "UPDATED",
            DomainEvent::TransactionDeleted { .. } => "DELETED",
            DomainEvent::TransactionUndone { .. } => "UNDO",
            DomainEvent::WalletUserAdded { .. } => "WALLET_USER_ADDED",
            DomainEvent::WalletUserRoleChanged { .. } => "WALLET_USER_ROLE_CHANGED",
            DomainEvent::WalletUserRemoved { .. } => "WALLET_USER_REMOVED",
            DomainEvent::UserGroupCreated { .. } => "USER_GROUP_CREATED",
            DomainEvent::UserGroupRenamed { .. } => "USER_GROUP_RENAMED",
            DomainEvent::UserGroupDeleted { .. } => "USER_GROUP_DELETED",
            DomainEvent::UserGroupMemberAdded { .. } => "USER_GROUP_MEMBER_ADDED",
            DomainEvent::UserGroupMemberRemoved { .. } => "USER_GROUP_MEMBER_REMOVED",
            DomainEvent::ContactGroupCreated { .. } => "CONTACT_GROUP_CREATED",
            DomainEvent::ContactGroupRenamed { .. } => "CONTACT_GROUP_RENAMED",
            DomainEvent::ContactGroupDeleted { .. } => "CONTACT_GROUP_DELETED",
            DomainEvent::ContactGroupMemberAdded { .. } => "CONTACT_GROUP_MEMBER_ADDED",
            DomainEvent::ContactGroupMemberRemoved { .. } => "CONTACT_GROUP_MEMBER_REMOVED",
            DomainEvent::PermissionMatrixSet { .. } => "PERMISSION_MATRIX_SET",
        }
    }

    /// Get base fields
    pub fn id(&self) -> Uuid {
        match self {
            DomainEvent::ContactCreated { id, .. }
            | DomainEvent::ContactUpdated { id, .. }
            | DomainEvent::ContactDeleted { id, .. }
            | DomainEvent::ContactUndone { id, .. }
            | DomainEvent::TransactionCreated { id, .. }
            | DomainEvent::TransactionUpdated { id, .. }
            | DomainEvent::TransactionDeleted { id, .. }
            | DomainEvent::TransactionUndone { id, .. }
            | DomainEvent::WalletUserAdded { id, .. }
            | DomainEvent::WalletUserRoleChanged { id, .. }
            | DomainEvent::WalletUserRemoved { id, .. }
            | DomainEvent::UserGroupCreated { id, .. }
            | DomainEvent::UserGroupRenamed { id, .. }
            | DomainEvent::UserGroupDeleted { id, .. }
            | DomainEvent::UserGroupMemberAdded { id, .. }
            | DomainEvent::UserGroupMemberRemoved { id, .. }
            | DomainEvent::ContactGroupCreated { id, .. }
            | DomainEvent::ContactGroupRenamed { id, .. }
            | DomainEvent::ContactGroupDeleted { id, .. }
            | DomainEvent::ContactGroupMemberAdded { id, .. }
            | DomainEvent::ContactGroupMemberRemoved { id, .. }
            | DomainEvent::PermissionMatrixSet { id, .. } => *id,
        }
    }

    pub fn aggregate_id(&self) -> Uuid {
        match self {
            DomainEvent::ContactCreated { aggregate_id, .. }
            | DomainEvent::ContactUpdated { aggregate_id, .. }
            | DomainEvent::ContactDeleted { aggregate_id, .. }
            | DomainEvent::ContactUndone { aggregate_id, .. }
            | DomainEvent::TransactionCreated { aggregate_id, .. }
            | DomainEvent::TransactionUpdated { aggregate_id, .. }
            | DomainEvent::TransactionDeleted { aggregate_id, .. }
            | DomainEvent::TransactionUndone { aggregate_id, .. }
            | DomainEvent::WalletUserAdded { aggregate_id, .. }
            | DomainEvent::WalletUserRoleChanged { aggregate_id, .. }
            | DomainEvent::WalletUserRemoved { aggregate_id, .. }
            | DomainEvent::UserGroupCreated { aggregate_id, .. }
            | DomainEvent::UserGroupRenamed { aggregate_id, .. }
            | DomainEvent::UserGroupDeleted { aggregate_id, .. }
            | DomainEvent::UserGroupMemberAdded { aggregate_id, .. }
            | DomainEvent::UserGroupMemberRemoved { aggregate_id, .. }
            | DomainEvent::ContactGroupCreated { aggregate_id, .. }
            | DomainEvent::ContactGroupRenamed { aggregate_id, .. }
            | DomainEvent::ContactGroupDeleted { aggregate_id, .. }
            | DomainEvent::ContactGroupMemberAdded { aggregate_id, .. }
            | DomainEvent::ContactGroupMemberRemoved { aggregate_id, .. }
            | DomainEvent::PermissionMatrixSet { aggregate_id, .. } => *aggregate_id,
        }
    }

    pub fn wallet_id(&self) -> Uuid {
        match self {
            DomainEvent::ContactCreated { wallet_id, .. }
            | DomainEvent::ContactUpdated { wallet_id, .. }
            | DomainEvent::ContactDeleted { wallet_id, .. }
            | DomainEvent::ContactUndone { wallet_id, .. }
            | DomainEvent::TransactionCreated { wallet_id, .. }
            | DomainEvent::TransactionUpdated { wallet_id, .. }
            | DomainEvent::TransactionDeleted { wallet_id, .. }
            | DomainEvent::TransactionUndone { wallet_id, .. }
            | DomainEvent::WalletUserAdded { wallet_id, .. }
            | DomainEvent::WalletUserRoleChanged { wallet_id, .. }
            | DomainEvent::WalletUserRemoved { wallet_id, .. }
            | DomainEvent::UserGroupCreated { wallet_id, .. }
            | DomainEvent::UserGroupRenamed { wallet_id, .. }
            | DomainEvent::UserGroupDeleted { wallet_id, .. }
            | DomainEvent::UserGroupMemberAdded { wallet_id, .. }
            | DomainEvent::UserGroupMemberRemoved { wallet_id, .. }
            | DomainEvent::ContactGroupCreated { wallet_id, .. }
            | DomainEvent::ContactGroupRenamed { wallet_id, .. }
            | DomainEvent::ContactGroupDeleted { wallet_id, .. }
            | DomainEvent::ContactGroupMemberAdded { wallet_id, .. }
            | DomainEvent::ContactGroupMemberRemoved { wallet_id, .. }
            | DomainEvent::PermissionMatrixSet { wallet_id, .. } => *wallet_id,
        }
    }

    pub fn user_id(&self) -> Uuid {
        match self {
            DomainEvent::ContactCreated { user_id, .. }
            | DomainEvent::ContactUpdated { user_id, .. }
            | DomainEvent::ContactDeleted { user_id, .. }
            | DomainEvent::ContactUndone { user_id, .. }
            | DomainEvent::TransactionCreated { user_id, .. }
            | DomainEvent::TransactionUpdated { user_id, .. }
            | DomainEvent::TransactionDeleted { user_id, .. }
            | DomainEvent::TransactionUndone { user_id, .. }
            | DomainEvent::WalletUserAdded { user_id, .. }
            | DomainEvent::WalletUserRoleChanged { user_id, .. }
            | DomainEvent::WalletUserRemoved { user_id, .. }
            | DomainEvent::UserGroupCreated { user_id, .. }
            | DomainEvent::UserGroupRenamed { user_id, .. }
            | DomainEvent::UserGroupDeleted { user_id, .. }
            | DomainEvent::UserGroupMemberAdded { user_id, .. }
            | DomainEvent::UserGroupMemberRemoved { user_id, .. }
            | DomainEvent::ContactGroupCreated { user_id, .. }
            | DomainEvent::ContactGroupRenamed { user_id, .. }
            | DomainEvent::ContactGroupDeleted { user_id, .. }
            | DomainEvent::ContactGroupMemberAdded { user_id, .. }
            | DomainEvent::ContactGroupMemberRemoved { user_id, .. }
            | DomainEvent::PermissionMatrixSet { user_id, .. } => *user_id,
        }
    }

    pub fn created_at(&self) -> DateTime<Utc> {
        match self {
            DomainEvent::ContactCreated { created_at, .. }
            | DomainEvent::ContactUpdated { created_at, .. }
            | DomainEvent::ContactDeleted { created_at, .. }
            | DomainEvent::ContactUndone { created_at, .. }
            | DomainEvent::TransactionCreated { created_at, .. }
            | DomainEvent::TransactionUpdated { created_at, .. }
            | DomainEvent::TransactionDeleted { created_at, .. }
            | DomainEvent::TransactionUndone { created_at, .. }
            | DomainEvent::WalletUserAdded { created_at, .. }
            | DomainEvent::WalletUserRoleChanged { created_at, .. }
            | DomainEvent::WalletUserRemoved { created_at, .. }
            | DomainEvent::UserGroupCreated { created_at, .. }
            | DomainEvent::UserGroupRenamed { created_at, .. }
            | DomainEvent::UserGroupDeleted { created_at, .. }
            | DomainEvent::UserGroupMemberAdded { created_at, .. }
            | DomainEvent::UserGroupMemberRemoved { created_at, .. }
            | DomainEvent::ContactGroupCreated { created_at, .. }
            | DomainEvent::ContactGroupRenamed { created_at, .. }
            | DomainEvent::ContactGroupDeleted { created_at, .. }
            | DomainEvent::ContactGroupMemberAdded { created_at, .. }
            | DomainEvent::ContactGroupMemberRemoved { created_at, .. }
            | DomainEvent::PermissionMatrixSet { created_at, .. } => *created_at,
        }
    }

    pub fn version(&self) -> i32 {
        match self {
            DomainEvent::ContactCreated { version, .. }
            | DomainEvent::ContactUpdated { version, .. }
            | DomainEvent::ContactDeleted { version, .. }
            | DomainEvent::ContactUndone { version, .. }
            | DomainEvent::TransactionCreated { version, .. }
            | DomainEvent::TransactionUpdated { version, .. }
            | DomainEvent::TransactionDeleted { version, .. }
            | DomainEvent::TransactionUndone { version, .. }
            | DomainEvent::WalletUserAdded { version, .. }
            | DomainEvent::WalletUserRoleChanged { version, .. }
            | DomainEvent::WalletUserRemoved { version, .. }
            | DomainEvent::UserGroupCreated { version, .. }
            | DomainEvent::UserGroupRenamed { version, .. }
            | DomainEvent::UserGroupDeleted { version, .. }
            | DomainEvent::UserGroupMemberAdded { version, .. }
            | DomainEvent::UserGroupMemberRemoved { version, .. }
            | DomainEvent::ContactGroupCreated { version, .. }
            | DomainEvent::ContactGroupRenamed { version, .. }
            | DomainEvent::ContactGroupDeleted { version, .. }
            | DomainEvent::ContactGroupMemberAdded { version, .. }
            | DomainEvent::ContactGroupMemberRemoved { version, .. }
            | DomainEvent::PermissionMatrixSet { version, .. } => *version,
        }
    }

    /// Convert DomainEvent to a generic Event for database storage
    pub fn to_event(&self) -> crate::database::models::Event {
        crate::database::models::Event {
            id: self.id(),
            aggregate_id: self.aggregate_id(),
            aggregate_type: self.aggregate_type().to_string(),
            event_type: self.event_type().to_string(),
            data: serde_json::to_value(self).unwrap_or(serde_json::json!({})),
            wallet_id: self.wallet_id(),
            user_id: self.user_id(),
            created_at: self.created_at(),
            version: self.version(),
            idempotency_key: match self {
                DomainEvent::ContactCreated { idempotency_key, .. }
                | DomainEvent::ContactUpdated { idempotency_key, .. }
                | DomainEvent::ContactDeleted { idempotency_key, .. }
                | DomainEvent::ContactUndone { idempotency_key, .. }
                | DomainEvent::TransactionCreated { idempotency_key, .. }
                | DomainEvent::TransactionUpdated { idempotency_key, .. }
                | DomainEvent::TransactionDeleted { idempotency_key, .. }
                | DomainEvent::TransactionUndone { idempotency_key, .. }
                | DomainEvent::WalletUserAdded { idempotency_key, .. }
                | DomainEvent::WalletUserRoleChanged { idempotency_key, .. }
                | DomainEvent::WalletUserRemoved { idempotency_key, .. }
                | DomainEvent::UserGroupCreated { idempotency_key, .. }
                | DomainEvent::UserGroupRenamed { idempotency_key, .. }
                | DomainEvent::UserGroupDeleted { idempotency_key, .. }
                | DomainEvent::UserGroupMemberAdded { idempotency_key, .. }
                | DomainEvent::UserGroupMemberRemoved { idempotency_key, .. }
                | DomainEvent::ContactGroupCreated { idempotency_key, .. }
                | DomainEvent::ContactGroupRenamed { idempotency_key, .. }
                | DomainEvent::ContactGroupDeleted { idempotency_key, .. }
                | DomainEvent::ContactGroupMemberAdded { idempotency_key, .. }
                | DomainEvent::ContactGroupMemberRemoved { idempotency_key, .. }
                | DomainEvent::PermissionMatrixSet { idempotency_key, .. } => {
                    idempotency_key.clone()
                }
            },
        }
    }

    /// Convert a generic Event to DomainEvent
    pub fn from_event(event: &crate::database::models::Event) -> Result<Self, String> {
        serde_json::from_value(event.data.clone())
            .map_err(|e| format!("Failed to deserialize event: {}", e))
    }
}

// ============ HTTP Request Types ============

/// Custom deserializer for UUID strings - validates format
fn deserialize_uuid_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
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
    DateTime::parse_from_rfc3339(&s)
        .map_err(|_| serde::de::Error::custom("Invalid RFC3339 timestamp format"))?;
    Ok(s)
}

/// Sync event request with validation at deserialization boundary.
/// Invalid data is rejected during JSON parsing, before any handler logic.
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
    pub fn required_permissions(&self) -> Vec<(crate::permissions::Action, crate::permissions::Resource)> {
        use crate::permissions::{Action, Resource};

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
