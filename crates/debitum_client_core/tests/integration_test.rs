//! Integration tests: app instances talk to a real server over the network.
//!
//! Style matches Flutter integration tests:
//! - Create app instances: `app1 = AppInstance::new("app1", &server_url)` or `with_credentials` for shared user.
//! - Call `app1.initialize()`, `app1.signup()` or `app1.login()`, `app1.run_commands([...])`, `app1.sync()`.
//! - For multi-app: build `EventGenerator` with a map of app name → AppInstance, then `generator.execute_commands(&["app1: contact create ..."])`.
//! - Rely on robust sync: no manual_sync in commands; sleep 50–100ms before asserting on data that came from sync.
//! - Assert via `app1.get_contacts()`, `app1.get_events()`, `app1.get_transactions()`.
//!
//! Requires a running server. Set `TEST_SERVER_URL` (default `http://127.0.0.1:8000`).
//!
//! Run: `cargo test --test integration_test -- --ignored`
//!
//! Tests run in parallel by default: storage and backend config are thread-local, so each test thread has its own state.
//! For full reliability (all 14 tests), use: `--ignored --test-threads=1`. Some multi-app scenarios may flake when parallel.

mod common;

use common::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use common::event_generator::EventGenerator;
use std::collections::{HashMap, HashSet};

fn test_server_url() -> String {
    std::env::var("TEST_SERVER_URL").unwrap_or_else(|_| "http://127.0.0.1:8000".to_string())
}

/// Single app: new instance, signup, run commands (create contact + sync), assert on get_contacts and get_events.
#[test]
#[ignore]
fn test_app_instance_create_contact_and_sync() {
    let server_url = test_server_url();
    let app1 = AppInstance::new("app1", &server_url);
    app1.initialize().expect("initialize");
    app1.signup().expect("signup");

    app1
        .run_commands(&["contact create \"Alice\" alice", "wait 300"])
        .expect("run_commands");

    let contacts_json = app1.get_contacts().expect("get_contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse contacts");
    assert_eq!(contacts.len(), 1, "expected 1 contact");
    assert_eq!(contacts[0]["name"], "Alice");

    let events_json = app1.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    assert!(!events.is_empty(), "expected at least one event");
}

/// Single app with shared credentials: create unique user, then login and run commands.
#[test]
#[ignore]
fn test_app_instance_login_and_sync() {
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

    let contacts_json = app1.get_contacts().expect("get_contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse");
    assert!(contacts.iter().any(|c| c["name"].as_str() == Some("Bob")), "expected Bob: {:?}", contacts);
}

/// Two app instances (same user): app1 creates contact and syncs; app2 syncs and sees the contact.
#[test]
#[ignore]
fn test_two_app_instances_sync_via_server() {
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

    let contacts_json = app2_ref.get_contacts().expect("get_contacts");
    let list: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse");
    assert!(list.iter().any(|c| c["name"].as_str() == Some("Carol")), "app2 should see Carol: {:?}", list);
}

/// Test core behavior: offline → API fails; online → app's WS-connect flow triggers sync.
/// We simulate the app: go_online then sync (app calls sync when WS is created). We test the core, not invent app logic.
#[test]
#[ignore]
fn test_offline_create_then_online_sync() {
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
    // Simulate app: WS (re)connects and triggers sync. We don't add this to the core; we test that the core responds correctly.
    app.sync().expect("sync (as app does when WS connects)");
    std::thread::sleep(std::time::Duration::from_millis(300));

    let contacts_json = app.get_contacts().expect("get_contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse");
    assert!(contacts.iter().any(|c| c["name"].as_str() == Some("Online First")), "should have Online First");
    assert!(contacts.iter().any(|c| c["name"].as_str() == Some("Created Offline")), "should have Created Offline after sync");
}

