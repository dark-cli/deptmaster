//! Core types: error handling and data models for FFI boundary.

pub mod error;
pub mod models;

pub use error::ClientError;
pub use models::{Contact, Currency, Event, Transaction, Wallet};
