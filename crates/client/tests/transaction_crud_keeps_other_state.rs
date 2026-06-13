//! Regression tests for bugs 1 + 2: a transaction CRUD op (delete
//! or create) sometimes wipes the wallet's local projection. The
//! server stays correct; a later, unrelated event triggers another
//! sync that repopulates the local state.
//!
//! Symptom: after `transaction delete X`, the wallet's local
//! contacts + other transactions briefly read as empty. After
//! `transaction create Y`, the previous transactions also vanish
//! briefly.
//!
//! Hypothesis: sync::pull_and_merge's hash-divergence path fires
//! `events_delete_all_for_wallet` after the local CRUD's push, but
//! the subsequent full pull either fails or completes against stale
//! storage state, leaving the projection tables empty until the
//! next sync re-runs.

use crate::common::app_instance::AppInstance;
use crate::common::test_helpers::test_server_url;

fn make_app() -> AppInstance {
    let server_url = test_server_url();
    let app = AppInstance::new("app", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");
    app
}

/// Delete one transaction out of three; the other two and the
/// contact must remain in the local projection.
#[test]
#[ignore]
fn deleting_one_transaction_keeps_contact_and_other_transactions() {
    let app = make_app();
    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
        "transaction create alice owed 500  \"t2\" t2",
        "transaction create alice lent 200  \"t3\" t3",
    ])
    .expect("setup");
    app.sync().expect("initial sync");

    // Sanity check before the buggy op.
    app.assert_commands(&["contacts count 1", "transactions count 3"])
        .expect("pre-delete state");

    // The op under test.
    app.run_commands(&["transaction delete t2"]).expect("delete t2");
    app.sync().expect("sync after delete");

    // Bug claim: the wallet gets wiped locally. Correct behavior:
    // contact stays, t1 and t3 stay, t2 is gone (soft-deleted).
    // Balance also recomputes: +1000 (t1) -200 (t3) = +800.
    app.assert_commands(&[
        "contacts count 1",
        "transactions count 2",
        "contact \"Alice\" balance 800",
    ])
    .expect("only t2 should be gone — other state must survive");
}

/// Create a second transaction; the first one must still be there.
#[test]
#[ignore]
fn creating_a_second_transaction_keeps_the_first() {
    let app = make_app();
    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
    ])
    .expect("setup");
    app.sync().expect("initial sync");

    app.assert_commands(&["contacts count 1", "transactions count 1"])
        .expect("pre-create-2 state");

    app.run_commands(&["transaction create alice lent 300 \"t2\" t2"])
        .expect("create t2");
    app.sync().expect("sync after create");

    // Bug claim: the first transaction disappears. Correct behavior:
    // both transactions are present. Balance: +1000 -300 = +700.
    app.assert_commands(&[
        "contacts count 1",
        "transactions count 2",
        "contact \"Alice\" balance 700",
    ])
    .expect("both transactions must be present");
}

/// Same as `deleting_one_transaction_keeps_contact_and_other_transactions`
/// but the sync is triggered by the Rust WS worker, not an explicit
/// `app.sync()`. This is the production code path: in the live app,
/// crud::create/delete pushes; server broadcasts events_synced; the
/// WS worker triggers manual_sync; pull_and_merge runs. If this path
/// hits the hash-divergence branch and wipes the projection without
/// re-applying correctly, the bug shows up here and NOT in the
/// explicit-sync version above.
#[test]
#[ignore]
fn deleting_transaction_via_ws_sync_keeps_other_state() {
    let app = make_app();
    app.connect_realtime().expect("connect_realtime");
    // Let the worker open the socket before we act.
    std::thread::sleep(std::time::Duration::from_millis(500));

    app.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1000 \"t1\" t1",
        "transaction create alice owed 500  \"t2\" t2",
        "transaction create alice lent 200  \"t3\" t3",
    ])
    .expect("setup");
    // Wait for the WS-triggered syncs from the setup events to settle.
    std::thread::sleep(std::time::Duration::from_secs(1));

    app.run_commands(&["transaction delete t2"]).expect("delete t2");
    // Crucially: NO explicit sync. The WS worker's events_synced
    // handler must run manual_sync, and that path must NOT wipe the
    // wallet.
    std::thread::sleep(std::time::Duration::from_secs(2));

    app.assert_commands(&[
        "contacts count 1",
        "transactions count 2",
        "contact \"Alice\" balance 800",
    ])
    .expect("WS-triggered sync after a delete must not wipe other state");

    app.disconnect_realtime().expect("disconnect_realtime");
}

/// Rapid CRUD bursts with the Rust WS worker on. Every event_synced
/// fires a sync, so 8 creates + 1 delete in quick succession can race
/// the SDK's in-flight guard (thread_local in the buggy version =
/// no protection across spawned threads). If the race produces a
/// stale `previous_hash` stash, the next pull_and_merge wrongly
/// flags divergence and wipes the projection. Symptom: final state
/// missing rows or showing stale balances.
#[test]
#[ignore]
fn rapid_transaction_crud_burst_does_not_corrupt_state() {
    let app = make_app();
    app.connect_realtime().expect("connect_realtime");
    std::thread::sleep(std::time::Duration::from_millis(500));

    app.run_commands(&["contact create \"Alice\" alice"])
        .expect("contact");
    // 8 rapid transaction creates. Each triggers a push and (via the
    // server broadcast) an WS-driven sync on a fresh spawned thread.
    app.run_commands(&[
        "transaction create alice owed 100 \"t1\" t1",
        "transaction create alice lent 50  \"t2\" t2",
        "transaction create alice owed 200 \"t3\" t3",
        "transaction create alice lent 75  \"t4\" t4",
        "transaction create alice owed 300 \"t5\" t5",
        "transaction create alice lent 25  \"t6\" t6",
        "transaction create alice owed 400 \"t7\" t7",
        "transaction create alice lent 150 \"t8\" t8",
    ])
    .expect("rapid creates");
    // One delete in the middle of the burst's tail.
    app.run_commands(&["transaction delete t5"]).expect("delete t5");

    // Let all the WS-triggered syncs drain.
    std::thread::sleep(std::time::Duration::from_secs(3));

    // Net balance: +100 -50 +200 -75 (t5 deleted) -25 +400 -150 = +400
    app.assert_commands(&[
        "contacts count 1",
        "transactions count 7",
        "contact \"Alice\" balance 400",
    ])
    .expect("rapid CRUD must converge to the correct state");

    app.disconnect_realtime().expect("disconnect_realtime");
}

/// Mixed CRUD: create, delete, create. Final state must reflect all
/// three operations correctly without any wipe-and-partial-rebuild
/// artifact.
#[test]
#[ignore]
fn mixed_transaction_crud_does_not_wipe_state() {
    let app = make_app();
    app.run_commands(&[
        "contact create \"Alice\" alice",
        "contact create \"Bob\" bob",
        "transaction create alice owed 1000 \"t1\" t1",
        "transaction create bob   lent 400  \"t2\" t2",
    ])
    .expect("setup");
    app.sync().expect("initial sync");

    // delete one, create one
    app.run_commands(&[
        "transaction delete t2",
        "transaction create alice lent 300 \"t3\" t3",
    ])
    .expect("mixed crud");
    app.sync().expect("sync after mixed");

    app.assert_commands(&[
        "contacts count 2",
        "transactions count 2",
        "contact \"Alice\" balance 700", // +1000 - 300
        "contact \"Bob\" balance 0",     // t2 soft-deleted
    ])
    .expect("mixed CRUD must preserve unrelated state");
}
