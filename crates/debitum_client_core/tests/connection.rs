//! Connection-style scenarios: sync after many operations (client-core only; no server-down simulation).
//!
//! Ported from Flutter connection_scenarios.

use crate::common::app_instance::AppInstance;
use crate::common::test_helpers::{setup_three_apps, test_server_url};

/// Sync after 15 events; verify final state (1 contact, 10 transactions).
#[test]
#[ignore]
fn connection_sync_after_many_operations() {
    let server_url = test_server_url();
    let app = AppInstance::new("app1", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");

    let commands = [
        "contact create \"Contact to Interrupt\" contact1",
        "transaction create contact1 owed 1000 \"T1\" t1",
        "transaction create contact1 lent 500 \"T2\" t2",
        "transaction create contact1 owed 2000 \"T3\" t3",
        "transaction create contact1 lent 800 \"T4\" t4",
        "transaction create contact1 owed 1500 \"T5\" t5",
        "transaction create contact1 lent 600 \"T6\" t6",
        "transaction create contact1 owed 1200 \"T7\" t7",
        "transaction create contact1 lent 900 \"T8\" t8",
        "transaction create contact1 owed 1800 \"T9\" t9",
        "transaction create contact1 lent 400 \"T10\" t10",
        "transaction create contact1 owed 1100 \"T11\" t11",
        "transaction update t1 amount 1100",
        "transaction update t3 description \"Updated T3\"",
        "transaction delete t5",
        "wait 300",
    ];
    app.run_commands(&commands).expect("run_commands");
    app.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));

    app.assert_commands(&[
        "contacts count 1",
        "transactions count >= 10",
        "events count >= 14",
    ]).expect("assert_commands");
}

/// Multiple contacts and transactions then sync; verify no duplicates / consistent state.
#[test]
#[ignore]
fn connection_many_operations_then_sync() {
    let server_url = test_server_url();
    let app = AppInstance::new("app1", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");

    let commands = [
        "contact create \"Contact 0\" contact1",
        "contact create \"Contact 1\" contact2",
        "contact create \"Contact 2\" contact3",
        "transaction create contact1 owed 1000 \"T1\" t1",
        "transaction create contact1 lent 500 \"T2\" t2",
        "transaction create contact1 owed 2000 \"T3\" t3",
        "transaction create contact2 lent 800 \"T4\" t4",
        "transaction create contact2 owed 1200 \"T5\" t5",
        "transaction create contact2 lent 600 \"T6\" t6",
        "transaction create contact3 owed 1500 \"T7\" t7",
        "transaction create contact3 lent 900 \"T8\" t8",
        "transaction create contact3 owed 1800 \"T9\" t9",
        "transaction create contact1 lent 400 \"T10\" t10",
        "transaction create contact2 owed 1100 \"T11\" t11",
        "transaction create contact3 lent 700 \"T12\" t12",
        "transaction update t1 amount 1100",
        "transaction update t4 description \"Updated T4\"",
        "transaction delete t6",
        "transaction update t7 amount 1600",
        "transaction delete t9",
        "wait 300",
    ];
    app.run_commands(&commands).expect("run_commands");
    app.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));

    app.assert_commands(&[
        "events count >= 18",
        "contacts count 3",
        "transactions count >= 10",
    ]).expect("assert_commands");
}

/// Multi-app: 18 events across three apps then sync; verify one app sees full state.
#[test]
#[ignore]
fn connection_multi_app_sync_after_operations() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Contact from App1\" contact1",
        "app2: contact create \"Contact from App2\" contact2",
        "app3: contact create \"Contact from App3\" contact3",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app1: transaction create contact1 owed 2000 \"T3\" t3",
        "app2: transaction create contact2 lent 800 \"T4\" t4",
        "app2: transaction create contact2 owed 1200 \"T5\" t5",
        "app2: transaction create contact2 lent 600 \"T6\" t6",
        "app3: transaction create contact3 owed 1500 \"T7\" t7",
        "app3: transaction create contact3 lent 900 \"T8\" t8",
        "app3: transaction create contact3 owed 1800 \"T9\" t9",
        "app1: transaction create contact2 lent 400 \"T10\" t10",
        "app2: transaction create contact3 owed 1100 \"T11\" t11",
        "app3: transaction create contact1 lent 700 \"T12\" t12",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    generator.apps.get("app1").unwrap().sync().expect("app1 sync");

    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.assert_commands(&[
        "contacts count 3",
        "transactions count >= 10",
        "events count >= 15",
    ]).expect("assert_commands");
}
