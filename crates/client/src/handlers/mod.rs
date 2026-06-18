//! Public FFI handler layer: converts typed errors to String for Dart boundary.

pub(crate) mod auth;
pub(crate) mod sync;
pub(crate) mod wallets;

pub use auth::*;
pub use sync::*;
pub use wallets::*;
