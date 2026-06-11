//! Resync scenarios: full resync after "disconnect", incremental resync.
//!
//! Ported from Flutter resync_scenarios.

use crate::common::test_helpers::{setup_three_apps, test_server_url};

/// Full resync: app2 and app3 create many events and sync; app1 then syncs and receives all.
#[test]
#[ignore]
fn resync_full_after_app1_missed_events() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let commands = [
        "app2: contact create \"Contact from App2 #0\" contact1",
        "app2: contact create \"Contact from App2 #1\" contact2",
        "app2: contact create \"Contact from App2 #2\" contact3",
        "app3: contact create \"Contact from App3 #0\" contact4",
        "app3: contact create \"Contact from App3 #1\" contact5",
        "app2: transaction create contact1 owed 1000 \"T1\" t1",
        "app2: transaction create contact1 lent 500 \"T2\" t2",
        "app2: transaction create contact2 owed 2000 \"T3\" t3",
        "app2: transaction create contact2 lent 800 \"T4\" t4",
        "app2: transaction create contact3 owed 1500 \"T5\" t5",
        "app3: transaction create contact4 lent 600 \"T6\" t6",
        "app3: transaction create contact4 owed 1200 \"T7\" t7",
        "app3: transaction create contact5 lent 900 \"T8\" t8",
        "app3: transaction create contact5 owed 1800 \"T9\" t9",
        "app2: transaction create contact1 owed 1100 \"T10\" t10",
        "app2: transaction create contact2 lent 700 \"T11\" t11",
        "app3: transaction create contact4 owed 1300 \"T12\" t12",
        "app3: transaction create contact5 lent 400 \"T13\" t13",
        "app2: transaction update t1 amount 1100",
        "app2: transaction update t3 description \"Updated T3\"",
        "app3: transaction update t6 amount 700",
        "app3: transaction delete t8",
        "app2: transaction create contact3 lent 500 \"T14\" t14",
        "app3: transaction create contact4 owed 1400 \"T15\" t15",
        "app2: transaction delete t5",
    ];
    generator.execute_commands(&commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    generator.apps.get("app2").unwrap().sync().expect("app2 sync");
    generator.apps.get("app3").unwrap().sync().expect("app3 sync");
    std::thread::sleep(std::time::Duration::from_millis(300));

    generator.apps.get("app1").unwrap().sync().expect("app1 sync (full resync)");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.assert_commands(&[
        "contacts count 5",
        "transactions count >= 13",
        "events count >= 20",
    ]).expect("assert_commands");
}

/// Incremental resync: app1 creates and syncs; app2 creates more and syncs; app1 syncs again and has all.
#[test]
#[ignore]
fn resync_incremental_app1_catches_new_events() {
    let server_url = test_server_url();
    let generator = setup_three_apps(&server_url);
    let initial = [
        "app1: contact create \"Initial Contact\" contact1",
        "app1: transaction create contact1 owed 1000 \"T1\" t1",
        "app1: transaction create contact1 lent 500 \"T2\" t2",
        "app1: transaction create contact1 owed 2000 \"T3\" t3",
    ];
    generator.execute_commands(&initial).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    generator.apps.get("app1").unwrap().sync().expect("app1 sync (initial)");

    let new_commands = [
        "app2: contact create \"New Contact #0\" contact2",
        "app2: contact create \"New Contact #1\" contact3",
        "app2: contact create \"New Contact #2\" contact4",
        "app2: transaction create contact2 owed 1000 \"T4\" t4",
        "app2: transaction create contact2 lent 500 \"T5\" t5",
        "app2: transaction create contact3 owed 2000 \"T6\" t6",
        "app2: transaction create contact3 lent 800 \"T7\" t7",
        "app2: transaction create contact4 owed 1500 \"T8\" t8",
        "app2: transaction create contact4 lent 600 \"T9\" t9",
        "app2: transaction create contact2 owed 1200 \"T10\" t10",
        "app2: transaction create contact3 lent 900 \"T11\" t11",
        "app2: transaction create contact4 owed 1800 \"T12\" t12",
        "app2: transaction update t4 amount 1100",
        "app2: transaction update t6 description \"Updated T6\"",
        "app2: transaction delete t8",
    ];
    generator.execute_commands(&new_commands).expect("execute_commands");
    std::thread::sleep(std::time::Duration::from_millis(300));
    generator.apps.get("app2").unwrap().sync().expect("app2 sync");

    generator.apps.get("app1").unwrap().sync().expect("app1 sync (incremental)");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let app1_ref = generator.apps.get("app1").unwrap();
    app1_ref.assert_commands(&[
        "contacts count 4",
        "transactions count >= 11",
        "events count >= 18",
    ]).expect("assert_commands");
}
