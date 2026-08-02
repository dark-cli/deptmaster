//! Single integration test binary: all integration tests as modules.
//! Shared common code is compiled once, so no dead_code from per-binary subsets.
//!
//! Run: `cargo test --test integration -- --ignored`
//! Filter by module: `cargo test --test integration single_app:: -- --ignored`

mod balance;
mod clear_wallet_anchor_regression;
mod common;
mod comprehensive_events;
mod conflict;
mod delegable_permissions_client_test;
mod delegable_permissions_layers_test;
mod hash_divergence;
mod logout_clears_local_data;
mod multi_app_realtime;
mod multi_app_sync;
mod offline_online_multi_app;
mod owner_permission_security_test;
mod permission_enforcement;
mod permission_matrix_undo_persistence;
mod permissions;
mod permission_edit_without_read_modern;
mod resync;
mod single_app;
mod sync_chain_hash_stress;
mod transaction_crud_keeps_other_state;
mod ws_auto_sync;
mod ws_notifications;
