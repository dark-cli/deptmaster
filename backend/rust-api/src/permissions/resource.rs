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
    /// All contacts in wallet (implicit group)
    AllContacts,
    /// All transactions in wallet (implicit group)
    AllTransactions,
}

impl Resource {
    /// Get resource type (for permission lookup)
    pub fn resource_type(&self) -> ResourceType {
        match self {
            Resource::Contact(_) => ResourceType::Contact,
            Resource::Transaction(_) => ResourceType::Transaction,
            Resource::Wallet(_) => ResourceType::Wallet,
            Resource::ContactGroup(_) => ResourceType::ContactGroup,
            Resource::AllContacts => ResourceType::Contact,
            Resource::AllTransactions => ResourceType::Transaction,
        }
    }

    /// Get resource ID if this is a specific resource
    pub fn id(&self) -> Option<Uuid> {
        match self {
            Resource::Contact(id) => Some(*id),
            Resource::Transaction(id) => Some(*id),
            Resource::Wallet(id) => Some(*id),
            Resource::ContactGroup(id) => Some(*id),
            Resource::AllContacts => None,
            Resource::AllTransactions => None,
        }
    }

    /// Is this a wildcard resource (affects all of type)?
    pub fn is_wildcard(&self) -> bool {
        matches!(self, Resource::AllContacts | Resource::AllTransactions)
    }
}

impl fmt::Display for Resource {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Resource::Contact(id) => write!(f, "contact:{}", id),
            Resource::Transaction(id) => write!(f, "transaction:{}", id),
            Resource::Wallet(id) => write!(f, "wallet:{}", id),
            Resource::ContactGroup(id) => write!(f, "contact_group:{}", id),
            Resource::AllContacts => write!(f, "all_contacts"),
            Resource::AllTransactions => write!(f, "all_transactions"),
        }
    }
}

/// Resource type classification (for permission matrix lookup)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResourceType {
    Contact,
    Transaction,
    Wallet,
    ContactGroup,
}

impl fmt::Display for ResourceType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ResourceType::Contact => write!(f, "contact"),
            ResourceType::Transaction => write!(f, "transaction"),
            ResourceType::Wallet => write!(f, "wallet"),
            ResourceType::ContactGroup => write!(f, "contact_group"),
        }
    }
}