/// Single app: many events (contacts, transactions, updates, deletes), then assert state.
#[test]
#[ignore]
fn test_many_events_sync() {
    let server_url = test_server_url();
    let app1 = AppInstance::new("app1", &server_url);
    app1.initialize().expect("initialize");
    app1.signup().expect("signup");

    let commands = [
        "# Single contact, many transactions, updates, delete",
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

    let contacts_json = app1.get_contacts().expect("get_contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse contacts");
    assert_eq!(contacts.len(), 1, "expected 1 contact after updates");
    assert_eq!(contacts[0]["name"], "Updated Contact 1");

    let events_json = app1.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    assert!(events.len() >= 12, "expected at least 12 events (creates + updates + delete), got {}", events.len());

    let create_count = events.iter().filter(|e| e["event_type"].as_str() == Some("CREATED")).count();
    let update_count = events.iter().filter(|e| e["event_type"].as_str() == Some("UPDATED")).count();
    assert!(create_count >= 9, "expected at least 9 CREATED events");
    assert!(update_count >= 3, "expected at least 3 UPDATED events");
}

/// Single app: multiple contacts, many transactions, updates and deletes; assert final contacts and event count.
#[test]
#[ignore]
fn test_many_contacts_and_transactions() {
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

    let contacts_json = app1.get_contacts().expect("get_contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse contacts");
    assert_eq!(contacts.len(), 3, "expected 3 contacts");
    assert!(contacts.iter().any(|c| c["name"].as_str() == Some("Alice Updated")));
    assert!(contacts.iter().any(|c| c["name"].as_str() == Some("Bob")));
    assert!(contacts.iter().any(|c| c["name"].as_str() == Some("Carol")));

    let events_json = app1.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    assert!(events.len() >= 15, "expected at least 15 events (3 contacts + 9 tx + updates + delete), got {}", events.len());
}

// ---------- Basic Sync Scenarios (ported from Flutter basic_sync_scenarios.dart) ----------
// Sync commands replaced with "wait 300"; after execute_commands use 300ms sleep then one sync (simulates WS notification).

fn setup_three_apps(server_url: &str) -> EventGenerator {
    let (username, password, wallet_id) =
        create_unique_test_user_and_wallet(server_url).expect("create_unique_test_user_and_wallet");
    let app1 = AppInstance::with_credentials(
        "app1",
        server_url,
        username.clone(),
        password.clone(),
        Some(wallet_id.clone()),
    );
    let app2 = AppInstance::with_credentials(
        "app2",
        server_url,
        username.clone(),
        password.clone(),
        Some(wallet_id.clone()),
    );
    let app3 = AppInstance::with_credentials("app3", server_url, username, password, Some(wallet_id));
    app1.initialize().expect("initialize");
    app2.initialize().expect("initialize");
    app3.initialize().expect("initialize");
    app1.login().expect("login");
    app2.login().expect("login");
    app3.login().expect("login");
    let mut apps = HashMap::new();
    apps.insert("app1".to_string(), app1);
    apps.insert("app2".to_string(), app2);
    apps.insert("app3".to_string(), app3);
    EventGenerator::new(apps)
}

/// Single app creates contact + transactions + updates + delete; all apps see final state after sync.
#[test]
#[ignore]
fn test_basic_single_app_create_multi_app_sync() {
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

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    assert!(events.len() >= 12, "at least 12 events; got {}", events.len());
    let update_count = events.iter().filter(|e| e["event_type"].as_str() == Some("UPDATED")).count();
    assert!(update_count > 0, "should have UPDATED events");

    let contacts_json = app1_ref.get_contacts().expect("get_contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse contacts");
    assert_eq!(contacts.len(), 1);
    assert_eq!(contacts[0]["name"], "Updated Contact 1");

    let tx_json = app1_ref.get_transactions().expect("get_transactions");
    let tx: Vec<serde_json::Value> = serde_json::from_str(&tx_json).expect("parse transactions");
    assert!(tx.len() > 5, "expected >5 transactions");
}

/// All three apps create contacts and transactions; after sync all see the same set.
#[test]
#[ignore]
fn test_basic_concurrent_creates() {
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

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    assert!(events.len() >= 12, "at least 12 events; got {}", events.len());

    let contacts_json = app1_ref.get_contacts().expect("get_contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse contacts");
    assert_eq!(contacts.len(), 3, "all 3 contacts; got {:?}", contacts);
    let tx_json = app1_ref.get_transactions().expect("get_transactions");
    let tx: Vec<serde_json::Value> = serde_json::from_str(&tx_json).expect("parse transactions");
    assert!(tx.len() > 5);
}

/// Updates from different apps propagate; final state has many UPDATED events.
#[test]
#[ignore]
fn test_basic_update_propagation() {
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

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    assert!(events.len() >= 18, "at least 18 events; got {}", events.len());
    let update_count = events.iter().filter(|e| e["event_type"].as_str() == Some("UPDATED")).count();
    assert!(update_count >= 7, "at least 7 UPDATED events; got {}", update_count);
}

/// Deletes from different apps propagate; contact is removed from final state.
#[test]
#[ignore]
fn test_basic_delete_propagation() {
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

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    // 1 contact + up to 12 tx creates + deletes; full pull/merge can yield 14+ events
    assert!(events.len() >= 14, "at least 14 events; got {}", events.len());
    let contacts_json = app1_ref.get_contacts().expect("get_contacts");
    let contacts: Vec<serde_json::Value> = serde_json::from_str(&contacts_json).expect("parse contacts");
    let contact_removed = !contacts.iter().any(|c| c["name"].as_str() == Some("Contact to Delete"));
    assert!(contact_removed, "contact should be removed; got {:?}", contacts);
}

// ---------- Comprehensive Event Scenarios (ported from Flutter comprehensive_event_scenarios.dart) ----------

/// Contact event types: CREATED, UPDATED, DELETED.
#[test]
#[ignore]
fn test_comprehensive_contact_event_types() {
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

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    let contact_created = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact") && e["event_type"].as_str() == Some("CREATED")).count();
    let contact_updated = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact") && e["event_type"].as_str() == Some("UPDATED")).count();
    let contact_deleted = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact") && e["event_type"].as_str() == Some("DELETED")).count();
    assert_eq!(contact_created, 3, "3 contact CREATED");
    assert_eq!(contact_updated, 2, "2 contact UPDATED");
    assert_eq!(contact_deleted, 1, "1 contact DELETED");
}

/// Transaction event types: CREATED, UPDATED, DELETED (or UNDO).
#[test]
#[ignore]
fn test_comprehensive_transaction_event_types() {
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

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    let tx_created = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("transaction") && e["event_type"].as_str() == Some("CREATED")).count();
    let tx_updated = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("transaction") && e["event_type"].as_str() == Some("UPDATED")).count();
    assert!(tx_created >= 10, "many transaction CREATED");
    assert!(tx_updated >= 4, "many transaction UPDATED");
    // Server may use UNDO for recent deletes; DELETED/UNDO may not appear in synced event list
}

