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

    // Wallet actions (granular, replaces WalletRead/Update/Delete/ManageMembers)
    // Tier 1: Global wallet management
    WalletInfoRead,       // Read wallet name, description, members count
    WalletInfoUpdate,     // Modify wallet name, description
    // Tier 2: Global member management
    WalletMemberAdd,      // Invite/add users to wallet
    WalletMemberRemove,   // Remove users from wallet
    WalletMemberList,     // View all members in wallet
    // Tier 2: Vector-based member management (scoped to target group)
    WalletSetPermissionMatrix,  // Modify member group permissions
    // Tier 3: Owner-only operations (hardcoded in handlers, no matrix check)
    WalletOwnerTransfer,  // Transfer ownership (OWNER ONLY)
    WalletDelete,         // Soft delete wallet (OWNER ONLY)

    /// Owner-only fallback: bypasses every other check when held.
    /// Deprecated: kept for backward compatibility, not used in new code.
    #[deprecated(since = "0.2.0", note = "Use wallet permission matrix instead")]
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
            Action::WalletInfoRead => "wallet:info_read",
            Action::WalletInfoUpdate => "wallet:info_update",
            Action::WalletMemberAdd => "wallet:member_add",
            Action::WalletMemberRemove => "wallet:member_remove",
            Action::WalletMemberList => "wallet:member_list",
            Action::WalletSetPermissionMatrix => "wallet:set_permission_matrix",
            Action::WalletOwnerTransfer => "wallet:owner_transfer",
            Action::WalletDelete => "wallet:delete",
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
            // New wallet actions (granular)
            "wallet:info_read" => Some(Action::WalletInfoRead),
            "wallet:info_update" => Some(Action::WalletInfoUpdate),
            "wallet:member_add" => Some(Action::WalletMemberAdd),
            "wallet:member_remove" => Some(Action::WalletMemberRemove),
            "wallet:member_list" => Some(Action::WalletMemberList),
            "wallet:set_permission_matrix" => Some(Action::WalletSetPermissionMatrix),
            "wallet:owner_transfer" => Some(Action::WalletOwnerTransfer),
            "wallet:delete" => Some(Action::WalletDelete),
            // Old wallet actions (deprecated, for backward compat)
            "wallet:read" => Some(Action::WalletInfoRead),        // Maps to info_read
            "wallet:update" => Some(Action::WalletInfoUpdate),    // Maps to info_update
            "wallet:manage_members" => Some(Action::WalletMemberAdd), // Maps to member_add
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
            Action::WalletInfoRead,
            Action::WalletInfoUpdate,
            Action::WalletMemberAdd,
            Action::WalletMemberRemove,
            Action::WalletMemberList,
            Action::WalletSetPermissionMatrix,
            Action::WalletOwnerTransfer,
            Action::WalletDelete,
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
            // Wallet-level implications
            (Action::WalletInfoUpdate, Action::WalletInfoRead) => true,
            (Action::WalletDelete, Action::WalletInfoRead) => true,
            (Action::WalletMemberRemove, Action::WalletMemberList) => true,
            (Action::WalletMemberAdd, Action::WalletMemberList) => true,
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
