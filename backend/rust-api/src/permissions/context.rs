use std::fmt;
use uuid::Uuid;

/// Wallet role - determines permission inheritance
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WalletRole {
    /// Owner - tracked in wallet_owners table, can transfer ownership
    Owner,
    /// Member - group-based permissions only
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

    /// Check if this role is Owner
    pub fn is_owner(&self) -> bool {
        matches!(self, WalletRole::Owner)
    }

    /// Check if this role is at least Owner (Owner only, since Admin was removed)
    /// Note: This will be removed once database-backed admin permissions are implemented
    pub fn is_admin_or_higher(&self) -> bool {
        matches!(self, WalletRole::Owner)
    }

    /// Check if this role meets or exceeds required level (0=member, 1=owner)
    pub fn can_perform(&self, required: WalletRole) -> bool {
        let self_level = match self {
            WalletRole::Member => 0,
            WalletRole::Owner => 1,
        };
        let required_level = match required {
            WalletRole::Member => 0,
            WalletRole::Owner => 1,
        };
        self_level >= required_level
    }
}

impl fmt::Display for WalletRole {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Permission context - who is accessing what in which wallet
#[derive(Debug, Clone)]
pub struct PermissionContext {
    /// Which wallet we're operating in
    pub wallet_id: Uuid,
    /// Who is making the request
    pub user_id: Uuid,
    /// What role do they have in this wallet
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

    /// Create context for owner
    pub fn owner(wallet_id: Uuid, user_id: Uuid) -> Self {
        Self::new(wallet_id, user_id, WalletRole::Owner)
    }

    /// Create context for member (group-based permissions)
    pub fn member(wallet_id: Uuid, user_id: Uuid) -> Self {
        Self::new(wallet_id, user_id, WalletRole::Member)
    }
}
