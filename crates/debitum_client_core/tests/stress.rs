//! Stress scenarios: high volume concurrent, rapid create-update-delete, mixed operations.
//!
//! Ported from Flutter stress_scenarios.

use crate::common::app_instance::AppInstance;
use crate::common::test_helpers::{setup_three_apps, test_server_url};

/// High volume concurrent operations across three apps (~28 events).
#[test]
#[ignore]
fn stress_high_volume_concurrent_operations() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Contact App1-1\" contact1",
        "app2: contact create \"Contact App2-1\" contact2",
        "app3: contact create \"Contact App3-1\" contact3",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app1: transaction create contact1 owed 2000 \"T3\" t3",
        "app2: transaction create contact2 lent 800 \"T4\" t4",
        "app2: transaction create contact2 owed 1200 \"T5\" t5",
        "app2: transaction create contact2 lent 600 \"T6\" t6",
        "app3: transaction create contact3 owed 1500 \"T7\" t7",
        "app3: transaction create contact3 lent 900 \"T8\" t8",
        "app3: transaction create contact3 owed 1800 \"T9\" t9",
        "app1: transaction create contact1 lent 400 \"T10\" t10",
        "app1: transaction create contact2 owed 1100 \"T11\" t11",
        "app3: transaction create contact3 lent 700 \"T12\" t12",
        "app1: transaction create contact1 owed 1300 \"T13\" t13",
        "app2: transaction create contact2 lent 500 \"T14\" t14",
        "app3: transaction create contact3 owed 1600 \"T15\" t15",
        "app1: transaction update t1 amount 1100",
        "app2: transaction update t4 description \"Updated T4\"",
        "app3: transaction update t7 amount 1600",
        "app1: transaction delete t3",
        "app2: transaction delete t6",
        "app3: transaction update t9 amount 1900",
        "app1: transaction create contact3 lent 200 \"T18\" t18",
        "app2: transaction create contact1 owed 1700 \"T19\" t19",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    generator.apps.get("app1").unwrap().sync().expect("app1 sync");

    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.assert_commands(&[
        "events count >= 25",
        "contacts count 3",
        "transactions count > 15",
    ]).expect("assert_commands");
}

/// Rapid create-update-delete then assert contact and transactions removed.
#[test]
#[ignore]
fn stress_rapid_create_update_delete() {
    let server_url = test_server_url();
    let app = AppInstance::new("app1", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");

    let commands = [
        "contact create \"Rapid Test Contact\" contact1",
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
        "contact update contact1 name \"Updated 1\"",
        "transaction update t1 amount 2000",
        "transaction update t2 description \"Updated T2\"",
        "transaction update t3 amount 2200",
        "contact update contact1 name \"Updated 2\"",
        "transaction update t4 amount 900",
        "transaction update t5 description \"Updated T5\"",
        "transaction delete t6",
        "transaction delete t7",
        "transaction delete t8",
        "transaction delete t9",
        "transaction delete t10",
        "contact delete contact1",
        "wait 300",
    ];
    app.run_commands(&commands).expect("run_commands");
    app.sync().expect("sync");
    std::thread::sleep(std::time::Duration::from_millis(300));

    app.assert_commands(&[
        "contacts count 0",
        "contact name \"Rapid Test Contact\" removed",
    ]).expect("assert_commands");
}

/// Mixed operations stress across three apps (create, update, delete from each).
#[test]
#[ignore]
fn stress_mixed_operations() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app1: contact create \"Initial Contact 0\" contact1",
        "app1: contact create \"Initial Contact 1\" contact2",
        "app1: contact create \"Initial Contact 2\" contact3",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact2 lent 500 \"T2\" t2",
        "app1: transaction create contact3 owed 2000 \"T3\" t3",
        "app1: contact create \"App1 Contact\" contact4",
        "app1: transaction create contact4 owed 1500 \"T4\" t4",
        "app1: contact update contact1 name \"Updated by App1\"",
        "app1: transaction update t1 amount 2000",
        "app1: contact delete contact3",
        "app1: transaction delete t3",
        "app2: contact create \"App2 Contact\" contact5",
        "app2: transaction create contact5 lent 800 \"T5\" t5",
        "app2: contact update contact2 name \"Updated by App2\"",
        "app2: transaction update t2 description \"Updated T2\"",
        "app3: contact create \"App3 Contact\" contact6",
        "app3: transaction create contact6 owed 1200 \"T6\" t6",
        "app3: contact delete contact1",
        "app3: transaction delete t1",
        "app2: transaction update t4 amount 1600",
        "app3: transaction delete t6",
        "app3: contact update contact4 name \"Updated by App3\"",
        "app3: transaction create contact2 lent 400 \"T9\" t9",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    generator.apps.get("app1").unwrap().sync().expect("app1 sync");

    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.assert_commands(&[
        "events count >= 20",
        "contacts count > 0",
        "transactions count > 0",
    ]).expect("assert_commands");
}
