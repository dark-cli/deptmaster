/// Permission System - Single source of truth for all permission logic
///
/// Type-safe, isolated permission model with batch-only API
///
/// # Architecture
///
/// - **action.rs**: Action enum (type-safe permission definitions)
/// - **resource.rs**: Resource enum (what's being accessed)
/// - **context.rs**: PermissionContext (who, where, what role)
/// - **model.rs**: PermissionModel (public batch API)
/// - **resolver.rs**: Internal permission resolution (single JOIN query)
/// - **queries.rs**: SQL constants (centralized permission queries)
///
/// # Usage
///
/// ```ignore
/// let model = PermissionModel::new(pool);
/// let ctx = PermissionContext::new(wallet_id, user_id, WalletRole::Member);
///
/// let allowed = model.check_permissions(&ctx, vec![
///     (Action::ContactCreate, Resource::AllContacts),
///     (Action::TransactionRead, Resource::Transaction(id)),
/// ]).await?;
///
/// if allowed[0] { /* can create contact */ }
/// if allowed[1] { /* can read transaction */ }
/// ```

pub mod action;
pub mod context;
pub mod model;
pub mod queries;
pub mod resolver;
pub mod resource;

// Public API
pub use action::Action;
pub use context::{PermissionContext, WalletRole};
pub use model::PermissionModel;
pub use resource::Resource;
