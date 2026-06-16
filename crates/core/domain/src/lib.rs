//! Shared domain types for the Debitum debt-tracker.
//!
//! This crate is the **single source of truth** for types that cross the
//! client/server boundary: event payloads, permission actions, resource
//! identifiers, wallet roles. Both `backend/rust-api` and
//! `crates/sdk` depend on this crate so a struct change
//! shows up as a compile error on both sides instead of as a runtime JSON
//! mismatch.
//!
//! ## What lives here
//!
//! - [`event`] — `DomainEvent`, `EventData`, `AggregateType`. The wire format
//!   for everything the client pushes and the server emits.
//! - [`permission`] — `Action`, `Resource`, `WalletRole`, `PermissionContext`.
//!   The vocabulary of access control.
//! - [`system_group`] — `SystemGroup`. The three wallet-scoped groups
//!   (`all_users`, `__owners__`, `all_contacts`) seeded on wallet
//!   creation; carried by name in events.
//!
//! ## What does NOT live here
//!
//! Anything that touches I/O, DB rows, async runtimes, or
//! flutter_rust_bridge. Those stay in the platform crates (`backend/rust-api`,
//! `sdk`). Dependencies are kept to serde + uuid + chrono so
//! the crate compiles for any target — server x86_64, mobile aarch64,
//! frontend wasm32.

pub mod event;
pub mod permission;
pub mod system_group;
pub mod transaction;

pub use event::{AggregateType, DomainEvent, EventData, EventType};
pub use permission::{Action, PermissionContext, Resource, WalletRole};
pub use system_group::{SystemGroup, SystemGroupKind};
pub use transaction::{Currency, TransactionDirection, TransactionType};
