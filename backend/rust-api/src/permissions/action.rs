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
    UserGroupUpdate,

    // Contact Group actions
    ContactGroupCreate,
    ContactGroupRead,
    ContactGroupUpdate,

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
            Action::UserGroupUpdate => "user_group:update",
            Action::ContactGroupCreate => "contact_group:create",
            Action::ContactGroupRead => "contact_group:read",
            Action::ContactGroupUpdate => "contact_group:update",
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
            "user_group:update" => Some(Action::UserGroupUpdate),
            "contact_group:create" => Some(Action::ContactGroupCreate),
            "contact_group:read" => Some(Action::ContactGroupRead),
            "contact_group:update" => Some(Action::ContactGroupUpdate),
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
            Action::UserGroupUpdate,
            Action::ContactGroupCreate,
            Action::ContactGroupRead,
            Action::ContactGroupUpdate,
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
            // User Group: update implies read
            (Action::UserGroupUpdate, Action::UserGroupRead) => true,
            // Contact Group: update implies read
            (Action::ContactGroupUpdate, Action::ContactGroupRead) => true,
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
