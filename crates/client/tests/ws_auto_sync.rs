//! Regression test for bug 1, post-architectural-fix.
//!
//! Per the dart-is-ui-only rule, WebSocket handling must live in the
//! Rust client crate, not in Dart. This test asserts the end-to-end
//! property the user actually cares about: when app1 creates a
//! transaction, app2 picks it up automatically through its Rust-owned
//! WS connection, with no explicit `app2.sync()` call.
//!
//! Companion to `ws_notifications::server_broadcasts_events_synced_*`
//! (which proves the server emits the message) and
//! `multi_app_realtime::*` (which proves the plain push/pull works).
//! This test proves the missing piece: that Rust subscribes to the
//! WS and triggers `manual_sync` on `events_synced`.

use std::time::Duration;

use crate::common::test_helpers::{setup_three_apps, test_server_url};

#[test]
#[ignore]
fn transaction_create_auto_syncs_peer_via_ws_owned_by_rust() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);

    let app2 = generator.apps.get("app2").unwrap();

    // app2 starts the Rust-side WS worker. After this returns, the
    // worker thread is listening for events_synced from the server.
    app2.connect_realtime().expect("app2 connect_realtime");

    // Give the worker a moment to finish handshake before app1 acts.
    std::thread::sleep(Duration::from_millis(500));

    // app1 creates a transaction. crud::create_transaction's inline
    // push_unsynced reaches the server; the server's POST /api/sync
    // handler then broadcasts events_synced on the wallet's WS topic.
    generator
        .execute_commands(&[
            "app1: contact create \"Alice\" alice",
            "app1: transaction create alice owed 1000 \"x\" t1",
        ])
        .expect("execute_commands");

    // Test-framework subtlety: the SDK's SQLite handle is a process-wide
    // global. `app1: ...` above switched the global handle to app1's
    // tempdir DB. Re-bind it to app2's BEFORE the WS-triggered sync
    // fires, so the sync writes into app2's projection tables (which
    // is where assert_commands below will read from). In production
    // each device runs a single app, so there's only ever one handle —
    // this re-bind is purely a test isolation thing.
    app2.activate()
        .expect("re-bind storage to app2 before WS sync arrives");

    // Wait for app2's WS worker to receive the message and run
    // manual_sync. NO explicit app2.sync() here — that's the whole
    // point. If this fails, the Rust WS worker isn't wired up.
    std::thread::sleep(Duration::from_secs(2));

    app2.assert_commands(&[
        "contacts count 1",
        "contact name \"Alice\"",
        "transactions count 1",
    ])
    .expect("app2 must auto-sync on ws events_synced without explicit sync");

    // Cleanup so the worker thread exits before the next test starts.
    app2.disconnect_realtime()
        .expect("app2 disconnect_realtime");
}
