//! Event types — the wire format for everything pushed by the client and
//! emitted by the server. `EventData` is tagged-enum on `"type"` so each
//! variant carries only the fields it needs.
//!
//! Clients generate the event `id` (UUID v4) locally; the server stores it
//! as-is and uses `(wallet_id, id)` as the dedup + identity key. There is
//! no separate `idempotency_key` — retries send the same `id` and
//! `ON CONFLICT` handles them.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize};
use uuid::Uuid;

use crate::permission::{Action, Resource};

// ============ AGGREGATE TYPE ============

/// The aggregate (entity family) an event belongs to. Driven off `EventData`,
/// never typed by hand on the wire.
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
}

// ============ EVENT DATA ============

/// Strongly-typed event payload. Each variant carries only the fields its
/// applier needs; serialized with `#[serde(tag = "type")]` so the
/// discriminator rides on the JSON itself.
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
        #[serde(default)]
        group_ids: Vec<Uuid>,
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
        #[serde(default)]
        group_ids: Option<Vec<Uuid>>,
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
        contact_id: Uuid,
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

    // Permission events (still carry generic `data` until they grow typed schemas).
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

    // Wallet management
    WalletDeleted {
        #[serde(default)]
        reason: Option<String>,
    },
    OwnershipTransferred {
        from: Uuid,
        to: Uuid,
    },
}

impl EventData {
    /// Which aggregate this event belongs to. Derived from the variant, not
    /// the wire field, so renames stay in lockstep.
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
            | EventData::PermissionMatrixSet { .. }
            | EventData::WalletDeleted { .. }
            | EventData::OwnershipTransferred { .. } => AggregateType::Permission,
        }
    }

    /// String form of the event type for legacy code paths and DB rows.
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
            EventData::WalletDeleted { .. } => "WALLET_DELETED",
            EventData::OwnershipTransferred { .. } => "OWNERSHIP_TRANSFERRED",
        }
    }
}

// ============ DOMAIN EVENT ============

/// The full event envelope — metadata in the outer struct, payload in
/// `event_data`. This is exactly what crosses the wire between client and
/// server.
#[derive(Debug, Clone, Serialize)]
pub struct DomainEvent {
    pub id: Uuid,
    pub aggregate_id: Uuid,
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub version: i32,
    pub event_data: EventData,
}

impl<'de> Deserialize<'de> for DomainEvent {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct DomainEventDto {
            #[serde(default)]
            id: Option<Uuid>,
            aggregate_id: Uuid,
            wallet_id: Uuid,
            user_id: Uuid,
            #[serde(deserialize_with = "deserialize_datetime_utc")]
            created_at: DateTime<Utc>,
            version: i32,
            event_data: EventData,
        }

        let dto = DomainEventDto::deserialize(deserializer)?;
        let id = dto.id.unwrap_or_else(Uuid::new_v4);

        Ok(DomainEvent {
            id,
            aggregate_id: dto.aggregate_id,
            wallet_id: dto.wallet_id,
            user_id: dto.user_id,
            created_at: dto.created_at,
            version: dto.version,
            event_data: dto.event_data,
        })
    }
}

impl DomainEvent {
    pub fn aggregate_type_enum(&self) -> AggregateType {
        self.event_data.aggregate_type()
    }

    pub fn event_type(&self) -> &'static str {
        self.event_data.event_type()
    }

    /// The (action, resource) pairs that must all be permitted for this
    /// event to be accepted. Server's permission middleware reads this and
    /// fans out into matrix lookups.
    pub fn permission_metadata(&self) -> Vec<(Action, Resource)> {
        match &self.event_data {
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
            EventData::WalletUserAdded { .. }
            | EventData::WalletUserRemoved { .. }
            | EventData::WalletUserRoleChanged { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupCreated { .. } => {
                vec![(Action::UserGroupCreate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupUpdated { .. }
            | EventData::UserGroupMemberAdded { .. }
            | EventData::UserGroupMemberRemoved { .. }
            | EventData::PermissionMatrixSet { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupDeleted { .. }
            | EventData::ContactGroupDeleted { .. }
            | EventData::OwnershipTransferred { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupCreated { .. } => {
                vec![(Action::ContactGroupCreate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupUpdated { .. }
            | EventData::ContactGroupMemberAdded { .. }
            | EventData::ContactGroupMemberRemoved { .. } => {
                vec![(Action::ContactGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::WalletDeleted { .. } => {
                vec![(Action::WalletDelete, Resource::Wallet(self.wallet_id))]
            }
        }
    }
}

/// Accept any RFC3339 timestamp into a `DateTime<Utc>`. The server emits
/// RFC3339, the client stores RFC3339 — but `chrono`'s default is
/// permissive in a way we don't want here, so we constrain explicitly.
fn deserialize_datetime_utc<'de, D>(deserializer: D) -> Result<DateTime<Utc>, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    DateTime::parse_from_rfc3339(&s)
        .map(|dt| dt.with_timezone(&Utc))
        .map_err(|_| serde::de::Error::custom("Invalid RFC3339 timestamp format"))
}
