//! Permission vocabulary: actions, resources, roles, and the context that
//! ties them together. The matrix-resolution algorithm itself stays on the
//! server (it needs DB access); only the type vocabulary is shared.

use std::fmt;
use uuid::Uuid;

// ============ ACTION ============

/// Permission actions — the verbs a user can perform on a resource. The
/// string forms (returned by [`Action::as_str`]) match the DB
/// `permission_actions.name` column and the JSON the API speaks.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Action {
    // Contact actions
    ContactCreate,
    ContactRead,
    ContactUpdate,
    ContactDelete,

    // Transaction actions
    TransactionCreate,
    TransactionRead,
    TransactionUpdate,
    TransactionDelete,
    TransactionClose,

    // User Group actions
    UserGroupCreate,
    UserGroupRead,
    UserGroupUpdate,

    // Contact Group actions
    ContactGroupCreate,
    ContactGroupRead,
    ContactGroupUpdate,

    // Wallet actions
    WalletRead,
    WalletUpdate,
    WalletDelete,
    WalletManageMembers,

    /// Owner-only fallback: bypasses every other check when held.
    WalletSuperPermission,

    // Event actions
    EventsRead,
}

impl Action {
    /// Database / wire-format name for this action.
    pub fn as_str(&self) -> &'static str {
        match self {
            Action::ContactCreate => "contact:create",
            Action::ContactRead => "contact:read",
            Action::ContactUpdate => "contact:update",
            Action::ContactDelete => "contact:delete",
            Action::TransactionCreate => "transaction:create",
            Action::TransactionRead => "transaction:read",
            Action::TransactionUpdate => "transaction:update",
            Action::TransactionDelete => "transaction:delete",
            Action::TransactionClose => "transaction:close",
            Action::UserGroupCreate => "user_group:create",
            Action::UserGroupRead => "user_group:read",
            Action::UserGroupUpdate => "user_group:update",
            Action::ContactGroupCreate => "contact_group:create",
            Action::ContactGroupRead => "contact_group:read",
            Action::ContactGroupUpdate => "contact_group:update",
            Action::WalletRead => "wallet:read",
            Action::WalletUpdate => "wallet:update",
            Action::WalletDelete => "wallet:delete",
            Action::WalletManageMembers => "wallet:manage_members",
            Action::WalletSuperPermission => "wallet:super_permission",
            Action::EventsRead => "events:read",
        }
    }

    /// Parse a database / wire-format name back into an [`Action`].
    /// `contact:edit` is accepted as an alias for `contact:update` for
    /// backward compatibility with older clients.
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "contact:create" => Some(Action::ContactCreate),
            "contact:read" => Some(Action::ContactRead),
            "contact:update" => Some(Action::ContactUpdate),
            "contact:edit" => Some(Action::ContactUpdate),
            "contact:delete" => Some(Action::ContactDelete),
            "transaction:create" => Some(Action::TransactionCreate),
            "transaction:read" => Some(Action::TransactionRead),
            "transaction:update" => Some(Action::TransactionUpdate),
            "transaction:delete" => Some(Action::TransactionDelete),
            "transaction:close" => Some(Action::TransactionClose),
            "user_group:create" => Some(Action::UserGroupCreate),
            "user_group:read" => Some(Action::UserGroupRead),
            "user_group:update" => Some(Action::UserGroupUpdate),
            "contact_group:create" => Some(Action::ContactGroupCreate),
            "contact_group:read" => Some(Action::ContactGroupRead),
            "contact_group:update" => Some(Action::ContactGroupUpdate),
            "wallet:read" => Some(Action::WalletRead),
            "wallet:update" => Some(Action::WalletUpdate),
            "wallet:delete" => Some(Action::WalletDelete),
            "wallet:manage_members" => Some(Action::WalletManageMembers),
            "wallet:super_permission" => Some(Action::WalletSuperPermission),
            "events:read" => Some(Action::EventsRead),
            _ => None,
        }
    }

    /// Every defined action. Useful for initialization and tests.
    pub fn all() -> &'static [Action] {
        &[
            Action::ContactCreate,
            Action::ContactRead,
            Action::ContactUpdate,
            Action::ContactDelete,
            Action::TransactionCreate,
            Action::TransactionRead,
            Action::TransactionUpdate,
            Action::TransactionDelete,
            Action::TransactionClose,
            Action::UserGroupCreate,
            Action::UserGroupRead,
            Action::UserGroupUpdate,
            Action::ContactGroupCreate,
            Action::ContactGroupRead,
            Action::ContactGroupUpdate,
            Action::WalletRead,
            Action::WalletUpdate,
            Action::WalletDelete,
            Action::WalletManageMembers,
            Action::WalletSuperPermission,
            Action::EventsRead,
        ]
    }

    /// Does holding `self` imply being allowed to perform `other`?
    /// Update/Delete imply Read on the same resource type;
    /// `WalletSuperPermission` implies everything.
    pub fn implies(&self, other: Action) -> bool {
        match (self, other) {
            (Action::ContactUpdate, Action::ContactRead) => true,
            (Action::ContactDelete, Action::ContactRead) => true,
            (Action::TransactionUpdate, Action::TransactionRead) => true,
            (Action::TransactionDelete, Action::TransactionRead) => true,
            (Action::TransactionClose, Action::TransactionRead) => true,
            (Action::UserGroupUpdate, Action::UserGroupRead) => true,
            (Action::ContactGroupUpdate, Action::ContactGroupRead) => true,
            (Action::WalletUpdate, Action::WalletRead) => true,
            (Action::WalletDelete, Action::WalletRead) => true,
            (Action::WalletManageMembers, Action::WalletRead) => true,
            (Action::WalletSuperPermission, _) => true,
            _ if self == &other => true,
            _ => false,
        }
    }
}

