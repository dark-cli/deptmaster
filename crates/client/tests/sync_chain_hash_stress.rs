//! Stress tests for the per-row chain-hash sync protocol (server migration
//! 033 + client `pull_and_merge` rewrite).
//!
//! What the protocol guarantees:
//!   - Client sends its `last_hash` from the previous pull.
//!   - Server does `WHERE hash = ?` lookup in user_readable_events.
//!     Found → returns events with greater id (incremental).
//!     Not found → returns all events + `flush=true`.
//!   - Client NEVER validates the hash; it just stores what the server
//!     returns and obeys the `flush` flag.
//!
//! What these tests check:
//!   - Rapid sequential CRUD (single app) doesn't ever spuriously flush.
//!   - Multi-app with one actor never wedges the observer's state.
//!   - First sync correctly flushes and absorbs.
//!   - WS-driven syncs converge even under burst load.
//!   - Pull after no changes returns empty (server's lookup hits the
//!     latest row, no events have greater id).
//!   - DELETE / UNDO mixed in don't break the chain.
//!
//! Failure signal: the previous protocol logged
//!   `[debitum_rs] pull_and_merge: hash diverged ...`
//! on every action under load. The new protocol can't produce that line
//! at all (it's been removed). The flush-on-recovery line is
//!   `[debitum_rs] pull_and_merge: server requested flush — wiping ...`
//! It's allowed on the FIRST sync of a fresh app and after permission
//! flips. ANY OTHER occurrence under normal CRUD is a regression.

use std::time::Duration;

use crate::common::app_instance::AppInstance;
use crate::common::test_helpers::{setup_three_apps, test_server_url};

