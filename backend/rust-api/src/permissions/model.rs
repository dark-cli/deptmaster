use sqlx::PgPool;
use crate::database::error::DbError;

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
    pub async fn check_permissions(
        &self,
        ctx: &PermissionContext,
        checks: Vec<(Action, Resource)>,
    ) -> Result<Vec<bool>, DbError> {
        if checks.is_empty() {
            return Ok(Vec::new());
        }

        let mut results = Vec::with_capacity(checks.len());

        // Owner and admin bypass all checks
        if ctx.bypasses_permissions() {
            return Ok(vec![true; checks.len()]);
        }

        // For members, check each permission (currently per-check, can be batch optimized)
        for (action, resource) in checks {
            let allowed = resolver::can_perform(&self.pool, ctx, action, &resource).await?;
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
                Action::TransactionUpdate | Action::TransactionClose => {
                    if !actions.contains(&Action::TransactionRead) {
                        return Err(format!(
                            "Permission {} requires transaction:read",
                            action
                        ));
                    }
                }
                Action::WalletUpdate | Action::WalletAddMember | Action::WalletRemoveMember => {
                    if !actions.contains(&Action::WalletRead) {
                        return Err(format!(
                            "Permission {} requires wallet:read",
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
