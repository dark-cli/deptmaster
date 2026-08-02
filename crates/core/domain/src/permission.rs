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

    // Wallet actions (Layer 1: Wallet-wide permissions)
    WalletInfoRead,              // wallet:info_read
    WalletInfoUpdate,            // wallet:info_update
    WalletMembersRead,           // wallet:members_read - View all members in wallet
    WalletMembersAdd,            // wallet:members_add - Add users to wallet
    WalletMembersRemove,         // wallet:members_remove - Remove users from wallet
    WalletGroupsCreate,          // wallet:groups_create - Create member_groups
    WalletGroupsUpdate,          // wallet:groups_update - Update member_groups and manage members
    WalletGroupsDelete,          // wallet:groups_delete - Delete member_groups
    WalletContactGroupsCreate,   // wallet:contact_groups_create - Create contact_groups
    WalletContactGroupsUpdate,   // wallet:contact_groups_update - Update contact_groups
    WalletContactGroupsDelete,   // wallet:contact_groups_delete - Delete contact_groups
    WalletMetadataRead,          // wallet:metadata_read - View wallet structure
    WalletPermissionsEdit,       // wallet:permissions_edit - Modify permission matrix (Layer 3 only)
    WalletDelete,                // wallet:delete - Soft delete wallet (OWNER ONLY)
    WalletOwnerTransfer,         // wallet:owner_transfer - Transfer ownership (OWNER ONLY)

    // Layer 2: Member-group-to-member-group permissions (vector-based, scoped to target group)
    MemberGroupMembersRead,      // member_group:members_read
    MemberGroupMembersAdd,       // member_group:members_add
    MemberGroupMembersRemove,    // member_group:members_remove
    MemberGroupPermissionsEdit,  // member_group:permissions_edit

    // Layer 2.5: Contact-group management permissions (vector-based, scoped to target contact_group)
    ContactGroupContactsRead,    // contact_group:contacts_read
    ContactGroupContactsAdd,     // contact_group:contacts_add
    ContactGroupContactsRemove,  // contact_group:contacts_remove
    ContactGroupPermissionsEdit, // contact_group:permissions_edit - Modify Layer 2.5 permissions for this group

    // Legacy/deprecated actions (kept for backward compatibility)
    WalletMemberAdd,      // DEPRECATED: Use WalletMembersAdd
    WalletMemberRemove,   // DEPRECATED: Use WalletMembersRemove
    WalletMemberList,     // DEPRECATED: Use WalletMembersRead
    WalletSetPermissionMatrix,  // DEPRECATED: Use WalletPermissionsEdit

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
            // Layer 1: Wallet-wide permissions
            Action::WalletInfoRead => "wallet:info_read",
            Action::WalletInfoUpdate => "wallet:info_update",
            Action::WalletMembersRead => "wallet:members_read",
            Action::WalletMembersAdd => "wallet:members_add",
            Action::WalletMembersRemove => "wallet:members_remove",
            Action::WalletGroupsCreate => "wallet:groups_create",
            Action::WalletGroupsUpdate => "wallet:groups_update",
            Action::WalletGroupsDelete => "wallet:groups_delete",
            Action::WalletContactGroupsCreate => "wallet:contact_groups_create",
            Action::WalletContactGroupsUpdate => "wallet:contact_groups_update",
            Action::WalletContactGroupsDelete => "wallet:contact_groups_delete",
            Action::WalletMetadataRead => "wallet:metadata_read",
            Action::WalletPermissionsEdit => "wallet:permissions_edit",
            Action::WalletDelete => "wallet:delete",
            Action::WalletOwnerTransfer => "wallet:owner_transfer",
            // Layer 2: Member-group-to-member-group permissions
            Action::MemberGroupMembersRead => "member_group:members_read",
            Action::MemberGroupMembersAdd => "member_group:members_add",
            Action::MemberGroupMembersRemove => "member_group:members_remove",
            Action::MemberGroupPermissionsEdit => "member_group:permissions_edit",
            // Layer 2.5: Contact-group management permissions
            Action::ContactGroupContactsRead => "contact_group:contacts_read",
            Action::ContactGroupContactsAdd => "contact_group:contacts_add",
            Action::ContactGroupContactsRemove => "contact_group:contacts_remove",
            Action::ContactGroupPermissionsEdit => "contact_group:permissions_edit",
            // Legacy/deprecated
            Action::WalletMemberAdd => "wallet:member_add",       // Deprecated alias
            Action::WalletMemberRemove => "wallet:member_remove", // Deprecated alias
            Action::WalletMemberList => "wallet:member_list",     // Deprecated alias
            Action::WalletSetPermissionMatrix => "wallet:set_permission_matrix", // Deprecated
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
            // Layer 1: Wallet-wide permissions
            "wallet:info_read" => Some(Action::WalletInfoRead),
            "wallet:info_update" => Some(Action::WalletInfoUpdate),
            "wallet:members_read" => Some(Action::WalletMembersRead),
            "wallet:members_add" => Some(Action::WalletMembersAdd),
            "wallet:members_remove" => Some(Action::WalletMembersRemove),
            "wallet:groups_create" => Some(Action::WalletGroupsCreate),
            "wallet:groups_update" => Some(Action::WalletGroupsUpdate),
            "wallet:groups_delete" => Some(Action::WalletGroupsDelete),
            "wallet:contact_groups_create" => Some(Action::WalletContactGroupsCreate),
            "wallet:contact_groups_update" => Some(Action::WalletContactGroupsUpdate),
            "wallet:contact_groups_delete" => Some(Action::WalletContactGroupsDelete),
            "wallet:metadata_read" => Some(Action::WalletMetadataRead),
            "wallet:permissions_edit" => Some(Action::WalletPermissionsEdit),
            "wallet:delete" => Some(Action::WalletDelete),
            "wallet:owner_transfer" => Some(Action::WalletOwnerTransfer),
            // Layer 2: Member-group-to-member-group permissions
            "member_group:members_read" => Some(Action::MemberGroupMembersRead),
            "member_group:members_add" => Some(Action::MemberGroupMembersAdd),
            "member_group:members_remove" => Some(Action::MemberGroupMembersRemove),
            "member_group:permissions_edit" => Some(Action::MemberGroupPermissionsEdit),
            // Layer 2.5: Contact-group management permissions
            "contact_group:contacts_read" => Some(Action::ContactGroupContactsRead),
            "contact_group:contacts_add" => Some(Action::ContactGroupContactsAdd),
            "contact_group:contacts_remove" => Some(Action::ContactGroupContactsRemove),
            "contact_group:permissions_edit" => Some(Action::ContactGroupPermissionsEdit),
            // Deprecated wallet actions (for backward compatibility)
            "wallet:member_add" => Some(Action::WalletMemberAdd),
            "wallet:member_remove" => Some(Action::WalletMemberRemove),
            "wallet:member_list" => Some(Action::WalletMemberList),
            "wallet:set_permission_matrix" => Some(Action::WalletSetPermissionMatrix),
            // Old deprecated wallet actions (map to new ones)
            "wallet:read" => Some(Action::WalletInfoRead),        // Maps to info_read
            "wallet:update" => Some(Action::WalletInfoUpdate),    // Maps to info_update
            "wallet:manage_members" => Some(Action::WalletMembersAdd), // Maps to members_add
            "wallet:super_permission" => Some(Action::WalletSuperPermission),
            "events:read" => Some(Action::EventsRead),
            _ => None,
        }
    }

    /// Every defined action. Useful for initialization and tests.
    pub fn all() -> &'static [Action] {
        &[
            // Contact actions
            Action::ContactCreate,
            Action::ContactRead,
            Action::ContactUpdate,
            Action::ContactDelete,
            // Transaction actions
            Action::TransactionCreate,
            Action::TransactionRead,
            Action::TransactionUpdate,
            Action::TransactionDelete,
            Action::TransactionClose,
            // User group actions
            Action::UserGroupCreate,
            Action::UserGroupRead,
            Action::UserGroupUpdate,
            // Contact group actions
            Action::ContactGroupCreate,
            Action::ContactGroupRead,
            Action::ContactGroupUpdate,
            // Layer 1: Wallet-wide permissions
            Action::WalletInfoRead,
            Action::WalletInfoUpdate,
            Action::WalletMembersRead,
            Action::WalletMembersAdd,
            Action::WalletMembersRemove,
            Action::WalletGroupsCreate,
            Action::WalletGroupsUpdate,
            Action::WalletGroupsDelete,
            Action::WalletContactGroupsCreate,
            Action::WalletContactGroupsUpdate,
            Action::WalletContactGroupsDelete,
            Action::WalletMetadataRead,
            Action::WalletPermissionsEdit,
            Action::WalletDelete,
            Action::WalletOwnerTransfer,
            // Layer 2: Member-group-to-member-group permissions
            Action::MemberGroupMembersRead,
            Action::MemberGroupMembersAdd,
            Action::MemberGroupMembersRemove,
            Action::MemberGroupPermissionsEdit,
            // Layer 2.5: Contact-group management permissions
            Action::ContactGroupContactsRead,
            Action::ContactGroupContactsAdd,
            Action::ContactGroupContactsRemove,
            Action::ContactGroupPermissionsEdit,
            // Legacy/deprecated (not included - for backward compat only)
            // Events
            Action::EventsRead,
            // Deprecated (kept for backward compat)
            Action::WalletSuperPermission,
        ]
    }

    /// Does holding `self` imply being allowed to perform `other`?
    /// Update/Delete/Add/Remove operations imply Read on the same resource;
    /// `WalletSuperPermission` implies everything.
    pub fn implies(&self, other: Action) -> bool {
        match (self, other) {
            // Contact implications
            (Action::ContactUpdate, Action::ContactRead) => true,
            (Action::ContactDelete, Action::ContactRead) => true,
            // Transaction implications
            (Action::TransactionUpdate, Action::TransactionRead) => true,
            (Action::TransactionDelete, Action::TransactionRead) => true,
            (Action::TransactionClose, Action::TransactionRead) => true,
            // User group implications
            (Action::UserGroupUpdate, Action::UserGroupRead) => true,
            // Contact group implications
            (Action::ContactGroupUpdate, Action::ContactGroupRead) => true,
            // Wallet-level implications
            (Action::WalletInfoUpdate, Action::WalletInfoRead) => true,
            (Action::WalletDelete, Action::WalletInfoRead) => true,
            (Action::WalletMembersRemove, Action::WalletMembersRead) => true,
            (Action::WalletMembersAdd, Action::WalletMembersRead) => true,
            // Layer 2: Member-group-to-member-group implications
            (Action::MemberGroupMembersAdd, Action::MemberGroupMembersRead) => true,
            (Action::MemberGroupMembersRemove, Action::MemberGroupMembersRead) => true,
            // Layer 2.5: Contact-group management implications
            (Action::ContactGroupContactsAdd, Action::ContactGroupContactsRead) => true,
            (Action::ContactGroupContactsRemove, Action::ContactGroupContactsRead) => true,
            // ContactGroupPermissionsEdit is admin - implies all contact-group management actions
            (Action::ContactGroupPermissionsEdit, Action::ContactGroupContactsRead) => true,
            (Action::ContactGroupPermissionsEdit, Action::ContactGroupContactsAdd) => true,
            (Action::ContactGroupPermissionsEdit, Action::ContactGroupContactsRemove) => true,
            // Legacy/deprecated actions (map to new ones)
            (Action::WalletMemberAdd, Action::WalletMemberList) => true,
            (Action::WalletMemberRemove, Action::WalletMemberList) => true,
            // Super permission implies everything
            (Action::WalletSuperPermission, _) => true,
            // Self-implication
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
    // Wallet member groups for vector-based permission checks (which source can manage which target)
    WalletGroup(Uuid),
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
            | Resource::UserGroup(id)
            | Resource::WalletGroup(id) => Some(*id),
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
            Resource::WalletGroup(id) => write!(f, "wallet_group:{}", id),
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
