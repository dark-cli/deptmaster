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
mod permissions;
mod balance;
mod multi_app_realtime;
mod ws_notifications;
mod ws_auto_sync;
mod transaction_crud_keeps_other_state;
mod hash_divergence;
mod sync_chain_hash_stress;
mod clear_wallet_anchor_regression;
mod permission_enforcement;
