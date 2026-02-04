//! In-memory event store with optional file persistence. Replaces Hive EventStore.

use crate::models::Event;
use chrono::Utc;
use std::collections::HashMap;
use std::sync::Mutex;

static EVENTS: once_cell::sync::Lazy<Mutex<Vec<Event>>> = once_cell::sync::Lazy::new(|| Mutex::new(Vec::new()));

pub fn get_all_events() -> Vec<Event> {
    let mut list = EVENTS.lock().unwrap().clone();
    list.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
    list
}

pub fn get_events_for_aggregate(aggregate_type: &str, aggregate_id: &str) -> Vec<Event> {
    let list = EVENTS.lock().unwrap();
    let mut out: Vec<Event> = list
        .iter()
        .filter(|e| e.aggregate_type == aggregate_type && e.aggregate_id == aggregate_id)
        .cloned()
        .collect();
    out.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
    out
}

pub fn get_unsynced_events(_wallet_id: Option<&str>) -> Vec<Event> {
    let list = EVENTS.lock().unwrap();
    let mut out: Vec<Event> = list.iter().filter(|e| !e.synced).cloned().collect();
    out.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
    out
}

pub fn append_event(
    aggregate_type: &str,
    aggregate_id: &str,
    event_type: &str,
    event_data: HashMap<String, serde_json::Value>,
    version: i32,
) -> Event {
    let event = Event {
        id: uuid::Uuid::new_v4().to_string(),
        aggregate_type: aggregate_type.to_string(),
        aggregate_id: aggregate_id.to_string(),
        event_type: event_type.to_string(),
        event_data,
        timestamp: Utc::now(),
        version,
        synced: false,
    };
    EVENTS.lock().unwrap().push(event.clone());
    event
}

pub fn mark_event_synced(event_id: &str) {
    let mut list = EVENTS.lock().unwrap();
    if let Some(e) = list.iter_mut().find(|e| e.id == event_id) {
        e.synced = true;
    }
}

pub fn get_latest_version(aggregate_type: &str, aggregate_id: &str) -> i32 {
    let list = EVENTS.lock().unwrap();
    list.iter()
        .filter(|e| e.aggregate_type == aggregate_type && e.aggregate_id == aggregate_id)
        .map(|e| e.version)
        .max()
        .unwrap_or(0)
}

pub fn clear_all_events() {
    EVENTS.lock().unwrap().clear();
}

pub fn event_count() -> usize {
    EVENTS.lock().unwrap().len()
}

pub fn get_events_after(timestamp: chrono::DateTime<Utc>) -> Vec<Event> {
    let list = EVENTS.lock().unwrap();
    let mut out: Vec<Event> = list.iter().filter(|e| e.timestamp > timestamp).cloned().collect();
    out.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
    out
}