/// Spin up a fresh user/wallet and run one warmup action so the client
/// has a NON-EMPTY last_hash stored before the real assertion window
/// starts. Without this, the first sync after the initial empty state
/// legitimately flushes (server can't tell that the client had nothing
/// to lose), which would muddy the "no spurious flush" assertion.
fn make_warmed_app(id: &str) -> AppInstance {
    let server_url = test_server_url();
    let app = AppInstance::new(id, &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");
    // First action + sync: anchors the client to a real hash in the
    // server's chain. Subsequent syncs should never flush.
    app.run_commands(&["contact create \"_warmup\" _warmup"])
        .expect("warmup contact create");
    app.sync().expect("warmup sync");
    app
}

/// A flush is allowed on the very first sync of a new client (no last_hash
/// to look up). Anything beyond that during normal CRUD is a regression in
/// the protocol.
fn count_flushes(logs: &[String]) -> usize {
    logs.iter()
        .filter(|l| l.contains("server requested flush"))
        .count()
}

fn assert_no_unexpected_flush(stage: &str, logs: &[String], allowed: usize) {
    let actual = count_flushes(logs);
    if actual > allowed {
        eprintln!("=== FULL LOG ({}) ===", stage);
        for line in logs {
            eprintln!("{}", line);
        }
        eprintln!("=== END LOG ===");
        panic!(
            "{}: {} flush(es) observed, expected at most {} — protocol is wedging",
            stage, actual, allowed
        );
    }
}

/// The simplest workflow: create a contact, sync, create transactions,
/// sync between each. With a warmed client, never flushes.
#[test]
#[ignore]
fn solo_explicit_sync_never_flushes_after_first() {
    let app = make_warmed_app("solo-explicit");
    let _ = client::drain_rust_logs();

    for cmd in &[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
        "transaction create alice lent 200  \"t2\" t2",
        "transaction create alice owed 500  \"t3\" t3",
    ] {
        app.run_commands(&[*cmd]).expect("run");
        app.sync().expect("sync");
    }

    let logs = client::drain_rust_logs();
    assert_no_unexpected_flush("solo + explicit syncs", &logs, 0);

    app.assert_commands(&[
        "contacts count 2", // _warmup + Alice
        "transactions count 3",
    ])
    .expect("final state");
}

/// Inline-push (from crud) + WS-triggered sync are the production code
/// path. Run a sequence with the WS worker on; assert no flush after the
/// first sync.
#[test]
#[ignore]
fn solo_with_ws_worker_no_flush_under_load() {
    let app = make_warmed_app("solo-ws");
    app.connect_realtime().expect("connect_realtime");
    std::thread::sleep(Duration::from_millis(500));
    // Drain warmup + initial WS-triggered sync logs.
    let _ = client::drain_rust_logs();

    app.run_commands(&["contact create \"Alice\" alice"])
        .expect("contact create");
    std::thread::sleep(Duration::from_millis(700));

    for cmd in &[
        "transaction create alice owed 100 \"t1\" t1",
        "transaction create alice lent  50 \"t2\" t2",
        "transaction create alice owed 200 \"t3\" t3",
        "transaction create alice lent  75 \"t4\" t4",
        "transaction create alice owed 300 \"t5\" t5",
        "transaction create alice lent  25 \"t6\" t6",
        "transaction create alice owed 400 \"t7\" t7",
        "transaction create alice lent 150 \"t8\" t8",
    ] {
        app.run_commands(&[*cmd]).expect("run");
        std::thread::sleep(Duration::from_millis(700));
    }
    std::thread::sleep(Duration::from_secs(2));
    app.disconnect_realtime().expect("disconnect_realtime");

    let logs = client::drain_rust_logs();
    assert_no_unexpected_flush("solo + ws + paced burst", &logs, 0);

    // Final state sanity check.
    app.assert_commands(&[
        "contacts count 2", // _warmup + Alice
        "transactions count 8",
        // signed: +100 -50 +200 -75 +300 -25 +400 -150 = 700
        "contact \"Alice\" balance 700",
    ])
    .expect("final state should match all 8 transactions");
}

/// Fire actions as fast as possible — no sleeps, no pacing. The protocol
/// must still converge without spurious flushes.
#[test]
#[ignore]
fn solo_rapid_fire_with_ws_no_spurious_flush() {
    let app = make_warmed_app("solo-rapid");
    app.connect_realtime().expect("connect_realtime");
    std::thread::sleep(Duration::from_millis(500));
    let _ = client::drain_rust_logs();

    app.run_commands(&["contact create \"Alice\" alice"])
        .expect("contact");
    app.run_commands(&[
        "transaction create alice owed 100 \"t1\" t1",
        "transaction create alice lent  50 \"t2\" t2",
        "transaction create alice owed 200 \"t3\" t3",
        "transaction create alice lent  75 \"t4\" t4",
        "transaction create alice owed 300 \"t5\" t5",
        "transaction create alice lent  25 \"t6\" t6",
        "transaction create alice owed 400 \"t7\" t7",
        "transaction create alice lent 150 \"t8\" t8",
    ])
    .expect("burst");
    std::thread::sleep(Duration::from_secs(3));
    app.disconnect_realtime().expect("disconnect_realtime");

    let logs = client::drain_rust_logs();
    assert_no_unexpected_flush("solo + ws + rapid-fire burst", &logs, 0);

    app.assert_commands(&[
        "contacts count 2", // _warmup + Alice
        "transactions count 8",
        "contact \"Alice\" balance 700",
    ])
    .expect("rapid CRUD must converge");
}

/// DELETE-after-CREATE is the exact pattern the user reported. Walk through
/// it with explicit syncs and assert no flush fires.
#[test]
#[ignore]
fn solo_delete_after_create_never_flushes() {
    let app = make_warmed_app("solo-delete");
    let _ = client::drain_rust_logs();

    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
        "transaction create alice owed  500 \"t2\" t2",
        "transaction create alice lent  200 \"t3\" t3",
    ])
    .expect("setup");
    app.sync().expect("sync 1");

    // The bug shape: delete one, sync; the previous protocol diverged here.
    app.run_commands(&["transaction delete t2"])
        .expect("delete t2");
    app.sync().expect("sync after delete");

    let logs = client::drain_rust_logs();
    assert_no_unexpected_flush("solo delete-after-create", &logs, 0);

    app.assert_commands(&[
        "contacts count 2", // _warmup + Alice
        "transactions count 2",
        // +1000 t1, -200 t3 = +800. t2 soft-deleted.
        "contact \"Alice\" balance 800",
    ])
    .expect("post-delete state");
}

