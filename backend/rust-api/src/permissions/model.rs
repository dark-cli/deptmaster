use sqlx::PgPool;
use uuid::Uuid;
use crate::database::error::DbError;
use std::collections::HashSet;

use super::action::Action;
use super::context::PermissionContext;
use super::resource::Resource;
use super::resolver;

/// Permission Model - Single source of truth for all permission checks
///
/// Batch-only API: All checks (even single) are collected in a list and processed together
/// This ensures maximum efficiency and prevents accidental use of per-item queries
pub struct PermissionModel {
    pool: PgPool,
}

impl PermissionModel {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Check permissions for a batch of (action, resource) pairs
    ///
    /// Even single checks should be wrapped in a vec and passed here
    /// This ensures all permission checks go through optimized batch path
    ///
    /// # Arguments
    /// * `ctx` - Permission context (who, what wallet, what role)
    /// * `checks` - List of (action, resource) pairs to check
    ///
    /// # Returns
    /// Vec<bool> where index i corresponds to checks[i]
    /// true = action allowed, false = action denied
    ///
    /// # Example
    /// ```ignore
    /// let allowed = model.check_permissions(&ctx, vec![
    ///     (Action::ContactCreate, Resource::AllContacts),
    ///     (Action::TransactionRead, Resource::Transaction(id)),
    /// ]).await?;
    ///
    /// if allowed[0] { /* can create */ }
    /// if allowed[1] { /* can read */ }
    /// ```
    /// Resolve all allowed actions for a user on a specific resource
    ///
    /// Returns the set of actions the user can perform on the resource.
    /// Owner/Admin bypass and have all actions available.
    ///
    /// # Arguments
    /// * `ctx` - Permission context (who, what wallet, what role)
    /// * `resource` - The resource to check permissions for
    ///
    /// # Returns
    /// HashSet of all allowed actions on this resource
    ///
    /// # Example
    /// ```ignore
    /// let actions = model.resolve_actions(&ctx, &Resource::Contact(contact_id)).await?;
    /// if actions.contains(&Action::ContactUpdate) {
    ///     // User can update this contact
    /// }
    /// ```
    pub async fn resolve_actions(
        &self,
        ctx: &PermissionContext,
        resource: &Resource,
    ) -> Result<HashSet<Action>, DbError> {
        resolver::resolve_actions(&self.pool, ctx, resource).await
    }

    /// Get contact IDs the user can read (for sync filtering)
    ///
    /// Returns None if user can read all contacts, Some(set) if limited to specific contacts.
    /// Owner/Admin get None (can read all).
    ///
    /// # Arguments
    /// * `ctx` - Permission context (who, what wallet, what role)
    ///
    /// # Returns
    /// None = can read all contacts, Some(HashSet<Uuid>) = specific contact IDs
    pub async fn get_readable_contacts(
        &self,
        ctx: &PermissionContext,
    ) -> Result<Option<HashSet<Uuid>>, DbError> {
        resolver::get_readable_contacts(&self.pool, ctx).await
    }

    /// Get contacts whose transactions a user can read (for sync filtering)
    ///
    /// Returns None if user can read all transaction contacts, Some(set) if limited to specific contacts.
    /// Owner/Admin get None (can read all).
    ///
    /// # Arguments
    /// * `ctx` - Permission context (who, what wallet, what role)
    ///
    /// # Returns
    /// None = can read all transaction contacts, Some(HashSet<Uuid>) = specific contact IDs
    pub async fn get_readable_transaction_contacts(
        &self,
        ctx: &PermissionContext,
    ) -> Result<Option<HashSet<Uuid>>, DbError> {
        resolver::get_readable_transaction_contacts(&self.pool, ctx).await
    }

    pub async fn check_permissions(
        &self,
        ctx: &PermissionContext,
        checks: Vec<(Action, Resource)>,
    ) -> Result<Vec<bool>, DbError> {
        if checks.is_empty() {
            return Ok(Vec::new());
        }

        let mut results = Vec::with_capacity(checks.len());

        // Check each permission with WalletSuperPermission as automatic fallback
        for (action, resource) in checks {
            // Check specific permission
            let allowed = resolver::can_perform(&self.pool, ctx, action, &resource).await?;

            // If specific permission denied, check WalletSuperPermission fallback
            let allowed = if !allowed {
                resolver::can_perform(
                    &self.pool,
                    ctx,
                    Action::WalletSuperPermission,
                    &Resource::Wallet(ctx.wallet_id),
                ).await?
            } else {
                true
            };

            results.push(allowed);
        }

        Ok(results)
    }

    /// Validate permission dependency requirements
    /// E.g., write requires read, update requires read, etc.
    ///
    /// Returns Err if dependencies are violated
    pub fn validate_dependencies(actions: &[Action]) -> Result<(), String> {
        // Check that if write action is present, read action is also present
        for action in actions {
            match action {
                Action::ContactUpdate | Action::ContactDelete => {
                    if !actions.contains(&Action::ContactRead) {
                        return Err(format!(
                            "Permission {} requires contact:read",
                            action
                        ));
                    }
                }
                Action::TransactionUpdate | Action::TransactionDelete => {
                    if !actions.contains(&Action::TransactionRead) {
                        return Err(format!(
                            "Permission {} requires transaction:read",
                            action
                        ));
                    }
                }
                Action::WalletUpdate | Action::WalletDelete => {
                    if !actions.contains(&Action::WalletRead) {
                        return Err(format!(
                            "Permission {} requires wallet:read",
                            action
                        ));
                    }
                }
                Action::UserGroupEdit | Action::UserGroupAddMember | Action::UserGroupRemoveMember => {
                    if !actions.contains(&Action::UserGroupRead) {
                        return Err(format!(
                            "Permission {} requires user_group:read",
                            action
                        ));
                    }
                }
                Action::ContactGroupEdit | Action::ContactGroupAddMember | Action::ContactGroupRemoveMember => {
                    if !actions.contains(&Action::ContactGroupRead) {
                        return Err(format!(
                            "Permission {} requires contact_group:read",
                            action
                        ));
                    }
                }
                _ => {}
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_checks() {
        let checks: Vec<(Action, Resource)> = Vec::new();
        assert_eq!(checks.len(), 0);
    }

    #[test]
    fn test_validate_dependencies() {
        // Valid: update with read
        assert!(PermissionModel::validate_dependencies(&[
            Action::ContactUpdate,
            Action::ContactRead,
        ])
        .is_ok());

        // Invalid: update without read
        assert!(PermissionModel::validate_dependencies(&[Action::ContactUpdate]).is_err());

        // Valid: just read
        assert!(PermissionModel::validate_dependencies(&[Action::ContactRead]).is_ok());
    }

    #[test]
    fn test_action_implies() {
        assert!(Action::ContactUpdate.implies(Action::ContactRead));
        assert!(Action::ContactDelete.implies(Action::ContactRead));
        assert!(!Action::ContactRead.implies(Action::ContactUpdate));
        assert!(Action::ContactRead.implies(Action::ContactRead));
    }
}
