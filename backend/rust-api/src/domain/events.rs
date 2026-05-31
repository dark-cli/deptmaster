use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize};
use uuid::Uuid;

// ============ AGGREGATE TYPE ENUM ============

/// Strongly typed aggregate types. Use instead of string matching.
/// Add new types here as the system grows (user, team, etc.)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AggregateType {
    Contact,
    Transaction,
    Permission,
}

impl AggregateType {
    pub fn as_str(&self) -> &'static str {
        match self {
            AggregateType::Contact => "contact",
            AggregateType::Transaction => "transaction",
            AggregateType::Permission => "permission",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "contact" => Some(AggregateType::Contact),
            "transaction" => Some(AggregateType::Transaction),
            "permission" => Some(AggregateType::Permission),
            _ => None,
        }
    }
}

// ============ EVENT DATA PAYLOAD ============

/// Strongly typed event data payload. Each variant carries only its specific fields.
/// Serialized with #[serde(tag = "type")], so each variant is discriminated by a "type" field.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum EventData {
    // Contact events
    ContactCreated {
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
        #[serde(default)]
        comment: Option<String>,
    },
    ContactUndone {
        undone_event_id: String,
    },

    // Transaction events
    TransactionCreated {
        contact_id: Uuid,
        amount: i64,
        direction: String,
        #[serde(default)]
        transaction_type: Option<String>,
        #[serde(default)]
        currency: Option<String>,
        #[serde(default)]
        description: Option<String>,
        #[serde(default)]
        transaction_date: Option<String>,
        #[serde(default)]
        due_date: Option<String>,
    },
    TransactionUpdated {
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
        transaction_date: Option<String>,
        #[serde(default)]
        due_date: Option<String>,
    },
    TransactionDeleted {
        #[serde(default)]
        comment: Option<String>,
    },
    TransactionUndone {
        undone_event_id: String,
    },

    // Permission events (14 variants with generic untyped data)
    WalletUserAdded {
        #[serde(default)]
        data: serde_json::Value,
    },
    WalletUserRoleChanged {
        #[serde(default)]
        data: serde_json::Value,
    },
    WalletUserRemoved {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupCreated {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupUpdated {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupDeleted {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupMemberAdded {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupMemberRemoved {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupCreated {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupUpdated {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupDeleted {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupMemberAdded {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupMemberRemoved {
        #[serde(default)]
        data: serde_json::Value,
    },
    PermissionMatrixSet {
        #[serde(default)]
        data: serde_json::Value,
    },
}

impl EventData {
    /// Get the aggregate type for this event data
    pub fn aggregate_type(&self) -> AggregateType {
        match self {
            EventData::ContactCreated { .. }
            | EventData::ContactUpdated { .. }
            | EventData::ContactDeleted { .. }
            | EventData::ContactUndone { .. } => AggregateType::Contact,
            EventData::TransactionCreated { .. }
            | EventData::TransactionUpdated { .. }
            | EventData::TransactionDeleted { .. }
            | EventData::TransactionUndone { .. } => AggregateType::Transaction,
            EventData::WalletUserAdded { .. }
            | EventData::WalletUserRoleChanged { .. }
            | EventData::WalletUserRemoved { .. }
            | EventData::UserGroupCreated { .. }
            | EventData::UserGroupUpdated { .. }
            | EventData::UserGroupDeleted { .. }
            | EventData::UserGroupMemberAdded { .. }
            | EventData::UserGroupMemberRemoved { .. }
            | EventData::ContactGroupCreated { .. }
            | EventData::ContactGroupUpdated { .. }
            | EventData::ContactGroupDeleted { .. }
            | EventData::ContactGroupMemberAdded { .. }
            | EventData::ContactGroupMemberRemoved { .. }
            | EventData::PermissionMatrixSet { .. } => AggregateType::Permission,
        }
    }

    /// Get the event type string
    pub fn event_type(&self) -> &'static str {
        match self {
            EventData::ContactCreated { .. } => "CREATED",
            EventData::ContactUpdated { .. } => "UPDATED",
            EventData::ContactDeleted { .. } => "DELETED",
            EventData::ContactUndone { .. } => "UNDO",
            EventData::TransactionCreated { .. } => "CREATED",
            EventData::TransactionUpdated { .. } => "UPDATED",
            EventData::TransactionDeleted { .. } => "DELETED",
            EventData::TransactionUndone { .. } => "UNDO",
            EventData::WalletUserAdded { .. } => "WALLET_USER_ADDED",
            EventData::WalletUserRoleChanged { .. } => "WALLET_USER_ROLE_CHANGED",
            EventData::WalletUserRemoved { .. } => "WALLET_USER_REMOVED",
            EventData::UserGroupCreated { .. } => "USER_GROUP_CREATED",
            EventData::UserGroupUpdated { .. } => "USER_GROUP_UPDATED",
            EventData::UserGroupDeleted { .. } => "USER_GROUP_DELETED",
            EventData::UserGroupMemberAdded { .. } => "USER_GROUP_MEMBER_ADDED",
            EventData::UserGroupMemberRemoved { .. } => "USER_GROUP_MEMBER_REMOVED",
            EventData::ContactGroupCreated { .. } => "CONTACT_GROUP_CREATED",
            EventData::ContactGroupUpdated { .. } => "CONTACT_GROUP_UPDATED",
            EventData::ContactGroupDeleted { .. } => "CONTACT_GROUP_DELETED",
            EventData::ContactGroupMemberAdded { .. } => "CONTACT_GROUP_MEMBER_ADDED",
            EventData::ContactGroupMemberRemoved { .. } => "CONTACT_GROUP_MEMBER_REMOVED",
            EventData::PermissionMatrixSet { .. } => "PERMISSION_MATRIX_SET",
        }
    }
}

// ============ EVENT APPLIER TRAIT ============

/// Trait for events that know how to apply themselves during projection rebuilds.
/// Each aggregate type implements this to handle its own application logic.
#[async_trait]
pub trait EventApplier: Send + Sync {
    /// Apply this event to the database during sync or rebuild
    async fn apply(
        &self,
        pool: &sqlx::PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
        event_db_id: i64,
        created_at: chrono::NaiveDateTime,
    ) -> Result<(), sqlx::Error>;

    /// Clear all projections/data for this aggregate type in a wallet during rebuild with UNDO events
    async fn clear_for_rebuild(
        &self,
        pool: &sqlx::PgPool,
        wallet_id: Uuid,
    ) -> Result<(), sqlx::Error>;

    /// Get the aggregate type for this event (contact, transaction, permission, etc.)
    fn aggregate_type(&self) -> &'static str;
}

// ============ DOMAIN EVENT ============

/// Strongly-typed domain event with metadata in the struct and payload in EventData enum.
/// This separates concerns: metadata (id, wallet_id, user_id, created_at, version) from
/// event-specific payload (in event_data).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainEvent {
    pub id: Uuid,
    pub aggregate_id: Uuid,
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    #[serde(deserialize_with = "deserialize_datetime_utc")]
    pub created_at: DateTime<Utc>,
    pub version: i32,
    pub idempotency_key: Option<String>,
    pub event_data: EventData,
}

impl DomainEvent {
    /// Get the strongly-typed aggregate type for this event
    pub fn aggregate_type_enum(&self) -> AggregateType {
        self.event_data.aggregate_type()
    }

    /// Get the aggregate type as a string (for database storage)
    pub fn aggregate_type(&self) -> &'static str {
        self.aggregate_type_enum().as_str()
    }

    /// Get the event type string
    pub fn event_type(&self) -> &'static str {
        self.event_data.event_type()
    }

    /// Convert DomainEvent to a generic Event for database storage
    pub fn to_event(&self) -> crate::database::models::Event {
        crate::database::models::Event {
            id: self.id,
            aggregate_id: self.aggregate_id,
            aggregate_type: self.aggregate_type().to_string(),
            event_type: self.event_type().to_string(),
            data: serde_json::to_value(self).unwrap_or(serde_json::json!({})),
            wallet_id: self.wallet_id,
            user_id: self.user_id,
            created_at: self.created_at,
            version: self.version,
            idempotency_key: self.idempotency_key.clone(),
        }
    }

    /// Convert a generic Event to DomainEvent
    pub fn from_event(event: &crate::database::models::Event) -> Result<Self, String> {
        serde_json::from_value(event.data.clone())
            .map_err(|e| format!("Failed to deserialize event: {}", e))
    }

    /// Get permission metadata for this event
    pub fn permission_metadata(
        &self,
    ) -> Vec<(crate::permissions::Action, crate::permissions::Resource)> {
        use crate::permissions::{Action, Resource};

        match &self.event_data {
            // Contact events
            EventData::ContactCreated { .. } => {
                vec![(Action::ContactCreate, Resource::AllContacts)]
            }
            EventData::ContactUpdated { .. } => {
                vec![(Action::ContactUpdate, Resource::Contact(self.aggregate_id))]
            }
            EventData::ContactDeleted { .. } => {
                vec![(Action::ContactDelete, Resource::Contact(self.aggregate_id))]
            }
            EventData::ContactUndone { .. } => {
                vec![(Action::ContactUpdate, Resource::Contact(self.aggregate_id))]
            }
            // Transaction events
            EventData::TransactionCreated { contact_id, .. } => {
                vec![(Action::TransactionCreate, Resource::Contact(*contact_id))]
            }
            EventData::TransactionUpdated { .. } => {
                vec![(
                    Action::TransactionUpdate,
                    Resource::Transaction(self.aggregate_id),
                )]
            }
            EventData::TransactionDeleted { .. } => {
                vec![(
                    Action::TransactionDelete,
                    Resource::Transaction(self.aggregate_id),
                )]
            }
            EventData::TransactionUndone { .. } => {
                vec![(
                    Action::TransactionUpdate,
                    Resource::Transaction(self.aggregate_id),
                )]
            }
            // Permission events
            EventData::WalletUserAdded { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::WalletUserRemoved { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::WalletUserRoleChanged { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupCreated { .. } => {
                vec![(Action::UserGroupCreate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupUpdated { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupDeleted { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupMemberAdded { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupMemberRemoved { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupCreated { .. } => {
                vec![(Action::ContactGroupCreate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupUpdated { .. } => {
                vec![(Action::ContactGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupDeleted { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupMemberAdded { .. } => {
                vec![(Action::ContactGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupMemberRemoved { .. } => {
                vec![(Action::ContactGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::PermissionMatrixSet { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
        }
    }
}


/// Custom deserializer for DateTime<Utc> from RFC3339 string
fn deserialize_datetime_utc<'de, D>(deserializer: D) -> Result<DateTime<Utc>, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    DateTime::parse_from_rfc3339(&s)
        .map(|dt| dt.with_timezone(&Utc))
        .map_err(|_| serde::de::Error::custom("Invalid RFC3339 timestamp format"))
}