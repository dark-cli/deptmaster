//! Port of Flutter state_builder_test.dart – build state from events, UNDO, balances.

use debitum_frontend::models::Event;
use debitum_frontend::state_builder;
use chrono::{TimeZone, Utc};
use std::collections::HashMap;

fn now() -> chrono::DateTime<Utc> {
    Utc::now()
}

fn event_data_contact(name: &str, timestamp: chrono::DateTime<Utc>) -> HashMap<String, serde_json::Value> {
    let mut m = HashMap::new();
    m.insert("name".to_string(), serde_json::json!(name));
    m.insert("timestamp".to_string(), serde_json::json!(timestamp.to_rfc3339()));
    m
}

fn event_data_transaction(
    contact_id: &str,
    direction: &str,
    amount: i64,
    transaction_date: &str,
    timestamp: chrono::DateTime<Utc>,
) -> HashMap<String, serde_json::Value> {
    let mut m = HashMap::new();
    m.insert("contact_id".to_string(), serde_json::json!(contact_id));
    m.insert("type".to_string(), serde_json::json!("money"));
    m.insert("direction".to_string(), serde_json::json!(direction));
    m.insert("amount".to_string(), serde_json::json!(amount));
    m.insert("currency".to_string(), serde_json::json!("IQD"));
    m.insert("transaction_date".to_string(), serde_json::json!(transaction_date));
    m.insert("timestamp".to_string(), serde_json::json!(timestamp.to_rfc3339()));
    m
}

#[test]
fn build_state_empty_events_returns_empty_state() {
    let state = state_builder::build_state(&[]);
    assert!(state.contacts.is_empty());
    assert!(state.transactions.is_empty());
}

#[test]
fn build_state_creates_contact_from_created_event() {
    let t = now();
    let contact_id = "contact-1";
    let event = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: {
            let mut m = event_data_contact("Test Contact", t);
            m.insert("username".to_string(), serde_json::json!("testuser"));
            m.insert("phone".to_string(), serde_json::json!("123456789"));
            m.insert("email".to_string(), serde_json::json!("test@example.com"));
            m.insert("notes".to_string(), serde_json::json!("Test notes"));
            m
        },
        timestamp: t,
        version: 1,
        synced: false,
    };

    let state = state_builder::build_state(&[event]);

    assert_eq!(state.contacts.len(), 1);
    let c = &state.contacts[0];
    assert_eq!(c.id, contact_id);
    assert_eq!(c.name, "Test Contact");
    assert_eq!(c.username.as_deref(), Some("testuser"));
    assert_eq!(c.phone.as_deref(), Some("123456789"));
    assert_eq!(c.email.as_deref(), Some("test@example.com"));
    assert_eq!(c.notes.as_deref(), Some("Test notes"));
    assert_eq!(c.balance, 0);
}

#[test]
fn build_state_updates_contact_from_updated_event() {
    let t = now();
    let contact_id = "contact-1";
    let created = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_contact("Original Name", t),
        timestamp: t,
        version: 1,
        synced: false,
    };
    let updated = Event {
        id: "event-2".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UPDATED".to_string(),
        event_data: {
            let mut m = event_data_contact("Updated Name", t + chrono::Duration::seconds(1));
            m.insert("phone".to_string(), serde_json::json!("987654321"));
            m
        },
        timestamp: t + chrono::Duration::seconds(1),
        version: 2,
        synced: false,
    };

    let state = state_builder::build_state(&[created, updated]);

    assert_eq!(state.contacts.len(), 1);
    assert_eq!(state.contacts[0].name, "Updated Name");
    assert_eq!(state.contacts[0].phone.as_deref(), Some("987654321"));
}

#[test]
fn build_state_deletes_contact_from_deleted_event() {
    let t = now();
    let contact_id = "contact-1";
    let created = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_contact("Test Contact", t),
        timestamp: t,
        version: 1,
        synced: false,
    };
    let deleted = Event {
        id: "event-2".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "DELETED".to_string(),
        event_data: {
            let mut m = HashMap::new();
            m.insert("timestamp".to_string(), serde_json::json!((t + chrono::Duration::seconds(1)).to_rfc3339()));
            m
        },
        timestamp: t + chrono::Duration::seconds(1),
        version: 2,
        synced: false,
    };

    let state = state_builder::build_state(&[created, deleted]);

    assert!(state.contacts.is_empty());
}

#[test]
fn build_state_creates_transaction_and_calculates_balance() {
    let t = now();
    let contact_id = "contact-1";
    let transaction_id = "transaction-1";
    let date_str = t.format("%Y-%m-%d").to_string();

    let contact_event = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_contact("Test Contact", t),
        timestamp: t,
        version: 1,
        synced: false,
    };
    let transaction_event = Event {
        id: "event-2".to_string(),
        aggregate_type: "transaction".to_string(),
        aggregate_id: transaction_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_transaction(contact_id, "lent", 100000, &date_str, t + chrono::Duration::seconds(1)),
        timestamp: t + chrono::Duration::seconds(1),
        version: 1,
        synced: false,
    };

    let state = state_builder::build_state(&[contact_event, transaction_event]);

    assert_eq!(state.contacts.len(), 1);
    assert_eq!(state.transactions.len(), 1);
    assert_eq!(state.contacts[0].balance, 100000); // lent = positive
}

