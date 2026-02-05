//! Shared types: currency, ID aliases. Use date types (chrono) for timestamps and dates.

pub mod currency;
pub mod ids;

pub use currency::Currency;
pub use ids::{ContactId, EventId, TransactionId, UserId, WalletId};