/// Multi-app via the test framework. One acts, the other observes via WS.
/// Each app must converge to the same final state without spurious
/// flushes.
/// Multi-app via the test framework, using explicit syncs (no WS). The
/// per-app SQLite isolation + per-thread WS workers in the test
/// framework make WS-driven multi-app tests sensitive to scheduling; the
/// production guarantee we want here is just "two apps on the same
/// wallet converge to the same state through pull, with no spurious
/// flushes". Explicit syncs exercise that without the framework
/// confounders.
#[test]
#[ignore]
fn multi_app_actor_observer_no_spurious_flush() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let app1 = generator.apps.get("app1").unwrap();
    let app2 = generator.apps.get("app2").unwrap();

    // Warmup app1: one action + sync so its last_hash is non-empty.
    app1.activate().expect("activate app1");
    app1.run_commands(&["contact create \"_warmup\" _warmup"])
        .expect("warmup contact create");
    app1.sync().expect("warmup sync app1");

    // Warmup app2: explicit sync to absorb the warmup contact and store
    // its own non-empty last_hash.
    app2.activate().expect("activate app2");
    app2.sync().expect("warmup sync app2");

    let _ = client::drain_rust_logs();

    // app1 is the actor. Each command pushes to server inline; the
    // explicit app1.sync() after every command shouldn't return any new
    // events (it pushed them itself) and shouldn't flush.
    app1.activate().expect("activate app1 for actions");
    for cmd in &[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
        "transaction create alice lent  300 \"t2\" t2",
        "transaction create alice owed  500 \"t3\" t3",
        "transaction delete t1",
    ] {
        app1.run_commands(&[*cmd]).expect("actor action");
        app1.sync().expect("actor sync");
    }

    // app2 pulls the actor's events.
    app2.activate().expect("activate app2 for pull");
    app2.sync().expect("observer sync");

    let logs = client::drain_rust_logs();
    assert_no_unexpected_flush("multi-app actor/observer", &logs, 0);

    app2.assert_commands(&[
        "contacts count 2", // _warmup + Alice
        "transactions count 2",
        // After delete of t1 (undo path since within 5s window — net
        // effect: t1 cancelled): -300 t2 +500 t3 = +200.
        "contact \"Alice\" balance 200",
    ])
    .expect("observer should see actor's final state");
}

/// A pull with no new events on the server should return zero events
/// AND not flush — the server's WHERE hash = ? hits the latest row and
/// produces an empty incremental.
#[test]
#[ignore]
fn empty_pull_returns_zero_events_no_flush() {
    let app = make_warmed_app("solo-empty");
    let _ = client::drain_rust_logs();

    // Five back-to-back syncs with no intervening actions.
    for _ in 0..5 {
        app.sync().expect("idle sync");
    }

    let logs = client::drain_rust_logs();
    assert_no_unexpected_flush("idle syncs", &logs, 0);

    // The protocol logs "server returned N events" on every pull.
    // Idle syncs must report 0.
    let non_zero_pulls = logs
        .iter()
        .filter(|l| l.contains("server returned"))
        .filter(|l| !l.contains("server returned 0 events"))
        .count();
    assert_eq!(
        non_zero_pulls, 0,
        "idle syncs should never return events; got {} non-zero pulls",
        non_zero_pulls,
    );
}

/// UNDO is the one event type the old protocol had a special rebuild path
/// for. Verify the new protocol handles it cleanly.
#[test]
#[ignore]
fn solo_undo_inside_window_never_flushes() {
    let app = make_warmed_app("solo-undo");
    let _ = client::drain_rust_logs();

    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
    ])
    .expect("setup");
    app.sync().expect("sync 1");

    // Delete-with-undo runs an UNDO event (delete within the 5s window).
    app.run_commands(&["transaction delete t1"])
        .expect("delete t1 (undo)");
    app.sync().expect("sync after delete");

    let logs = client::drain_rust_logs();
    assert_no_unexpected_flush("solo with undo", &logs, 0);
}