#[test]
fn build_state_calculates_balance_with_multiple_transactions() {
    let t = now();
    let contact_id = "contact-1";
    let date_str = t.format("%Y-%m-%d").to_string();

    let contact_event = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_contact("Test Contact", t),
        timestamp: t,
        version: 1,
        synced: false,
    };
    let lent_event = Event {
        id: "event-2".to_string(),
        aggregate_type: "transaction".to_string(),
        aggregate_id: "txn-1".to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_transaction(contact_id, "lent", 100000, &date_str, t + chrono::Duration::seconds(1)),
        timestamp: t + chrono::Duration::seconds(1),
        version: 1,
        synced: false,
    };
    let owed_event = Event {
        id: "event-3".to_string(),
        aggregate_type: "transaction".to_string(),
        aggregate_id: "txn-2".to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_transaction(contact_id, "owed", 50000, &date_str, t + chrono::Duration::seconds(2)),
        timestamp: t + chrono::Duration::seconds(2),
        version: 1,
        synced: false,
    };

    let state = state_builder::build_state(&[contact_event, lent_event, owed_event]);

    assert_eq!(state.contacts.len(), 1);
    assert_eq!(state.contacts[0].balance, 50000); // 100000 - 50000
}

#[test]
fn apply_events_updates_existing_state_incrementally() {
    let t = now();
    let contact_id = "contact-1";

    let initial_event = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_contact("Initial Contact", t),
        timestamp: t,
        version: 1,
        synced: false,
    };
    let initial_state = state_builder::build_state(&[initial_event]);
    assert_eq!(initial_state.contacts.len(), 1);
    assert_eq!(initial_state.contacts[0].name, "Initial Contact");

    let new_event = Event {
        id: "event-2".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UPDATED".to_string(),
        event_data: event_data_contact("Updated Contact", t + chrono::Duration::seconds(1)),
        timestamp: t + chrono::Duration::seconds(1),
        version: 2,
        synced: false,
    };
    let updated_state = state_builder::apply_events(&initial_state, &[new_event]);

    assert_eq!(updated_state.contacts.len(), 1);
    assert_eq!(updated_state.contacts[0].name, "Updated Contact");
}

#[test]
fn apply_events_with_empty_events_returns_same_state() {
    let t = now();
    let contact_id = "contact-1";
    let event = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_contact("Test Contact", t),
        timestamp: t,
        version: 1,
        synced: false,
    };
    let initial_state = state_builder::build_state(&[event]);
    let updated_state = state_builder::apply_events(&initial_state, &[]);

    assert_eq!(updated_state.contacts.len(), initial_state.contacts.len());
    assert_eq!(updated_state.contacts[0].name, initial_state.contacts[0].name);
}

#[test]
fn build_state_skips_undo_events_and_undone_events() {
    let t = now();
    let contact_id = "contact-1";

    let created = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_contact("Original Name", t),
        timestamp: t,
        version: 1,
        synced: false,
    };
    let updated = Event {
        id: "event-2".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UPDATED".to_string(),
        event_data: event_data_contact("Updated Name", t + chrono::Duration::seconds(1)),
        timestamp: t + chrono::Duration::seconds(1),
        version: 2,
        synced: false,
    };
    let mut undo_data = HashMap::new();
    undo_data.insert("undone_event_id".to_string(), serde_json::json!("event-2"));
    undo_data.insert("timestamp".to_string(), serde_json::json!((t + chrono::Duration::seconds(2)).to_rfc3339()));
    let undo_event = Event {
        id: "event-3".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: undo_data,
        timestamp: t + chrono::Duration::seconds(2),
        version: 3,
        synced: false,
    };

    let state = state_builder::build_state(&[created, updated, undo_event]);

    assert_eq!(state.contacts.len(), 1);
    assert_eq!(state.contacts[0].name, "Original Name");
}

#[test]
fn build_state_handles_undo_for_transaction_correctly() {
    let t = now();
    let contact_id = "contact-1";
    let transaction_id = "transaction-1";
    let date_str = t.format("%Y-%m-%d").to_string();

    let contact_event = Event {
        id: "event-1".to_string(),
        aggregate_type: "contact".to_string(),
        aggregate_id: contact_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_contact("Test Contact", t),
        timestamp: t,
        version: 1,
        synced: false,
    };
    let transaction_event = Event {
        id: "event-2".to_string(),
        aggregate_type: "transaction".to_string(),
        aggregate_id: transaction_id.to_string(),
        event_type: "CREATED".to_string(),
        event_data: event_data_transaction(contact_id, "lent", 100000, &date_str, t + chrono::Duration::seconds(1)),
        timestamp: t + chrono::Duration::seconds(1),
        version: 1,
        synced: false,
    };
    let mut undo_data = HashMap::new();
    undo_data.insert("undone_event_id".to_string(), serde_json::json!("event-2"));
    undo_data.insert("timestamp".to_string(), serde_json::json!((t + chrono::Duration::seconds(2)).to_rfc3339()));
    let undo_event = Event {
        id: "event-3".to_string(),
        aggregate_type: "transaction".to_string(),
        aggregate_id: transaction_id.to_string(),
        event_type: "UNDO".to_string(),
        event_data: undo_data,
        timestamp: t + chrono::Duration::seconds(2),
        version: 2,
        synced: false,
    };

    let state = state_builder::build_state(&[contact_event, transaction_event, undo_event]);

    assert!(state.transactions.is_empty());
    assert_eq!(state.contacts[0].balance, 0);
}