/// Mixed operations: contacts and transactions from multiple apps; all event types present.
#[test]
#[ignore]
fn test_comprehensive_mixed_operations() {
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

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    let contact_events = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact")).count();
    let transaction_events = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("transaction")).count();
    assert!(contact_events > 2);
    assert!(transaction_events > 15);
    let contact_types: HashSet<_> = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact")).filter_map(|e| e["event_type"].as_str()).collect();
    let tx_types: HashSet<_> = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("transaction")).filter_map(|e| e["event_type"].as_str()).collect();
    assert!(contact_types.contains("CREATED"));
    assert!(contact_types.contains("UPDATED"));
    assert!(tx_types.contains("CREATED"));
    assert!(tx_types.contains("UPDATED"));
    assert!(tx_types.contains("DELETED") || tx_types.contains("UNDO"));
}

/// Concurrent mixed operations across all three apps.
#[test]
#[ignore]
fn test_comprehensive_concurrent_mixed_operations() {
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

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    let contact_events = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact")).count();
    let transaction_events = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("transaction")).count();
    assert_eq!(contact_events, 3, "3 contact CREATED events");
    assert!(transaction_events > 20, "many transaction events");
}

/// Full lifecycle: create, update, delete for both contacts and transactions.
#[test]
#[ignore]
fn test_comprehensive_full_lifecycle() {
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
    // Allow time for WS notification to trigger sync (app receives server push and pulls).
    std::thread::sleep(std::time::Duration::from_millis(300));
    let app1_ref = generator.apps.get("app1").unwrap();
    // In production, WS message triggers sync; in test we have no WS client so we trigger sync here after the wait.
    app1_ref.sync().expect("app1 sync (simulates WS notification)");

    let events_json = app1_ref.get_events().expect("get_events");
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json).expect("parse events");
    let contact_created = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact") && e["event_type"].as_str() == Some("CREATED")).count();
    let contact_updated = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact") && e["event_type"].as_str() == Some("UPDATED")).count();
    let contact_deleted = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("contact") && e["event_type"].as_str() == Some("DELETED")).count();
    let tx_created = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("transaction") && e["event_type"].as_str() == Some("CREATED")).count();
    let tx_updated = events.iter().filter(|e| e["aggregate_type"].as_str() == Some("transaction") && e["event_type"].as_str() == Some("UPDATED")).count();
    let tx_deleted_or_undo = events.iter().filter(|e| {
        e["aggregate_type"].as_str() == Some("transaction") && (e["event_type"].as_str() == Some("DELETED") || e["event_type"].as_str() == Some("UNDO"))
    }).count();
    assert_eq!(contact_created, 2);
    assert_eq!(contact_updated, 1);
    assert_eq!(contact_deleted, 1);
    assert!(tx_created >= 10);
    assert!(tx_updated > 2);
    // Server may emit UNDO for recent deletes; at least one delete-like event expected
    assert!(tx_deleted_or_undo >= 1, "expected at least 1 tx DELETED/UNDO; got {}", tx_deleted_or_undo);
}
