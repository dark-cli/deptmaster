//! Multi-app offline/online: partial offline (some apps online), offline multi-app conflict.
//!
//! Ported from Flutter offline_online_scenarios and comprehensive_event_generator_test.
//! These tests are skipped in Rust: go_offline() is thread-local, so per-app offline is not supported.

/// Partial offline: app1 offline, app2/app3 create online and sync; app1 creates offline, then app1 goes online and syncs.
/// Skipped in Rust: go_offline() is thread-local, so app2/app3 cannot sync while app1 is "offline".
#[test]
#[ignore]
fn partial_offline_some_apps_online() {
    eprintln!("Skipping: per-app offline not supported (single thread-local offline flag)");
}

/// Offline multi-app conflict: app1 and app2 go offline, both create contacts/transactions; app3 stays online; then app1/app2 go online and sync.
/// Skipped in Rust: go_offline() is thread-local, so app3 cannot sync while app1/app2 are "offline".
#[test]
#[ignore]
fn offline_multi_app_conflict_then_sync() {
    eprintln!("Skipping: per-app offline not supported (single thread-local offline flag)");
}
