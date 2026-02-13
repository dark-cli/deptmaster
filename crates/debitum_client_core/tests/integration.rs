//! Single integration test binary: all integration tests as modules.
//! Shared common code is compiled once, so no dead_code from per-binary subsets.
//!
//! Run: `cargo test --test integration -- --ignored`
//! Filter by module: `cargo test --test integration single_app:: -- --ignored`

mod common;
mod single_app;
mod multi_app_sync;
mod comprehensive_events;
mod offline_online_multi_app;
mod conflict;
mod resync;
mod stress;
mod connection;
mod permissions;
mod groups;
