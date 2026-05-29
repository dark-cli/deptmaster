use uuid::Uuid;
use std::fmt;

/// Wallet role - determines permission inheritance
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WalletRole {
    /// Owner - immovable, has all permissions always
    Owner,
    /// Admin - manages permissions but cannot edit own
    Admin,
    /// Member - group-based permissions only
    Member,
}

impl WalletRole {
    pub fn as_str(&self) -> &'static str {
        match self {
            WalletRole::Owner => "owner",
            WalletRole::Admin => "admin",
            WalletRole::Member => "member",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "owner" => Some(WalletRole::Owner),
            "admin" => Some(WalletRole::Admin),
            "member" => Some(WalletRole::Member),
            _ => None,
        }
    }

    /// Owner and admin bypass normal permission checks
    pub fn bypasses_permissions(&self) -> bool {
        matches!(self, WalletRole::Owner | WalletRole::Admin)
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

    /// Check if context bypasses normal permission checks
    /// Owner and admin do not go through permission matrix
    pub fn bypasses_permissions(&self) -> bool {
        self.user_role.bypasses_permissions()
    }

    /// Create context for owner (always has permissions)
    pub fn owner(wallet_id: Uuid, user_id: Uuid) -> Self {
        Self::new(wallet_id, user_id, WalletRole::Owner)
    }

    /// Create context for admin
    pub fn admin(wallet_id: Uuid, user_id: Uuid) -> Self {
        Self::new(wallet_id, user_id, WalletRole::Admin)
    }

    /// Create context for member (group-based permissions)
    pub fn member(wallet_id: Uuid, user_id: Uuid) -> Self {
        Self::new(wallet_id, user_id, WalletRole::Member)
    }
}
