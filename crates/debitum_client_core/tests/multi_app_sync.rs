//! Multi-app basic sync: one app creates then all sync; concurrent creates; update/delete propagation.
//!
//! Uses three apps (same user). After execute_commands: sleep 300ms then one sync. See docs/INTEGRATION_TEST_COMMANDS.md.

use crate::common::test_helpers::{setup_three_apps, test_server_url};

/// Single app creates contact and transactions; after sync that app sees final state.
#[test]
#[ignore]
fn multi_app_single_app_creates_then_sync() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Test Contact 1\" contact1",
        "app1: transaction create contact1 owed 1000 \"Transaction 1\" t1",
        "app1: transaction create contact1 lent 500 \"Transaction 2\" t2",
        "app1: transaction create contact1 owed 2000 \"Transaction 3\" t3",
        "app1: transaction create contact1 lent 800 \"Transaction 4\" t4",
        "app1: transaction create contact1 owed 1500 \"Transaction 5\" t5",
        "app1: transaction create contact1 lent 300 \"Transaction 6\" t6",
        "app1: transaction create contact1 owed 1200 \"Transaction 7\" t7",
        "app1: transaction update t1 amount 1100",
        "app1: transaction update t3 description \"Updated Transaction 3\"",
        "app1: transaction delete t5",
        "app1: contact update contact1 name \"Updated Contact 1\"",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events count >= 12",
        "events event_type UPDATED count > 0",
        "contacts count 1",
        "contact 0 name \"Updated Contact 1\"",
        "transactions count > 5",
    ]).expect("assert_commands");
}

/// All three apps create contacts and transactions; after sync all see the same set.
#[test]
#[ignore]
fn multi_app_concurrent_creates_then_sync() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Contact from App1\" contact1",
        "app2: contact create \"Contact from App2\" contact2",
        "app3: contact create \"Contact from App3\" contact3",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app2: transaction create contact2 lent 800 \"T3\" t3",
        "app2: transaction create contact2 owed 1200 \"T4\" t4",
        "app3: transaction create contact3 owed 2000 \"T5\" t5",
        "app3: transaction create contact3 lent 600 \"T6\" t6",
        "app1: transaction create contact1 owed 1500 \"T7\" t7",
        "app2: transaction create contact2 lent 900 \"T8\" t8",
        "app3: transaction create contact3 owed 1800 \"T9\" t9",
        "app1: transaction update t1 amount 1100",
        "app2: transaction update t3 description \"Updated T3\"",
        "app3: transaction delete t5",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events count >= 12",
        "contacts count 3",
        "transactions count > 5",
    ]).expect("assert_commands");
}

/// Updates from different apps propagate; final state has many UPDATED events.
#[test]
#[ignore]
fn multi_app_update_propagation() {
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
        "app1: wait 300",
        "app1: contact update contact1 name \"Updated by App1\"",
        "app2: contact update contact1 name \"Updated by App2\"",
        "app1: transaction update t1 amount 2000",
        "app2: transaction update t1 amount 3000",
        "app1: transaction update t3 amount 2200",
        "app2: transaction update t5 description \"Updated T5\"",
        "app3: transaction update t7 amount 1300",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events count >= 18",
        "events event_type UPDATED count >= 7",
    ]).expect("assert_commands");
}

/// Deletes from different apps propagate; contact is removed from final state.
#[test]
#[ignore]
fn multi_app_delete_propagation() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Contact to Delete\" contact1",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app1: transaction create contact1 owed 2000 \"T3\" t3",
        "app1: transaction create contact1 lent 800 \"T4\" t4",
        "app1: transaction create contact1 owed 1500 \"T5\" t5",
        "app1: wait 300",
        "app2: transaction create contact1 lent 600 \"T6\" t6",
        "app2: transaction create contact1 owed 1200 \"T7\" t7",
        "app3: transaction create contact1 lent 900 \"T8\" t8",
        "app3: transaction create contact1 owed 1800 \"T9\" t9",
        "app3: transaction create contact1 lent 400 \"T10\" t10",
        "app1: transaction create contact1 owed 1100 \"T11\" t11",
        "app2: transaction create contact1 lent 700 \"T12\" t12",
        "app1: wait 300",
        "app2: transaction delete t1",
        "app3: transaction delete t5",
        "app3: contact delete contact1",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    app1_ref.assert_commands(&[
        "events count >= 14",
        "contact name \"Contact to Delete\" removed",
    ]).expect("assert_commands");
}
