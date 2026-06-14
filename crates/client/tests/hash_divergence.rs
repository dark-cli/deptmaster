//! Reproducer for the hash-divergence-on-actor bug reported by the user.
//!
//! Symptom (from production logs):
//!   [debitum_rs] push_unsynced wallet_id=... accepted=1
//!   [debitum_rs] pull_and_merge: server returned 1 events
//!   [debitum_rs] pull_and_merge: hash diverged (server=..., computed=...)
//!     — events removed from view; clearing and full pull
//!
//! The actor app sees the divergence-recovery path fire on EVERY action,
//! wiping the local projection and refetching. This produces the visible
//! "data flashes empty" / "deleted things come back" / "unknown contact"
//! behavior in the UI.
//!
//! The observer app (one that only receives WS notifications, never
//! pushes) does NOT see the divergence — proof that the bug is on the
//! actor's pull-after-push code path specifically.
//!
//! These tests scrape `client::drain_rust_logs()` for "hash diverged"
//! lines. If any appear, the test fails with the full log dump so we
//! can see the values (previous_hash, folded ids, server_hash) that
//! went out of sync.

use std::time::Duration;

use crate::common::app_instance::AppInstance;
use crate::common::test_helpers::test_server_url;

fn make_app() -> AppInstance {
    let server_url = test_server_url();
    let app = AppInstance::new("actor", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");
    // Warm up: anchor last_hash to a real chain entry so subsequent
    // WS-triggered pulls never see flush=true. Without this, the first
    // sync after signup wipes the projection — and if it races with
    // crud's load-after-create, the create returns "Transaction not
    // found after create".
    app.run_commands(&["contact create \"_warmup\" _warmup"])
        .expect("warmup contact");
    app.sync().expect("warmup sync");
    app
}

fn assert_no_divergence_in_logs(stage: &str) {
    let logs = client::drain_rust_logs();
    let divergence_lines: Vec<&String> = logs
        .iter()
        .filter(|line| line.contains("hash diverged"))
        .collect();
    if !divergence_lines.is_empty() {
        // Dump the surrounding context — the lines immediately before
        // each divergence are usually where the discrepancy started.
        eprintln!("=== FULL LOG AT FAILURE ({}) ===", stage);
        for line in &logs {
            eprintln!("{}", line);
        }
        eprintln!("=== END LOG ===");
        panic!(
            "{}: {} hash divergence(s) detected in pull_and_merge — actor's previous_hash drifted from server's user_event_hashes",
            stage,
            divergence_lines.len()
        );
    }
}

/// Baseline: one contact, two transactions, all via explicit sync.
/// If THIS diverges, the bug is in the simplest possible flow.
#[test]
#[ignore]
fn actor_explicit_sync_no_divergence() {
    let app = make_app();
    // Drain the signup/wallet-creation logs so we only inspect what
    // this test produces.
    let _ = client::drain_rust_logs();

    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
        "transaction create alice lent 200 \"t2\" t2",
    ])
    .expect("setup");
    app.sync().expect("sync 1");

    assert_no_divergence_in_logs("after explicit sync of 3 actions");
}

/// Each push happens inline via crud::append_event → sync::push_unsynced.
/// Then we run manual_sync to mimic the WS-triggered pull that the
/// production bug appears in.
#[test]
#[ignore]
fn actor_inline_push_then_manual_sync_no_divergence() {
    let app = make_app();
    let _ = client::drain_rust_logs();

    // Each command's append_event pushes inline. After the push, run a
    // manual_sync to simulate the WS pull that fires for the same event.
    for cmd in &[
        "contact create \"Alice\" alice",
        "transaction create alice owed 100 \"t1\" t1",
        "transaction create alice owed 200 \"t2\" t2",
        "transaction create alice lent 50  \"t3\" t3",
        "transaction create alice owed 300 \"t4\" t4",
    ] {
        app.run_commands(&[*cmd]).expect("run");
        app.sync().expect("manual_sync between actions");
    }

    assert_no_divergence_in_logs("after inline-push + post-action manual_sync ×5");
}

/// Production path: WS worker on, actor performs actions, WS-triggered
/// syncs fire in the background. This is the exact scenario in the
/// user's log dump.
#[test]
#[ignore]
fn actor_with_ws_worker_no_divergence() {
    let app = make_app();
    app.connect_realtime().expect("connect_realtime");
    std::thread::sleep(Duration::from_millis(500));
    let _ = client::drain_rust_logs();

    app.run_commands(&["contact create \"Alice\" alice"])
        .expect("contact create");
    std::thread::sleep(Duration::from_millis(800));

    for cmd in &[
        "transaction create alice owed 100 \"t1\" t1",
        "transaction create alice owed 200 \"t2\" t2",
        "transaction create alice lent 50  \"t3\" t3",
        "transaction create alice owed 300 \"t4\" t4",
        "transaction create alice lent 75  \"t5\" t5",
    ] {
        app.run_commands(&[*cmd]).expect("run");
        // Give the WS worker time to fire its sync before the next
        // action. The production trace shows ~10ms between user
        // taps; we use 800ms to favor reliable repro over speed.
        std::thread::sleep(Duration::from_millis(800));
    }

    // Final settle to let any in-flight sync finish.
    std::thread::sleep(Duration::from_secs(2));

    app.disconnect_realtime().expect("disconnect_realtime");

    assert_no_divergence_in_logs("after 5 sequential WS-triggered syncs by the actor");
}

/// Rapid-fire actions BEFORE the previous sync settles. Closer to the
/// "user taps fast" case where the WS-triggered sync from action N may
/// race with action N+1's inline push.
#[test]
#[ignore]
fn actor_rapid_fire_no_divergence() {
    let app = make_app();
    app.connect_realtime().expect("connect_realtime");
    std::thread::sleep(Duration::from_millis(500));
    let _ = client::drain_rust_logs();

    app.run_commands(&["contact create \"Alice\" alice"])
        .expect("contact create");

    // No sleeps between actions — let them stack up however the
    // runtime schedules them.
    app.run_commands(&[
        "transaction create alice owed 100 \"t1\" t1",
        "transaction create alice lent 50  \"t2\" t2",
        "transaction create alice owed 200 \"t3\" t3",
        "transaction create alice owed 300 \"t4\" t4",
        "transaction create alice lent 75  \"t5\" t5",
        "transaction create alice owed 400 \"t6\" t6",
        "transaction create alice lent 25  \"t7\" t7",
        "transaction create alice owed 150 \"t8\" t8",
    ])
    .expect("burst");

    // Let WS-triggered syncs settle.
    std::thread::sleep(Duration::from_secs(3));

    app.disconnect_realtime().expect("disconnect_realtime");

    assert_no_divergence_in_logs("after a rapid 8-action burst");
}
