use std::fmt;

/// Permission actions - type-safe, single source of truth
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

    // User Group actions
    UserGroupCreate,
    UserGroupRead,
    UserGroupAddMember,
    UserGroupRemoveMember,
    UserGroupEdit,

    // Contact Group actions
    ContactGroupCreate,
    ContactGroupRead,
    ContactGroupAddMember,
    ContactGroupRemoveMember,
    ContactGroupEdit,

    // Wallet actions
    WalletRead,
    WalletUpdate,
    WalletDelete,

    // Special: Owner-only permission (fallback for any action)
    WalletSuperPermission,

    // Event actions
    EventsRead,
}

impl Action {
    /// Convert Action to database permission name string
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
            Action::UserGroupCreate => "user_group:create",
            Action::UserGroupRead => "user_group:read",
            Action::UserGroupAddMember => "user_group:add_member",
            Action::UserGroupRemoveMember => "user_group:remove_member",
            Action::UserGroupEdit => "user_group:edit",
            Action::ContactGroupCreate => "contact_group:create",
            Action::ContactGroupRead => "contact_group:read",
            Action::ContactGroupAddMember => "contact_group:add_member",
            Action::ContactGroupRemoveMember => "contact_group:remove_member",
            Action::ContactGroupEdit => "contact_group:edit",
            Action::WalletRead => "wallet:read",
            Action::WalletUpdate => "wallet:update",
            Action::WalletDelete => "wallet:delete",
            Action::WalletSuperPermission => "wallet:super_permission",
            Action::EventsRead => "events:read",
        }
    }

    /// Parse database permission name to Action
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "contact:create" => Some(Action::ContactCreate),
            "contact:read" => Some(Action::ContactRead),
            "contact:update" => Some(Action::ContactUpdate),
            "contact:edit" => Some(Action::ContactUpdate), // Alias
            "contact:delete" => Some(Action::ContactDelete),
            "transaction:create" => Some(Action::TransactionCreate),
            "transaction:read" => Some(Action::TransactionRead),
            "transaction:update" => Some(Action::TransactionUpdate),
            "transaction:delete" => Some(Action::TransactionDelete),
            "user_group:create" => Some(Action::UserGroupCreate),
            "user_group:read" => Some(Action::UserGroupRead),
            "user_group:add_member" => Some(Action::UserGroupAddMember),
            "user_group:remove_member" => Some(Action::UserGroupRemoveMember),
            "user_group:edit" => Some(Action::UserGroupEdit),
            "contact_group:create" => Some(Action::ContactGroupCreate),
            "contact_group:read" => Some(Action::ContactGroupRead),
            "contact_group:add_member" => Some(Action::ContactGroupAddMember),
            "contact_group:remove_member" => Some(Action::ContactGroupRemoveMember),
            "contact_group:edit" => Some(Action::ContactGroupEdit),
            "wallet:read" => Some(Action::WalletRead),
            "wallet:update" => Some(Action::WalletUpdate),
            "wallet:delete" => Some(Action::WalletDelete),
            "wallet:super_permission" => Some(Action::WalletSuperPermission),
            "events:read" => Some(Action::EventsRead),
            _ => None,
        }
    }

    /// All available actions (for initialization, testing)
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
            Action::UserGroupCreate,
            Action::UserGroupRead,
            Action::UserGroupAddMember,
            Action::UserGroupRemoveMember,
            Action::UserGroupEdit,
            Action::ContactGroupCreate,
            Action::ContactGroupRead,
            Action::ContactGroupAddMember,
            Action::ContactGroupRemoveMember,
            Action::ContactGroupEdit,
            Action::WalletRead,
            Action::WalletUpdate,
            Action::WalletDelete,
            Action::WalletSuperPermission,
            Action::EventsRead,
        ]
    }

    /// Check if permission A implies permission B
    /// E.g., write implies read
    pub fn implies(&self, other: Action) -> bool {
        match (self, other) {
            // Contact: update/delete implies read
            (Action::ContactUpdate, Action::ContactRead) => true,
            (Action::ContactDelete, Action::ContactRead) => true,
            // Transaction: update/delete implies read
            (Action::TransactionUpdate, Action::TransactionRead) => true,
            (Action::TransactionDelete, Action::TransactionRead) => true,
            // User Group: edit/add/remove implies read
            (Action::UserGroupEdit, Action::UserGroupRead) => true,
            (Action::UserGroupAddMember, Action::UserGroupRead) => true,
            (Action::UserGroupRemoveMember, Action::UserGroupRead) => true,
            // Contact Group: edit/add/remove implies read
            (Action::ContactGroupEdit, Action::ContactGroupRead) => true,
            (Action::ContactGroupAddMember, Action::ContactGroupRead) => true,
            (Action::ContactGroupRemoveMember, Action::ContactGroupRead) => true,
            // Wallet: update/delete implies read
            (Action::WalletUpdate, Action::WalletRead) => true,
            (Action::WalletDelete, Action::WalletRead) => true,
            // Super permission implies everything
            (Action::WalletSuperPermission, _) => true,
            // Same permission always implies
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
