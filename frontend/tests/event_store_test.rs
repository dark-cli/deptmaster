//! Event store tests: append, list, filter (no Dioxus/desktop required for logic).
//! Run with: cargo test -- --test-threads=1 (global event store is shared).

use debitum_frontend::event_store;
use chrono::Utc;
use std::collections::HashMap;

#[test]
fn append_event_and_get_all() {
    event_store::clear_all_events();

    let mut data = HashMap::new();
    data.insert("name".to_string(), serde_json::json!("Test"));
    data.insert("timestamp".to_string(), serde_json::json!(Utc::now().to_rfc3339()));

    let e = event_store::append_event("contact", "c1", "CREATED", data, 1);

    let all = event_store::get_all_events();
    assert_eq!(all.len(), 1);
    assert_eq!(all[0].id, e.id);
    assert_eq!(all[0].aggregate_type, "contact");
    assert_eq!(all[0].aggregate_id, "c1");
    assert_eq!(all[0].event_type, "CREATED");
    assert!(!all[0].synced);

    event_store::clear_all_events();
}

#[test]
fn get_events_for_aggregate() {
    event_store::clear_all_events();

    let mut data = HashMap::new();
    data.insert("name".to_string(), serde_json::json!("A"));
    data.insert("timestamp".to_string(), serde_json::json!(Utc::now().to_rfc3339()));

    event_store::append_event("contact", "c1", "CREATED", data.clone(), 1);
    event_store::append_event("contact", "c2", "CREATED", data, 1);

    let for_c1 = event_store::get_events_for_aggregate("contact", "c1");
    assert_eq!(for_c1.len(), 1);
    assert_eq!(for_c1[0].aggregate_id, "c1");

    event_store::clear_all_events();
}

#[test]
fn get_unsynced_events() {
    event_store::clear_all_events();

    let mut data = HashMap::new();
    data.insert("timestamp".to_string(), serde_json::json!(Utc::now().to_rfc3339()));

    event_store::append_event("contact", "c1", "CREATED", data, 1);
    let unsynced = event_store::get_unsynced_events(None);
    assert_eq!(unsynced.len(), 1);

    let id = unsynced[0].id.clone();
    event_store::mark_event_synced(&id);
    let unsynced2 = event_store::get_unsynced_events(None);
    assert!(unsynced2.is_empty());

    event_store::clear_all_events();
}
