//! Comprehensive event scenarios: contact/transaction event types, mixed operations, full lifecycle.
//!
//! Uses three apps (same user). After execute_commands: sleep 300ms then one sync. See docs/INTEGRATION_TEST_COMMANDS.md.
//! Run: `cargo test --test integration_comprehensive_events -- --ignored`

mod common;

use common::test_helpers::{setup_three_apps, test_server_url};

/// Contact event types: CREATED, UPDATED, DELETED.
#[test]
#[ignore]
fn comprehensive_contact_event_types() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Test Contact 1\" contact1",
        "app1: contact create \"Test Contact 2\" contact2",
        "app1: contact create \"Test Contact 3\" contact3",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app1: transaction create contact2 owed 2000 \"T3\" t3",
        "app1: transaction create contact2 lent 800 \"T4\" t4",
        "app1: transaction create contact3 owed 1500 \"T5\" t5",
        "app1: transaction create contact3 lent 600 \"T6\" t6",
        "app1: wait 300",
        "app2: contact update contact1 name \"Updated Name 1\"",
        "app2: contact update contact2 name \"Updated Name 2\"",
        "app1: transaction update t1 amount 1100",
        "app1: transaction update t3 description \"Updated T3\"",
        "app3: contact delete contact3",
        "app1: transaction delete t5",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events aggregate_type contact event_type CREATED count 3",
        "events aggregate_type contact event_type UPDATED count 2",
        "events aggregate_type contact event_type DELETED count 1",
    ]).expect("assert_commands");
}

/// Transaction event types: CREATED, UPDATED, DELETED (or UNDO).
#[test]
#[ignore]
fn comprehensive_transaction_event_types() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Contact for Transaction\" contact1",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app1: transaction create contact1 owed 2000 \"T3\" t3",
        "app1: transaction create contact1 lent 800 \"T4\" t4",
        "app1: transaction create contact1 owed 1500 \"T5\" t5",
        "app1: transaction create contact1 lent 600 \"T6\" t6",
        "app1: transaction create contact1 owed 1200 \"T7\" t7",
        "app1: transaction create contact1 lent 900 \"T8\" t8",
        "app1: transaction create contact1 owed 1800 \"T9\" t9",
        "app1: transaction create contact1 lent 400 \"T10\" t10",
        "app1: wait 300",
        "app2: transaction update t1 amount 2000",
        "app2: transaction update t2 description \"Updated T2\"",
        "app2: transaction update t3 amount 2200",
        "app2: transaction update t4 description \"Updated T4\"",
        "app3: transaction delete t5",
        "app3: transaction delete t6",
        "app3: transaction delete t7",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events aggregate_type transaction event_type CREATED count >= 10",
        "events aggregate_type transaction event_type UPDATED count >= 4",
    ]).expect("assert_commands");
}

/// Mixed operations: contacts and transactions from multiple apps; all event types present.
#[test]
#[ignore]
fn comprehensive_mixed_operations() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Contact 1\" contact1",
        "app1: contact create \"Contact 2\" contact2",
        "app2: transaction create contact1 owed 1000 \"T1\" t1",
        "app2: transaction create contact1 lent 500 \"T2\" t2",
        "app2: transaction create contact1 owed 2000 \"T3\" t3",
        "app2: transaction create contact2 lent 800 \"T4\" t4",
        "app2: transaction create contact2 owed 1200 \"T5\" t5",
        "app3: transaction create contact1 lent 600 \"T6\" t6",
        "app3: transaction create contact1 owed 1500 \"T7\" t7",
        "app3: transaction create contact2 lent 900 \"T8\" t8",
        "app3: transaction create contact2 owed 1800 \"T9\" t9",
        "app1: transaction create contact1 lent 400 \"T10\" t10",
        "app1: transaction create contact2 owed 1100 \"T11\" t11",
        "app1: wait 300",
        "app3: contact update contact1 name \"Updated Contact 1\"",
        "app3: transaction update t1 amount 1500",
        "app1: transaction update t3 description \"Updated T3\"",
        "app2: transaction update t5 amount 1300",
        "app1: transaction delete t6",
        "app2: transaction delete t8",
        "app3: transaction create contact1 owed 1300 \"T12\" t12",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events aggregate_type contact count > 2",
        "events aggregate_type transaction count > 15",
        "events aggregate_type contact event_type CREATED count >= 1",
        "events aggregate_type contact event_type UPDATED count >= 1",
        "events aggregate_type transaction event_type CREATED count >= 1",
        "events aggregate_type transaction event_type UPDATED count >= 1",
        "events aggregate_type transaction event_type DELETED or UNDO count >= 1",
    ]).expect("assert_commands");
}

