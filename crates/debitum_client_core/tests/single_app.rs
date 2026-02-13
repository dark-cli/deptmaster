//! Single-app and two-app integration tests: signup/login, create contact, sync, offline/online, many events.
//!
//! Style: command/assert only; after run_commands use wait 300ms then sync once. See docs/INTEGRATION_TEST_COMMANDS.md.

use crate::common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use crate::common::event_generator::EventGenerator;
use crate::common::test_helpers::test_server_url;
use std::collections::HashMap;

/// Single app: signup, create contact, wait, assert contacts and events.
#[test]
#[ignore]
fn single_app_signup_create_contact_and_sync() {
    let server_url = test_server_url();
    let app1 = AppInstance::new("app1", &server_url);
    app1.initialize().expect("initialize");
    app1.signup().expect("signup");

    app1
        .run_commands(&["contact create \"Alice\" alice", "wait 300"])
        .expect("run_commands");

    app1
        .assert_commands(&[
            "contacts count 1",
            "contact 0 name \"Alice\"",
            "events count >= 1",
        ])
        .expect("assert_commands");
}

/// Single app with shared credentials: login then create contact and assert.
#[test]
#[ignore]
fn single_app_login_and_sync() {
    let server_url = test_server_url();
    let (username, password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create_unique_test_user_and_wallet");

    let app1 = AppInstance::with_credentials(
        "app1",
        &server_url,
        username,
        password,
        Some(wallet_id),
    );
    app1.initialize().expect("initialize");
    app1.login().expect("login");

    app1
        .run_commands(&["contact create \"Bob\" bob", "wait 300"])
        .expect("run_commands");

    app1.assert_commands(&["contact name \"Bob\""]).expect("assert_commands");
}

/// Two apps (same user): app1 creates contact and syncs; app2 syncs and sees the contact.
#[test]
#[ignore]
fn two_apps_sync_via_server() {
    let server_url = test_server_url();
    let (username, password, wallet_id) =
        create_unique_test_user_and_wallet(&server_url).expect("create_unique_test_user_and_wallet");

    let app1 = AppInstance::with_credentials(
        "app1",
        &server_url,
        username.clone(),
        password.clone(),
        Some(wallet_id.clone()),
    );
    let app2 = AppInstance::with_credentials("app2", &server_url, username, password, Some(wallet_id));

    app1.initialize().expect("initialize");
    app2.initialize().expect("initialize");
    app1.login().expect("login");
    app2.login().expect("login");

    let mut apps = HashMap::new();
    apps.insert("app1".to_string(), app1);
    apps.insert("app2".to_string(), app2);
    let generator = EventGenerator::new(apps);

    generator
        .execute_commands(&[
            "app1: contact create \"Carol\" carol",
            "app1: wait 300",
        ])
        .expect("execute_commands");

    let app1_ref = generator.apps.get("app1").unwrap();
    let app2_ref = generator.apps.get("app2").unwrap();
    app1_ref.sync().expect("app1 sync (push)");
    std::thread::sleep(std::time::Duration::from_millis(300));
    app2_ref.sync().expect("app2 sync (simulates WS notification)");

    app2_ref.assert_commands(&["contact name \"Carol\""]).expect("assert_commands");
}

/// Offline create then go online and sync: sync fails while offline, succeeds after go_online.
#[test]
#[ignore]
fn single_app_offline_create_then_online_sync() {
    let server_url = test_server_url();
    let app = AppInstance::new("app1", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");

    app.run_commands(&["contact create \"Online First\" contact1", "wait 300"]).expect("run_commands");
    app.sync().expect("sync while online");

    app.go_offline().expect("go_offline");
    app.run_commands(&["contact create \"Created Offline\" contact2"]).expect("create contact offline (local only)");
    let sync_offline = app.sync();
    let err = sync_offline.unwrap_err();
    assert!(err.contains("Network offline"), "sync while offline should fail with Network offline; got {}", err);

    app.go_online().expect("go_online");
    app.sync().expect("sync (as app does when WS connects)");
    std::thread::sleep(std::time::Duration::from_millis(300));

    app.assert_commands(&[
        "contact name \"Online First\"",
        "contact name \"Created Offline\"",
    ]).expect("assert_commands");
}

/// Offline update then online sync (ported from Flutter offline_online_scenarios).
#[test]
#[ignore]
fn single_app_offline_update_then_online_sync() {
    let server_url = test_server_url();
    let app = AppInstance::new("app1", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");

    app.run_commands(&[
        "contact create \"Original Name\" contact1",
        "transaction create contact1 owed 1000 \"T1\" t1",
        "transaction create contact1 lent 500 \"T2\" t2",
        "transaction create contact1 owed 2000 \"T3\" t3",
        "transaction create contact1 lent 800 \"T4\" t4",
        "transaction create contact1 owed 1500 \"T5\" t5",
        "wait 300",
    ]).expect("run_commands (setup)");
    app.sync().expect("sync while online");

    app.go_offline().expect("go_offline");
    app.run_commands(&[
        "contact update contact1 name \"Updated Offline\"",
        "transaction update t1 amount 2000",
        "transaction update t2 description \"Updated T2\"",
        "transaction update t3 amount 2200",
        "transaction update t4 description \"Updated T4\"",
        "transaction update t5 amount 1600",
        "transaction create contact1 lent 600 \"T6\" t6",
        "transaction create contact1 owed 1200 \"T7\" t7",
        "transaction update t6 amount 700",
        "transaction delete t5",
    ]).expect("run_commands (offline updates)");

    app.go_online().expect("go_online");
    app.sync().expect("sync after coming online");
    std::thread::sleep(std::time::Duration::from_millis(300));

    app.assert_commands(&[
        "contacts count 1",
        "contact name \"Updated Offline\"",
        "transactions count > 5",
        "events event_type UPDATED count >= 6",
    ]).expect("assert_commands");
}

/// Single app: one contact, many transactions, updates, delete; assert final state and event counts.
#[test]
#[ignore]
fn single_app_many_events_then_assert() {
    let server_url = test_server_url();
    let app1 = AppInstance::new("app1", &server_url);
    app1.initialize().expect("initialize");
    app1.signup().expect("signup");

    let commands = [
        "contact create \"Test Contact 1\" contact1",
        "transaction create contact1 owed 1000 \"Transaction 1\" t1",
        "transaction create contact1 lent 500 \"Transaction 2\" t2",
        "transaction create contact1 owed 2000 \"Transaction 3\" t3",
        "transaction create contact1 lent 800 \"Transaction 4\" t4",
        "transaction create contact1 owed 1500 \"Transaction 5\" t5",
        "transaction create contact1 lent 300 \"Transaction 6\" t6",
        "transaction create contact1 owed 1200 \"Transaction 7\" t7",
        "transaction create contact1 lent 600 \"Transaction 8\" t8",
        "transaction update t1 amount 1100",
        "transaction update t3 description \"Updated Transaction 3\"",
        "transaction delete t5",
        "contact update contact1 name \"Updated Contact 1\"",
        "wait 300",
    ];
    app1.run_commands(&commands).expect("run_commands");

    app1.assert_commands(&[
        "contacts count 1",
        "contact 0 name \"Updated Contact 1\"",
        "events count >= 12",
        "events event_type CREATED count >= 9",
        "events event_type UPDATED count >= 3",
    ]).expect("assert_commands");
}

/// Multiple offline creates then online sync (ported from Flutter offline_online_scenarios).
#[test]
#[ignore]
fn single_app_multiple_offline_creates_then_online_sync() {
    let server_url = test_server_url();
    let app = AppInstance::new("app1", &server_url);
    app.initialize().expect("initialize");
    app.signup().expect("signup");

    app.go_offline().expect("go_offline");
    let commands = [
        "contact create \"Offline Contact 1\" contact1",
        "contact create \"Offline Contact 2\" contact2",
        "contact create \"Offline Contact 3\" contact3",
        "transaction create contact1 owed 1000 \"T1\" t1",
        "transaction create contact1 lent 500 \"T2\" t2",
        "transaction create contact1 owed 2000 \"T3\" t3",
        "transaction create contact2 lent 800 \"T4\" t4",
        "transaction create contact2 owed 1200 \"T5\" t5",
        "transaction create contact2 lent 600 \"T6\" t6",
        "transaction create contact3 owed 1500 \"T7\" t7",
        "transaction create contact3 lent 900 \"T8\" t8",
        "transaction create contact3 owed 1800 \"T9\" t9",
        "transaction update t1 amount 1100",
        "transaction delete t5",
    ];
    app.run_commands(&commands).expect("run_commands (offline)");

    app.go_online().expect("go_online");
    app.sync().expect("sync after coming online");
    std::thread::sleep(std::time::Duration::from_millis(300));

    app.assert_commands(&[
        "contacts count 3",
        "contact name \"Offline Contact 1\"",
        "contact name \"Offline Contact 2\"",
        "contact name \"Offline Contact 3\"",
        "transactions count >= 8",
    ]).expect("assert_commands");
}

/// Single app: multiple contacts and transactions, updates and deletes; assert final contacts and event count.
#[test]
#[ignore]
fn single_app_many_contacts_and_transactions() {
    let server_url = test_server_url();
    let app1 = AppInstance::new("app1", &server_url);
    app1.initialize().expect("initialize");
    app1.signup().expect("signup");

    let commands = [
        "contact create \"Alice\" alice",
        "contact create \"Bob\" bob",
        "contact create \"Carol\" carol",
        "transaction create alice owed 1000 \"T1\" t1",
        "transaction create alice lent 500 \"T2\" t2",
        "transaction create bob lent 800 \"T3\" t3",
        "transaction create bob owed 1200 \"T4\" t4",
        "transaction create carol owed 2000 \"T5\" t5",
        "transaction create carol lent 600 \"T6\" t6",
        "transaction create alice owed 1500 \"T7\" t7",
        "transaction create bob lent 900 \"T8\" t8",
        "transaction create carol owed 1800 \"T9\" t9",
        "transaction update t1 amount 1100",
        "transaction update t3 description \"Updated T3\"",
        "transaction delete t5",
        "contact update alice name \"Alice Updated\"",
        "wait 300",
    ];
    app1.run_commands(&commands).expect("run_commands");

    app1.assert_commands(&[
        "contacts count 3",
        "contact name \"Alice Updated\"",
        "contact name \"Bob\"",
        "contact name \"Carol\"",
        "events count >= 15",
    ]).expect("assert_commands");
}
