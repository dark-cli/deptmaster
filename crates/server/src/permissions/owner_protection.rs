//! Owner Permission Protection
//!
//! Centralized validation for operations that could affect owner permissions.
//! This module ensures that:
//! 1. The (all_contacts, __owners__) permission vector cannot be modified
//! 2. Other vectors involving __owners__ cannot have permissions set
//! 3. Wallet owners cannot be added to non-system groups (enforced via DB trigger)
//! 4. System groups cannot be modified (enforced via DB trigger)
//!
//! All owner permission checks should flow through this module.

use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct OwnerPermissionValidator {
    pool: PgPool,
}

#[derive(Debug)]
pub enum OwnerProtectionError {
    /// Cannot modify the (all_contacts, __owners__) permission vector
    CannotModifyOwnerPermissions,
    /// Cannot add permissions to __owners__ group for non-all_contacts groups
    CannotAddPermissionsToOwnerGroup,
    /// Database error
    DatabaseError(String),
}

impl std::fmt::Display for OwnerProtectionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::CannotModifyOwnerPermissions => {
                write!(f, "Cannot modify owner permissions on all_contacts")
            }
            Self::CannotAddPermissionsToOwnerGroup => {
                write!(f, "Cannot add permissions to __owners__ group")
            }
            Self::DatabaseError(e) => {
                write!(f, "Database error: {}", e)
            }
        }
    }
}

impl std::error::Error for OwnerProtectionError {}

impl OwnerPermissionValidator {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Validate permission matrix modification
    ///
    /// Rejects modifications to:
    /// 1. (all_contacts, __owners__) - owner's core permissions, immutable
    /// 2. (any_group, __owners__) where any_group != all_contacts - invalid vectors
    ///
    /// Returns Ok(()) if modification is allowed, Err(...) if rejected.
    pub async fn validate_permission_matrix_modification(
        &self,
        wallet_id: Uuid,
        user_group_id: Uuid,
        contact_group_id: Uuid,
    ) -> Result<(), OwnerProtectionError> {
        // Get the user group name
        let user_group_name: Option<String> = sqlx::query_scalar(
            "SELECT name FROM user_groups WHERE id = $1 AND wallet_id = $2"
        )
        .bind(user_group_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| OwnerProtectionError::DatabaseError(e.to_string()))?;

        // Get the contact group name
        let contact_group_name: Option<String> = sqlx::query_scalar(
            "SELECT name FROM contact_groups WHERE id = $1 AND wallet_id = $2"
        )
        .bind(contact_group_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| OwnerProtectionError::DatabaseError(e.to_string()))?;

        let user_group_name = user_group_name.unwrap_or_default();
        let contact_group_name = contact_group_name.unwrap_or_default();

        // RULE 1: Cannot modify permissions for (__owners__, all_contacts)
        // This is the core owner permission vector and must never be changed
        if user_group_name == "__owners__" && contact_group_name == "all_contacts" {
            return Err(OwnerProtectionError::CannotModifyOwnerPermissions);
        }

        // RULE 2: Cannot add permissions to __owners__ with non-all_contacts groups
        // The only valid permission vector involving __owners__ is (all_contacts, __owners__)
        if user_group_name == "__owners__" && contact_group_name != "all_contacts" {
            return Err(OwnerProtectionError::CannotAddPermissionsToOwnerGroup);
        }

        Ok(())
    }

    /// Validate group membership change (owner restriction)
    ///
    /// Rejects adding wallet owners to non-system groups.
    /// This is also enforced at the database level via trigger.
    ///
    /// Note: This validation is redundant with the database trigger but provides
    /// clear error messages to the API client before attempting the operation.
    pub async fn validate_group_membership_change(
        &self,
        wallet_id: Uuid,
        group_id: Uuid,
        user_id: Uuid,
        is_adding: bool,
    ) -> Result<(), OwnerProtectionError> {
        // Only validate on ADD operations
        if !is_adding {
            return Ok(());
        }

        // Check if user is a wallet owner
        let is_owner: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM wallet_owners WHERE user_id = $1 AND wallet_id = $2)"
        )
        .bind(user_id)
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| OwnerProtectionError::DatabaseError(e.to_string()))?;

        if !is_owner {
            // Not an owner, no restrictions
            return Ok(());
        }

        // User is an owner - check if group is system
        let is_system: bool = sqlx::query_scalar(
            "SELECT is_system FROM user_groups WHERE id = $1 AND wallet_id = $2"
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| OwnerProtectionError::DatabaseError(e.to_string()))?
        .unwrap_or(false);

        if !is_system {
            // Owners can only be in system groups (database trigger also prevents this)
            return Err(OwnerProtectionError::CannotAddPermissionsToOwnerGroup);
        }

        Ok(())
    }

    /// Validate user group creation
    ///
    /// Rejects creation of groups with reserved system names.
    /// This is also enforced by the application handler but kept here for
    /// potential future use by other code paths.
    pub async fn validate_user_group_creation(
        &self,
        _wallet_id: Uuid,
        group_name: &str,
    ) -> Result<(), OwnerProtectionError> {
        // Reserved system group names
        if group_name.eq_ignore_ascii_case("all_users")
            || group_name.eq_ignore_ascii_case("__owners__")
        {
            return Err(OwnerProtectionError::CannotModifyOwnerPermissions);
        }

        Ok(())
    }

    /// Validate contact group creation
    ///
    /// Rejects creation of contact groups with reserved system names.
    pub async fn validate_contact_group_creation(
        &self,
        _wallet_id: Uuid,
        group_name: &str,
    ) -> Result<(), OwnerProtectionError> {
        // Reserved system contact group names
        if group_name.eq_ignore_ascii_case("all_contacts") {
            return Err(OwnerProtectionError::CannotModifyOwnerPermissions);
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = OwnerProtectionError::CannotModifyOwnerPermissions;
        assert_eq!(
            err.to_string(),
            "Cannot modify owner permissions on all_contacts"
        );
    }
}