/// Concurrent mixed operations across all three apps.
#[test]
#[ignore]
fn comprehensive_concurrent_mixed_operations() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Contact from App1\" contact1",
        "app2: contact create \"Contact from App2\" contact2",
        "app3: contact create \"Contact from App3\" contact3",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact2 lent 500 \"T2\" t2",
        "app2: transaction create contact2 owed 2000 \"T3\" t3",
        "app2: transaction create contact3 lent 750 \"T4\" t4",
        "app3: transaction create contact3 owed 3000 \"T5\" t5",
        "app3: transaction create contact1 lent 1000 \"T6\" t6",
        "app1: transaction create contact1 owed 1500 \"T7\" t7",
        "app1: transaction create contact2 lent 600 \"T8\" t8",
        "app2: transaction create contact2 owed 2500 \"T9\" t9",
        "app2: transaction create contact3 lent 850 \"T10\" t10",
        "app3: transaction create contact3 owed 3500 \"T11\" t11",
        "app3: transaction create contact1 lent 1100 \"T12\" t12",
        "app1: transaction create contact1 owed 1200 \"T13\" t13",
        "app1: transaction create contact2 lent 700 \"T14\" t14",
        "app2: transaction create contact2 owed 1800 \"T15\" t15",
        "app2: transaction create contact3 lent 550 \"T16\" t16",
        "app3: transaction create contact3 owed 2200 \"T17\" t17",
        "app3: transaction create contact1 lent 900 \"T18\" t18",
        "app1: wait 300",
        "app1: transaction update t1 amount 1100",
        "app2: transaction update t3 description \"Updated T3\"",
        "app3: transaction delete t5",
        "app1: transaction delete t7",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events aggregate_type contact count 3",
        "events aggregate_type transaction count > 20",
    ]).expect("assert_commands");
}

/// Full lifecycle: create, update, delete for both contacts and transactions.
#[test]
#[ignore]
fn comprehensive_full_lifecycle() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Lifecycle Contact\" contact1",
        "app1: contact create \"Lifecycle Contact 2\" contact2",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app1: transaction create contact1 owed 2000 \"T3\" t3",
        "app1: transaction create contact2 lent 800 \"T4\" t4",
        "app1: transaction create contact2 owed 1200 \"T5\" t5",
        "app1: transaction create contact1 lent 600 \"T6\" t6",
        "app1: transaction create contact1 owed 1500 \"T7\" t7",
        "app1: transaction create contact2 lent 900 \"T8\" t8",
        "app1: transaction create contact2 owed 1800 \"T9\" t9",
        "app1: transaction create contact1 lent 400 \"T10\" t10",
        "app1: wait 300",
        "app2: contact update contact1 name \"Updated Lifecycle Contact\"",
        "app2: transaction update t1 amount 2000",
        "app2: transaction update t3 description \"Updated T3\"",
        "app2: transaction update t5 amount 1300",
        "app3: transaction delete t6",
        "app3: transaction delete t7",
        "app3: contact delete contact1",
        "app3: transaction delete t1",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events aggregate_type contact event_type CREATED count 2",
        "events aggregate_type contact event_type UPDATED count 1",
        "events aggregate_type contact event_type DELETED count 1",
        "events aggregate_type transaction event_type CREATED count >= 10",
        "events aggregate_type transaction event_type UPDATED count > 2",
        "events aggregate_type transaction event_type DELETED or UNDO count >= 1",
    ]).expect("assert_commands");
}
