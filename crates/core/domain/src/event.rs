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

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "contact" => Some(AggregateType::Contact),
            "transaction" => Some(AggregateType::Transaction),
            "permission" => Some(AggregateType::Permission),
            _ => None,
        }
    }
}

// ============ EVENT TYPE ============

/// Discriminant of [`EventData`] that matches the `events.event_type`
/// column — the cheap typed form for code that only needs to know
/// "what kind of event is this?" without parsing the JSON payload.
/// Some variants (`Created`, `Updated`, `Deleted`, `Undo`) are shared
/// across aggregates; pair with [`AggregateType`] when full disambiguation
/// matters.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EventType {
    Created,
    Updated,
    Deleted,
    Undo,
    WalletUserAdded,
    WalletUserRoleChanged,
    WalletUserRemoved,
    UserGroupCreated,
    UserGroupUpdated,
    UserGroupDeleted,
    UserGroupMemberAdded,
    UserGroupMemberRemoved,
    ContactGroupCreated,
    ContactGroupUpdated,
    ContactGroupDeleted,
    ContactGroupMemberAdded,
    ContactGroupMemberRemoved,
    PermissionMatrixSet,
    WalletDeleted,
    OwnershipTransferred,
}

impl EventType {
    pub fn as_str(&self) -> &'static str {
        match self {
            EventType::Created => "CREATED",
            EventType::Updated => "UPDATED",
            EventType::Deleted => "DELETED",
            EventType::Undo => "UNDO",
            EventType::WalletUserAdded => "WALLET_USER_ADDED",
            EventType::WalletUserRoleChanged => "WALLET_USER_ROLE_CHANGED",
            EventType::WalletUserRemoved => "WALLET_USER_REMOVED",
            EventType::UserGroupCreated => "USER_GROUP_CREATED",
            // Canonical wire string is "RENAMED" (what handlers emit and what the
            // DB stores). `from_str` accepts both "RENAMED" and "UPDATED" for
            // backward compat with any code path that still says UPDATED.
            EventType::UserGroupUpdated => "USER_GROUP_RENAMED",
            EventType::UserGroupDeleted => "USER_GROUP_DELETED",
            EventType::UserGroupMemberAdded => "USER_GROUP_MEMBER_ADDED",
            EventType::UserGroupMemberRemoved => "USER_GROUP_MEMBER_REMOVED",
            EventType::ContactGroupCreated => "CONTACT_GROUP_CREATED",
            EventType::ContactGroupUpdated => "CONTACT_GROUP_RENAMED",
            EventType::ContactGroupDeleted => "CONTACT_GROUP_DELETED",
            EventType::ContactGroupMemberAdded => "CONTACT_GROUP_MEMBER_ADDED",
            EventType::ContactGroupMemberRemoved => "CONTACT_GROUP_MEMBER_REMOVED",
            EventType::PermissionMatrixSet => "PERMISSION_MATRIX_SET",
            EventType::WalletDeleted => "WALLET_DELETED",
            EventType::OwnershipTransferred => "OWNERSHIP_TRANSFERRED",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "CREATED" => Some(EventType::Created),
            "UPDATED" => Some(EventType::Updated),
            "DELETED" => Some(EventType::Deleted),
            "UNDO" => Some(EventType::Undo),
            "WALLET_USER_ADDED" => Some(EventType::WalletUserAdded),
            "WALLET_USER_ROLE_CHANGED" => Some(EventType::WalletUserRoleChanged),
            "WALLET_USER_REMOVED" => Some(EventType::WalletUserRemoved),
            "USER_GROUP_CREATED" => Some(EventType::UserGroupCreated),
            // Accept both wire spellings ("RENAMED" is canonical / live data;
            // "UPDATED" survives in older paths). See `as_str`.
            "USER_GROUP_RENAMED" | "USER_GROUP_UPDATED" => Some(EventType::UserGroupUpdated),
            "USER_GROUP_DELETED" => Some(EventType::UserGroupDeleted),
            "USER_GROUP_MEMBER_ADDED" => Some(EventType::UserGroupMemberAdded),
            "USER_GROUP_MEMBER_REMOVED" => Some(EventType::UserGroupMemberRemoved),
            "CONTACT_GROUP_CREATED" => Some(EventType::ContactGroupCreated),
            "CONTACT_GROUP_RENAMED" | "CONTACT_GROUP_UPDATED" => Some(EventType::ContactGroupUpdated),
            "CONTACT_GROUP_DELETED" => Some(EventType::ContactGroupDeleted),
            "CONTACT_GROUP_MEMBER_ADDED" => Some(EventType::ContactGroupMemberAdded),
            "CONTACT_GROUP_MEMBER_REMOVED" => Some(EventType::ContactGroupMemberRemoved),
            "PERMISSION_MATRIX_SET" => Some(EventType::PermissionMatrixSet),
            "WALLET_DELETED" => Some(EventType::WalletDeleted),
            "OWNERSHIP_TRANSFERRED" => Some(EventType::OwnershipTransferred),
            _ => None,
        }
    }

    pub fn is_undo(&self) -> bool {
        matches!(self, EventType::Undo)
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
        direction: crate::TransactionDirection,
        #[serde(default)]
        transaction_type: Option<crate::TransactionType>,
        #[serde(default)]
        currency: Option<crate::Currency>,
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
        direction: Option<crate::TransactionDirection>,
        #[serde(default)]
        transaction_type: Option<crate::TransactionType>,
        #[serde(default)]
        currency: Option<crate::Currency>,
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
