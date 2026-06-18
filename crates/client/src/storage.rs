//! Compatibility wrapper: re-exports database functions with String error conversion.
//!
//! This module provides backward compatibility during the migration from string-based
//! error handling to typed ClientError. New code should use the database:: module directly.

use crate::database;
use crate::models::{Contact, Transaction};

pub use database::StoredEvent;

pub fn is_ready() -> bool {
    database::is_ready()
}

pub fn init(path: &str) -> Result<(), String> {
    database::init(path).map_err(|e| e.to_string())
}

pub fn config_get(key: &str) -> Result<Option<String>, String> {
    database::config_get(key).map_err(|e| e.to_string())
}

pub fn config_set(key: &str, value: &str) -> Result<(), String> {
    database::config_set(key, value).map_err(|e| e.to_string())
}

pub fn config_remove(key: &str) -> Result<(), String> {
    database::config_remove(key).map_err(|e| e.to_string())
}

pub fn clear_all() -> Result<(), String> {
    database::clear_all().map_err(|e| e.to_string())
}

pub fn clear_wallet(wallet_id: &str) -> Result<(), String> {
    database::clear_wallet(wallet_id).map_err(|e| e.to_string())
}

pub fn events_insert(e: &StoredEvent) -> Result<(), String> {
    database::events_insert(e).map_err(|e| e.to_string())
}

pub fn events_update_event_data(event_id: &str, event_data_json: &str) -> Result<(), String> {
    database::events_update_event_data(event_id, event_data_json).map_err(|e| e.to_string())
}

pub fn events_get_all(wallet_id: &str) -> Result<Vec<StoredEvent>, String> {
    database::events_get_all(wallet_id).map_err(|e| e.to_string())
}

pub fn events_get_unsynced(wallet_id: &str) -> Result<Vec<StoredEvent>, String> {
    database::events_get_unsynced(wallet_id).map_err(|e| e.to_string())
}

pub fn events_mark_synced(ids: &[String]) -> Result<(), String> {
    database::events_mark_synced(ids).map_err(|e| e.to_string())
}

pub fn events_delete_unsynced(wallet_id: &str) -> Result<u64, String> {
    database::events_delete_unsynced(wallet_id).map_err(|e| e.to_string())
}

pub fn events_delete_all_for_wallet(wallet_id: &str) -> Result<(), String> {
    database::events_delete_all_for_wallet(wallet_id).map_err(|e| e.to_string())
}

pub fn events_count(wallet_id: &str) -> Result<i64, String> {
    database::events_count(wallet_id).map_err(|e| e.to_string())
}

pub fn events_get_for_aggregate(
    wallet_id: &str,
    aggregate_type: &str,
    aggregate_id: &str,
) -> Result<Vec<StoredEvent>, String> {
    database::events_get_for_aggregate(wallet_id, aggregate_type, aggregate_id)
        .map_err(|e| e.to_string())
}

pub fn load_contacts_from_tables(wallet_id: &str) -> Result<Vec<Contact>, String> {
    database::load_contacts_from_tables(wallet_id).map_err(|e| e.to_string())
}

pub fn load_transactions_from_tables(wallet_id: &str) -> Result<Vec<Transaction>, String> {
    database::load_transactions_from_tables(wallet_id).map_err(|e| e.to_string())
}

pub(crate) fn with_db<F, T>(f: F) -> Result<T, String>
where
    F: FnOnce(&rusqlite::Connection) -> Result<T, rusqlite::Error>,
{
    database::with_db(f).map_err(|e| e.to_string())
}
