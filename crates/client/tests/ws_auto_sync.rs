//! Regression test: WebSocket auto-sync works.
//!
//! Per the dart-is-ui-only rule, WebSocket handling must live in the
//! Rust client crate, not in Dart. This test asserts that when a
//! transaction is created (inline push to server), the server broadcasts
//! `events_synced`, and the Rust WS worker receives it and triggers
//! `manual_sync` automatically — with no explicit `app.sync()` call.
//!
//! Companion to `ws_notifications::server_broadcasts_events_synced_*`
//! (which proves server emits the message) and `multi_app_realtime::*`
//! (which proves plain push/pull works). This test proves the missing
//! piece: that Rust subscribes to WS and triggers `manual_sync` on
//! `events_synced`.

use std::time::Duration;

use crate::common::test_helpers::test_server_url;

fn make_app() -> crate::common::app_instance::AppInstance {
    let server_url = test_server_url();
    let app = crate::common::app_instance::AppInstance::new("app", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");
    // Warm up: anchor last_hash to a real chain entry so subsequent
    // WS-triggered pulls never see flush=true. Without this, the first
    // sync after signup wipes the projection — and if it races with
    // crud's load-after-create, the create returns "Transaction not found".
    app.run_commands(&["contact create \"_warmup\" _warmup"])
        .expect("warmup");
    app.sync().expect("warmup sync");
    app
}

#[test]
#[ignore]
fn transaction_create_auto_syncs_peer_via_ws_owned_by_rust() {
    let app = make_app();

    // Start the Rust-side WS worker. After this returns, the worker
    // thread is listening for events_synced from the server.
    app.connect_realtime().expect("app connect_realtime");

    // Give the worker a moment to finish handshake before creating.
    std::thread::sleep(Duration::from_millis(500));

    // Create a transaction. crud::create_transaction's inline push_unsynced
    // reaches the server; the server's POST /api/sync handler then
    // broadcasts events_synced on the wallet's WS topic.
    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"x\" t1",
    ])
    .expect("create contact and transaction");

    // Wait for the WS worker to receive the message and run manual_sync.
    // NO explicit app.sync() here — that's the whole point.
    // If this fails, the Rust WS worker isn't wired up correctly.
    std::thread::sleep(Duration::from_secs(2));

    app.assert_commands(&[
        "contacts count 2",  // _warmup + Alice
        "contact name \"Alice\"",
        "transactions count 1",
    ])
    .expect("WS auto-sync must work without explicit sync");

    // Cleanup so the worker thread exits before the next test starts.
    app.disconnect_realtime()
        .expect("app disconnect_realtime");
}
