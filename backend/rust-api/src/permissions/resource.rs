use uuid::Uuid;
use std::fmt;

/// What resource is being accessed - type-safe resource identification
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Resource {
    /// Specific contact by ID
    Contact(Uuid),
    /// Specific transaction by ID
    Transaction(Uuid),
    /// Specific wallet by ID
    Wallet(Uuid),
    /// Specific contact group by ID
    ContactGroup(Uuid),
    /// Specific user group by ID
    UserGroup(Uuid),
    /// All contacts in wallet (implicit group)
    AllContacts,
    /// All transactions in wallet (implicit group)
    AllTransactions,
    /// All user groups in wallet (for group-level permissions)
    AllUserGroups,
}

impl Resource {
    /// Get resource ID if this is a specific resource
    pub fn id(&self) -> Option<Uuid> {
        match self {
            Resource::Contact(id) => Some(*id),
            Resource::Transaction(id) => Some(*id),
            Resource::Wallet(id) => Some(*id),
            Resource::ContactGroup(id) => Some(*id),
            Resource::UserGroup(id) => Some(*id),
            Resource::AllContacts => None,
            Resource::AllTransactions => None,
            Resource::AllUserGroups => None,
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

