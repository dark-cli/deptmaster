//! Public FFI handler layer: converts typed errors to String for Dart boundary.

mod auth;
mod sync;
mod wallets;

pub use auth::*;
pub use sync::*;
pub use wallets::*;