impl fmt::Display for Action {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

// ============ RESOURCE ============

/// The thing an [`Action`] is being performed against. Some variants name a
/// specific entity by UUID; the `All*` variants are wildcards used for
/// create-style checks where no specific resource exists yet.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Resource {
    Contact(Uuid),
    Transaction(Uuid),
    Wallet(Uuid),
    ContactGroup(Uuid),
    UserGroup(Uuid),
    AllContacts,
    AllTransactions,
    AllUserGroups,
}

impl Resource {
    /// The entity's UUID, or `None` for wildcard resources.
    pub fn id(&self) -> Option<Uuid> {
        match self {
            Resource::Contact(id)
            | Resource::Transaction(id)
            | Resource::Wallet(id)
            | Resource::ContactGroup(id)
            | Resource::UserGroup(id) => Some(*id),
            Resource::AllContacts | Resource::AllTransactions | Resource::AllUserGroups => None,
        }
    }
}

impl fmt::Display for Resource {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Resource::Contact(id) => write!(f, "contact:{}", id),
            Resource::Transaction(id) => write!(f, "transaction:{}", id),
            Resource::Wallet(id) => write!(f, "wallet:{}", id),
            Resource::ContactGroup(id) => write!(f, "contact_group:{}", id),
            Resource::UserGroup(id) => write!(f, "user_group:{}", id),
            Resource::AllContacts => write!(f, "all_contacts"),
            Resource::AllTransactions => write!(f, "all_transactions"),
            Resource::AllUserGroups => write!(f, "all_user_groups"),
        }
    }
}

// ============ WALLET ROLE ============

/// Where a user stands in a wallet's authorization model.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WalletRole {
    /// Tracked in `wallet_owners`; can transfer ownership.
    Owner,
    /// Group-based permissions only.
    Member,
}

impl WalletRole {
    pub fn as_str(&self) -> &'static str {
        match self {
            WalletRole::Owner => "owner",
            WalletRole::Member => "member",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "owner" => Some(WalletRole::Owner),
            "member" => Some(WalletRole::Member),
            _ => None,
        }
    }

    pub fn is_owner(&self) -> bool {
        matches!(self, WalletRole::Owner)
    }

    /// Reserved for the future admin role; today it only matches Owner.
    pub fn is_admin_or_higher(&self) -> bool {
        matches!(self, WalletRole::Owner)
    }

    /// Numeric rank comparison: Owner (1) ≥ Member (0).
    pub fn can_perform(&self, required: WalletRole) -> bool {
        let rank = |r: WalletRole| match r {
            WalletRole::Member => 0,
            WalletRole::Owner => 1,
        };
        rank(*self) >= rank(required)
    }
}

impl fmt::Display for WalletRole {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

// ============ PERMISSION CONTEXT ============

/// Bundle of (who, where, role) passed through every permission check.
#[derive(Debug, Clone)]
pub struct PermissionContext {
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    pub user_role: WalletRole,
}

impl PermissionContext {
    pub fn new(wallet_id: Uuid, user_id: Uuid, user_role: WalletRole) -> Self {
        Self {
            wallet_id,
            user_id,
            user_role,
        }
    }

    pub fn owner(wallet_id: Uuid, user_id: Uuid) -> Self {
        Self::new(wallet_id, user_id, WalletRole::Owner)
    }

    pub fn member(wallet_id: Uuid, user_id: Uuid) -> Self {
        Self::new(wallet_id, user_id, WalletRole::Member)
    }
}
