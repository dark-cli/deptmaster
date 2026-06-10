//! Permission system — server-side resolution + DB access.
//!
//! The type vocabulary (`Action`, `Resource`, `WalletRole`, `PermissionContext`)
//! lives in the shared `domain` crate. This module owns the server-only pieces:
//! `PermissionModel` (batch API), `resolver` (DB-backed resolution against the
//! permission matrix), and SQL constants.
//!
//! # Usage
//!
//! ```ignore
//! use domain::{Action, PermissionContext, Resource, WalletRole};
//! use crate::permissions::PermissionModel;
//!
//! let model = PermissionModel::new(pool);
//! let ctx = PermissionContext::new(wallet_id, user_id, WalletRole::Member);
//!
//! let allowed = model.check_permissions(&ctx, vec![
//!     (Action::ContactCreate, Resource::AllContacts),
//!     (Action::TransactionRead, Resource::Transaction(id)),
//! ]).await?;
//! ```

pub mod model;
pub mod queries;
pub mod resolver;

pub use model::PermissionModel;
