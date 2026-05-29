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
    TransactionClose,

    // Wallet actions
    WalletRead,
    WalletUpdate,
    WalletAddMember,
    WalletRemoveMember,

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
            Action::TransactionClose => "transaction:close",
            Action::WalletRead => "wallet:read",
            Action::WalletUpdate => "wallet:update",
            Action::WalletAddMember => "wallet:add_member",
            Action::WalletRemoveMember => "wallet:remove_member",
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
            "transaction:close" => Some(Action::TransactionClose),
            "wallet:read" => Some(Action::WalletRead),
            "wallet:update" => Some(Action::WalletUpdate),
            "wallet:add_member" => Some(Action::WalletAddMember),
            "wallet:remove_member" => Some(Action::WalletRemoveMember),
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
            Action::TransactionClose,
            Action::WalletRead,
            Action::WalletUpdate,
            Action::WalletAddMember,
            Action::WalletRemoveMember,
            Action::EventsRead,
        ]
    }

    /// Check if permission A implies permission B
    /// E.g., write implies read
    pub fn implies(&self, other: Action) -> bool {
        match (self, other) {
            // Contact: update implies read
            (Action::ContactUpdate, Action::ContactRead) => true,
            (Action::ContactDelete, Action::ContactRead) => true,
            // Transaction: update/close implies read
            (Action::TransactionUpdate, Action::TransactionRead) => true,
            (Action::TransactionClose, Action::TransactionRead) => true,
            // Wallet: update/add/remove implies read
            (Action::WalletUpdate, Action::WalletRead) => true,
            (Action::WalletAddMember, Action::WalletRead) => true,
            (Action::WalletRemoveMember, Action::WalletRead) => true,
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
