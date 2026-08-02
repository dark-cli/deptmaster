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
    // Layer 1: Wallet-wide permission changes
    WalletPermissionsSet,
    // Layer 2: Member-group-to-member-group permission changes
    GroupPermissionsSet,
    // Layer 2.5: Contact-group management permission changes
    ContactGroupPermissionsSet,
    // Layer 3: Contact/transaction operational permissions
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
            EventType::WalletPermissionsSet => "WALLET_PERMISSIONS_SET",
            EventType::GroupPermissionsSet => "GROUP_PERMISSIONS_SET",
            EventType::ContactGroupPermissionsSet => "CONTACT_GROUP_PERMISSIONS_SET",
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
            "CONTACT_GROUP_RENAMED" | "CONTACT_GROUP_UPDATED" => {
                Some(EventType::ContactGroupUpdated)
            }
            "CONTACT_GROUP_DELETED" => Some(EventType::ContactGroupDeleted),
            "CONTACT_GROUP_MEMBER_ADDED" => Some(EventType::ContactGroupMemberAdded),
            "CONTACT_GROUP_MEMBER_REMOVED" => Some(EventType::ContactGroupMemberRemoved),
            "WALLET_PERMISSIONS_SET" => Some(EventType::WalletPermissionsSet),
            "GROUP_PERMISSIONS_SET" => Some(EventType::GroupPermissionsSet),
            "CONTACT_GROUP_PERMISSIONS_SET" => Some(EventType::ContactGroupPermissionsSet),
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
    WalletPermissionsSet {
        #[serde(default)]
        data: serde_json::Value,
    },
    GroupPermissionsSet {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupPermissionsSet {
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
            | EventData::WalletPermissionsSet { .. }
            | EventData::GroupPermissionsSet { .. }
            | EventData::ContactGroupPermissionsSet { .. }
            | EventData::PermissionMatrixSet { .. }
            | EventData::WalletDeleted { .. }
            | EventData::OwnershipTransferred { .. } => AggregateType::Permission,
        }
    }

    /// Serde tag for this variant (the `"type"` field on the JSON wire
    /// format, after `rename_all = "snake_case"`). Exhaustive — adding a
    /// variant to `EventData` fails compile until an arm exists here.
    /// This is the only place tag strings are spelled out.
    pub fn serde_tag(&self) -> &'static str {
        match self {
            EventData::ContactCreated { .. } => "contact_created",
            EventData::ContactUpdated { .. } => "contact_updated",
            EventData::ContactDeleted { .. } => "contact_deleted",
            EventData::ContactUndone { .. } => "contact_undone",
            EventData::TransactionCreated { .. } => "transaction_created",
            EventData::TransactionUpdated { .. } => "transaction_updated",
            EventData::TransactionDeleted { .. } => "transaction_deleted",
            EventData::TransactionUndone { .. } => "transaction_undone",
            EventData::WalletUserAdded { .. } => "wallet_user_added",
            EventData::WalletUserRoleChanged { .. } => "wallet_user_role_changed",
            EventData::WalletUserRemoved { .. } => "wallet_user_removed",
            EventData::UserGroupCreated { .. } => "user_group_created",
            EventData::UserGroupUpdated { .. } => "user_group_updated",
            EventData::UserGroupDeleted { .. } => "user_group_deleted",
            EventData::UserGroupMemberAdded { .. } => "user_group_member_added",
            EventData::UserGroupMemberRemoved { .. } => "user_group_member_removed",
            EventData::ContactGroupCreated { .. } => "contact_group_created",
            EventData::ContactGroupUpdated { .. } => "contact_group_updated",
            EventData::ContactGroupDeleted { .. } => "contact_group_deleted",
            EventData::ContactGroupMemberAdded { .. } => "contact_group_member_added",
            EventData::ContactGroupMemberRemoved { .. } => "contact_group_member_removed",
            EventData::WalletPermissionsSet { .. } => "wallet_permissions_set",
            EventData::GroupPermissionsSet { .. } => "group_permissions_set",
            EventData::ContactGroupPermissionsSet { .. } => "contact_group_permissions_set",
            EventData::PermissionMatrixSet { .. } => "permission_matrix_set",
            EventData::WalletDeleted { .. } => "wallet_deleted",
            EventData::OwnershipTransferred { .. } => "ownership_transferred",
        }
    }

    /// For a DB row's `(aggregate_type, event_type)` pair, look up the
    /// serde tag of the corresponding `EventData` variant. Returns
    /// `None` for combinations that don't correspond to any variant
    /// (e.g. a contact aggregate with a `WALLET_USER_ADDED` event_type).
    ///
    /// Exhaustive over both `EventType` AND `AggregateType` — adding a
    /// variant to either enum is a compile error here. This is the
    /// reverse of [`serde_tag`] and the only path from DB-string-pair
    /// back to a tag used by `parse_event_data_typed`.
    pub fn serde_tag_for(aggregate: AggregateType, event_type: EventType) -> Option<&'static str> {
        use AggregateType as A;
        use EventType as E;
        match event_type {
            E::Created => match aggregate {
                A::Contact => Some("contact_created"),
                A::Transaction => Some("transaction_created"),
                A::Permission => None,
            },
            E::Updated => match aggregate {
                A::Contact => Some("contact_updated"),
                A::Transaction => Some("transaction_updated"),
                A::Permission => None,
            },
            E::Deleted => match aggregate {
                A::Contact => Some("contact_deleted"),
                A::Transaction => Some("transaction_deleted"),
                A::Permission => None,
            },
            E::Undo => match aggregate {
                A::Contact => Some("contact_undone"),
                A::Transaction => Some("transaction_undone"),
                A::Permission => None,
            },
            E::WalletUserAdded => match aggregate {
                A::Permission => Some("wallet_user_added"),
                A::Contact | A::Transaction => None,
            },
            E::WalletUserRoleChanged => match aggregate {
                A::Permission => Some("wallet_user_role_changed"),
                A::Contact | A::Transaction => None,
            },
            E::WalletUserRemoved => match aggregate {
                A::Permission => Some("wallet_user_removed"),
                A::Contact | A::Transaction => None,
            },
            E::UserGroupCreated => match aggregate {
                A::Permission => Some("user_group_created"),
                A::Contact | A::Transaction => None,
            },
            E::UserGroupUpdated => match aggregate {
                A::Permission => Some("user_group_updated"),
                A::Contact | A::Transaction => None,
            },
            E::UserGroupDeleted => match aggregate {
                A::Permission => Some("user_group_deleted"),
                A::Contact | A::Transaction => None,
            },
            E::UserGroupMemberAdded => match aggregate {
                A::Permission => Some("user_group_member_added"),
                A::Contact | A::Transaction => None,
            },
            E::UserGroupMemberRemoved => match aggregate {
                A::Permission => Some("user_group_member_removed"),
                A::Contact | A::Transaction => None,
            },
            E::ContactGroupCreated => match aggregate {
                A::Permission => Some("contact_group_created"),
                A::Contact | A::Transaction => None,
            },
            E::ContactGroupUpdated => match aggregate {
                A::Permission => Some("contact_group_updated"),
                A::Contact | A::Transaction => None,
            },
            E::ContactGroupDeleted => match aggregate {
                A::Permission => Some("contact_group_deleted"),
                A::Contact | A::Transaction => None,
            },
            E::ContactGroupMemberAdded => match aggregate {
                A::Permission => Some("contact_group_member_added"),
                A::Contact | A::Transaction => None,
            },
            E::ContactGroupMemberRemoved => match aggregate {
                A::Permission => Some("contact_group_member_removed"),
                A::Contact | A::Transaction => None,
            },
            E::WalletPermissionsSet => match aggregate {
                A::Permission => Some("wallet_permissions_set"),
                A::Contact | A::Transaction => None,
            },
            E::GroupPermissionsSet => match aggregate {
                A::Permission => Some("group_permissions_set"),
                A::Contact | A::Transaction => None,
            },
            E::ContactGroupPermissionsSet => match aggregate {
                A::Permission => Some("contact_group_permissions_set"),
                A::Contact | A::Transaction => None,
            },
            E::PermissionMatrixSet => match aggregate {
                A::Permission => Some("permission_matrix_set"),
                A::Contact | A::Transaction => None,
            },
            E::WalletDeleted => match aggregate {
                A::Permission => Some("wallet_deleted"),
                A::Contact | A::Transaction => None,
            },
            E::OwnershipTransferred => match aggregate {
                A::Permission => Some("ownership_transferred"),
                A::Contact | A::Transaction => None,
            },
        }
    }

    /// Typed event-type discriminant. SINGLE SOURCE OF TRUTH — every
    /// other "what kind of event is this?" path goes through here. Adding
    /// a variant to `EventData` fails this match until an arm is added,
    /// which is exactly the compiler-driven guarantee we want.
    /// The wire-format string is `self.kind().as_str()`.
    pub fn kind(&self) -> EventType {
        match self {
            EventData::ContactCreated { .. } => EventType::Created,
            EventData::ContactUpdated { .. } => EventType::Updated,
            EventData::ContactDeleted { .. } => EventType::Deleted,
            EventData::ContactUndone { .. } => EventType::Undo,
            EventData::TransactionCreated { .. } => EventType::Created,
            EventData::TransactionUpdated { .. } => EventType::Updated,
            EventData::TransactionDeleted { .. } => EventType::Deleted,
            EventData::TransactionUndone { .. } => EventType::Undo,
            EventData::WalletUserAdded { .. } => EventType::WalletUserAdded,
            EventData::WalletUserRoleChanged { .. } => EventType::WalletUserRoleChanged,
            EventData::WalletUserRemoved { .. } => EventType::WalletUserRemoved,
            EventData::UserGroupCreated { .. } => EventType::UserGroupCreated,
            EventData::UserGroupUpdated { .. } => EventType::UserGroupUpdated,
            EventData::UserGroupDeleted { .. } => EventType::UserGroupDeleted,
            EventData::UserGroupMemberAdded { .. } => EventType::UserGroupMemberAdded,
            EventData::UserGroupMemberRemoved { .. } => EventType::UserGroupMemberRemoved,
            EventData::ContactGroupCreated { .. } => EventType::ContactGroupCreated,
            EventData::ContactGroupUpdated { .. } => EventType::ContactGroupUpdated,
            EventData::ContactGroupDeleted { .. } => EventType::ContactGroupDeleted,
            EventData::ContactGroupMemberAdded { .. } => EventType::ContactGroupMemberAdded,
            EventData::ContactGroupMemberRemoved { .. } => EventType::ContactGroupMemberRemoved,
            EventData::WalletPermissionsSet { .. } => EventType::WalletPermissionsSet,
            EventData::GroupPermissionsSet { .. } => EventType::GroupPermissionsSet,
            EventData::ContactGroupPermissionsSet { .. } => EventType::ContactGroupPermissionsSet,
            EventData::PermissionMatrixSet { .. } => EventType::PermissionMatrixSet,
            EventData::WalletDeleted { .. } => EventType::WalletDeleted,
            EventData::OwnershipTransferred { .. } => EventType::OwnershipTransferred,
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

    pub fn kind(&self) -> EventType {
        self.event_data.kind()
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
            EventData::WalletUserAdded { .. } => {
                // Changed: now uses specific WalletMemberAdd action
                vec![(Action::WalletMemberAdd, Resource::Wallet(self.wallet_id))]
            }
            EventData::WalletUserRemoved { .. } => {
                // Changed: now uses specific WalletMemberRemove action
                vec![(Action::WalletMemberRemove, Resource::Wallet(self.wallet_id))]
            }
            EventData::WalletUserRoleChanged { .. } => {
                // DEPRECATED: roles no longer exist; this event is no longer used
                vec![]  // No permission check needed
            }
            EventData::UserGroupCreated { .. } => {
                vec![(Action::UserGroupCreate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupUpdated { .. }
            | EventData::UserGroupMemberAdded { .. }
            | EventData::UserGroupMemberRemoved { .. }
            | EventData::WalletPermissionsSet { .. }
            | EventData::GroupPermissionsSet { .. }
            | EventData::ContactGroupPermissionsSet { .. }
            | EventData::PermissionMatrixSet { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupDeleted { .. }
            | EventData::ContactGroupDeleted { .. } => {
                // Group deletion is a wallet-level operation
                vec![(Action::WalletInfoUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::OwnershipTransferred { .. } => {
                // Changed: now uses specific WalletOwnerTransfer action
                vec![(Action::WalletOwnerTransfer, Resource::Wallet(self.wallet_id))]
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
