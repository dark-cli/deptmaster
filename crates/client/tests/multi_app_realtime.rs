//! Regression tests for the "transaction CRUD doesn't trigger
//! cross-app sync" report.
//!
//! Bug being captured: after one app creates / updates / deletes a
//! transaction, peer apps on the same wallet should observe the
//! change as soon as they sync (the production app uses a WebSocket
//! ping to trigger that sync automatically). These tests use
//! `app.sync()` directly — they exercise the push + pull flow only,
//! NOT the WebSocket bridge. If THESE tests fail, the bug is in
//! the push or pull path, not just the WS routing.
//!
//! Existing `multi_app_sync.rs` covers a similar shape but always
//! calls `app1.sync()` AFTER its creates, hiding the case where the
//! create call itself should already have pushed. These tests skip
//! the explicit app1 sync between the action and the cross-app pull
//! so a missing push surfaces.

use crate::common::test_helpers::{setup_three_apps, test_server_url};

/// app1 creates one transaction → no extra app1.sync() → app2 syncs
/// and should see it. If this fails, `crud::create_transaction`'s
/// inline `push_unsynced` isn't happening (or isn't completing) for
/// transaction events.
#[test]
#[ignore]
fn transaction_create_propagates_to_peer_without_explicit_app1_sync() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);

    generator
        .execute_commands(&[
            "app1: contact create \"Alice\" alice",
            // crud::append_event runs push_unsynced inline after each
            // append, so by the time these return the server should
            // already hold the rows.
            "app1: transaction create alice owed 500 \"a\" t1",
            "app1: transaction create alice lent 200 \"b\" t2",
        ])
        .expect("execute_commands");

    // Note: NO explicit app1.sync() here. The deltas above must already
    // be on the server by the time the create_transaction call returns.
    std::thread::sleep(std::time::Duration::from_millis(500));

    let app2 = generator.apps.get("app2").unwrap();
    app2.sync().expect("app2 sync");

    app2.assert_commands(&[
        "contacts count 1",
        "contact name \"Alice\"",
        "transactions count 2",
    ])
    .expect("app2 must see the contact + both transactions");
}

/// app1 updates a transaction → no app1.sync() in between → app2 sees
/// the updated amount. If this fails, transaction UPDATED events don't
/// push.
#[test]
#[ignore]
fn transaction_update_propagates_to_peer_without_explicit_app1_sync() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);

    generator
        .execute_commands(&[
            "app1: contact create \"Alice\" alice",
            "app1: transaction create alice owed 500 \"a\" t1",
        ])
        .expect("execute_commands (initial)");

    // Settle the create across all apps so the update is the only
    // event left to propagate.
    let app1 = generator.apps.get("app1").unwrap();
    let app2 = generator.apps.get("app2").unwrap();
    app1.sync().expect("app1 sync after create");
    app2.sync().expect("app2 sync after create");

    // The update — NO explicit app1.sync() between this and app2.sync().
    generator
        .execute_commands(&["app1: transaction update t1 amount 1234"])
        .expect("execute_commands (update)");

    std::thread::sleep(std::time::Duration::from_millis(500));
    app2.sync().expect("app2 sync after update");

    app2.assert_commands(&[
        "transactions count 1",
        "events event_type UPDATED count >= 1",
    ])
    .expect("app2 must observe the UPDATE");
}

/// app1 deletes a transaction → app2 sees the deletion. Same pattern.
#[test]
#[ignore]
fn transaction_delete_propagates_to_peer_without_explicit_app1_sync() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);

    generator
        .execute_commands(&[
            "app1: contact create \"Alice\" alice",
            "app1: transaction create alice owed 500 \"a\" t1",
            "app1: transaction create alice owed 800 \"b\" t2",
        ])
        .expect("execute_commands (initial)");

    let app1 = generator.apps.get("app1").unwrap();
    let app2 = generator.apps.get("app2").unwrap();
    app1.sync().expect("app1 sync after creates");
    app2.sync().expect("app2 sync after creates");

    generator
        .execute_commands(&["app1: transaction delete t2"])
        .expect("execute_commands (delete)");

    std::thread::sleep(std::time::Duration::from_millis(500));
    app2.sync().expect("app2 sync after delete");

    app2.assert_commands(&["transactions count 1"])
        .expect("app2 must observe the delete");
}
