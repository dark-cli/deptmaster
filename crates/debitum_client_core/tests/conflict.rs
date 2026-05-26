//! Conflict scenarios: simultaneous updates, update-delete conflict, offline-update conflict.
//!
//! Ported from Flutter conflict_scenarios.

use crate::common::test_helpers::{setup_three_apps, test_server_url};

/// Simultaneous updates from different apps; final state has multiple UPDATED events.
#[test]
#[ignore]
fn conflict_simultaneous_updates() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Original Name\" contact1",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app1: transaction create contact1 owed 2000 \"T3\" t3",
        "app1: transaction create contact1 lent 800 \"T4\" t4",
        "app1: transaction create contact1 owed 1500 \"T5\" t5",
        "app2: transaction create contact1 lent 600 \"T6\" t6",
        "app2: transaction create contact1 owed 1200 \"T7\" t7",
        "app3: transaction create contact1 lent 900 \"T8\" t8",
        "app3: transaction create contact1 owed 1800 \"T9\" t9",
        "app3: transaction create contact1 lent 400 \"T10\" t10",
        "app1: contact update contact1 name \"Updated by App1\"",
        "app2: contact update contact1 name \"Updated by App2\"",
        "app1: transaction update t1 amount 2000",
        "app2: transaction update t1 amount 3000",
        "app1: transaction update t3 amount 2200",
        "app2: transaction update t5 description \"Updated by App2\"",
        "app3: transaction update t7 amount 1300",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync");

    app1_ref.assert_commands(&[
        "events count >= 18",
        "events event_type UPDATED count >= 7",
        "contacts count 1",
        "transactions count > 8",
    ]).expect("assert_commands");
}

/// Update-delete conflict: one app updates, another deletes; delete wins for contact/transaction.
#[test]
#[ignore]
fn conflict_update_delete_resolution() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Contact to Conflict\" contact1",
        "app1: contact create \"Contact 2\" contact2",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact2 lent 800 \"T4\" t4",
        "app1: transaction create contact2 owed 1200 \"T5\" t5",
        "app2: transaction create contact1 lent 600 \"T6\" t6",
        "app3: transaction create contact2 lent 400 \"T10\" t10",
        "app1: wait 300",
        "app1: contact update contact1 name \"Updated Name\"",
        "app2: contact delete contact1",
        "app1: transaction update t4 amount 2000",
        "app2: transaction delete t4",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync");

    app1_ref.assert_commands(&[
        "contact name \"Contact to Conflict\" removed",
        "contact name \"Updated Name\" removed",
        "contacts count >= 1",
    ]).expect("assert_commands");
}

/// Offline update conflict: app1 offline updates, app2 online updates; both sync and resolve.
/// Skipped in Rust: go_offline() is thread-local, so we cannot have app1 offline while app2 syncs.
#[test]
#[ignore]
fn conflict_offline_update_then_sync() {
    eprintln!("Skipping: per-app offline not supported (single thread-local offline flag)");
}
