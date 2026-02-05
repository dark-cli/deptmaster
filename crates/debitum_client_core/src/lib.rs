use std::sync::Mutex;
use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;

pub use serde_json::Value;

mod api;
mod crud;
mod frb_generated;
mod ids;
mod log_bridge;
mod models;
mod state_builder;
mod storage;
mod sync;

struct BackendConfig {
    base_url: String,
    ws_url: String,
}
static BACKEND_CONFIG: Lazy<Mutex<Option<BackendConfig>>> = Lazy::new(|| Mutex::new(None));

#[frb(init)]
pub fn init_app() {
    // Storage is initialized via init_storage(path) from Dart.
}

/// Call once at startup with the app documents directory path (e.g. from path_provider).
pub fn init_storage(storage_path: String) -> Result<(), String> {
    storage::init(&storage_path)
}

pub fn set_backend_config(base_url: String, ws_url: String) {
    *BACKEND_CONFIG.lock().unwrap() = Some(BackendConfig { base_url, ws_url });
}

pub fn get_base_url() -> Option<String> {
    BACKEND_CONFIG.lock().unwrap().as_ref().map(|c| c.base_url.clone())
}

pub fn get_ws_url() -> Option<String> {
    BACKEND_CONFIG.lock().unwrap().as_ref().map(|c| c.ws_url.clone())
}

// --- Auth ---
pub fn login(username: String, password: String) -> Result<(), String> {
    api::login(username, password)
}

pub fn logout() -> Result<(), String> {
    crud::logout()
}

pub fn is_logged_in() -> bool {
    storage::config_get("token").ok().and_then(|o| o).is_some()
}

pub fn get_user_id() -> Option<String> {
    storage::config_get("user_id").ok().and_then(|o| o)
}

pub fn get_token() -> Option<String> {
    storage::config_get("token").ok().and_then(|o| o)
}

// --- Wallet ---
pub fn set_current_wallet_id(wallet_id: String) -> Result<(), String> {
    rust_log!("[debitum_rs] set_current_wallet_id wallet_id={}", wallet_id);
    let _ = ids::WalletId::parse(&wallet_id).map_err(|e| e)?;
    storage::config_set("current_wallet_id", &wallet_id)
}

pub fn get_current_wallet_id() -> Option<String> {
    storage::config_get("current_wallet_id").ok().and_then(|o| o)
}

pub fn get_wallets() -> Result<String, String> {
    let list = api::get_wallets_api()?;
    serde_json::to_string(&list).map_err(|e| e.to_string())
}

pub fn create_wallet(name: String, description: String) -> Result<String, String> {
    let w = api::create_wallet_api(name, description)?;
    serde_json::to_string(&w).map_err(|e| e.to_string())
}

pub fn ensure_current_wallet() -> Result<(), String> {
    if get_current_wallet_id().is_some() {
        return Ok(());
    }
    let list = api::get_wallets_api()?;
    let first = list.into_iter().next().ok_or("No wallets")?;
    let _ = ids::WalletId::parse(&first.id).map_err(|e| e)?;
    set_current_wallet_id(first.id)
}

// --- Data (JSON strings for Dart) ---
pub fn get_contacts() -> Result<String, String> {
    crud::get_contacts()
}

pub fn get_transactions() -> Result<String, String> {
    crud::get_transactions()
}

pub fn get_contact(id: String) -> Result<Option<String>, String> {
    crud::get_contact(id)
}

pub fn create_contact(
    name: String,
    username: Option<String>,
    phone: Option<String>,
    email: Option<String>,
    notes: Option<String>,
) -> Result<String, String> {
    let c = crud::create_contact(name, username, phone, email, notes)?;
    serde_json::to_string(&c).map_err(|e| e.to_string())
}

pub fn create_transaction(
    contact_id: String,
    type_: String,
    direction: String,
    amount: i64,
    currency: String,
    description: Option<String>,
    transaction_date: String,
    due_date: Option<String>,
) -> Result<String, String> {
    let t = crud::create_transaction(
        contact_id,
        type_,
        direction,
        amount,
        currency,
        description,
        transaction_date,
        due_date,
    )?;
    serde_json::to_string(&t).map_err(|e| e.to_string())
}

pub fn get_transaction(id: String) -> Result<Option<String>, String> {
    crud::get_transaction(id)
}

pub fn update_contact(
    id: String,
    name: String,
    username: Option<String>,
    phone: Option<String>,
    email: Option<String>,
    notes: Option<String>,
) -> Result<(), String> {
    crud::update_contact(id, name, username, phone, email, notes)
}

pub fn delete_contact(contact_id: String) -> Result<(), String> {
    crud::delete_contact(contact_id)
}

pub fn update_transaction(
    id: String,
    contact_id: String,
    type_: String,
    direction: String,
    amount: i64,
    currency: String,
    description: Option<String>,
    transaction_date: String,
    due_date: Option<String>,
) -> Result<(), String> {
    crud::update_transaction(
        id,
        contact_id,
        type_,
        direction,
        amount,
        currency,
        description,
        transaction_date,
        due_date,
    )
}

pub fn delete_transaction(transaction_id: String) -> Result<(), String> {
    crud::delete_transaction(transaction_id)
}

pub fn undo_contact_action(contact_id: String) -> Result<(), String> {
    crud::undo_contact_action(contact_id)
}

pub fn undo_transaction_action(transaction_id: String) -> Result<(), String> {
    crud::undo_transaction_action(transaction_id)
}

pub fn bulk_delete_contacts(contact_ids: Vec<String>) -> Result<(), String> {
    crud::bulk_delete_contacts(contact_ids)
}

pub fn bulk_delete_transactions(transaction_ids: Vec<String>) -> Result<(), String> {
    crud::bulk_delete_transactions(transaction_ids)
}

// --- Events (for events log / EventStoreService) ---
pub fn get_events() -> Result<String, String> {
    let wallet_id = match storage::config_get("current_wallet_id")? {
        Some(id) => id,
        None => {
            rust_log!("[debitum_rs] get_events: no current_wallet_id in config -> []");
            return Ok("[]".to_string());
        }
    };
    rust_log!("[debitum_rs] get_events wallet_id={} querying storage...", wallet_id);
    let events = storage::events_get_all(&wallet_id)?;
    rust_log!("[debitum_rs] get_events returning {} events", events.len());
    let list: Vec<serde_json::Value> = events
        .into_iter()
        .map(|e| {
            let event_data: serde_json::Value = serde_json::from_str(&e.event_data).unwrap_or(serde_json::Value::Null);
            serde_json::json!({
                "id": e.id,
                "aggregate_type": e.aggregate_type,
                "aggregate_id": e.aggregate_id,
                "event_type": e.event_type,
                "event_data": event_data,
                "timestamp": e.timestamp,
                "version": e.version,
                "synced": e.synced,
            })
        })
        .collect();
    serde_json::to_string(&list).map_err(|e| e.to_string())
}

// --- Sync ---
pub fn manual_sync() -> Result<(), String> {
    sync::full_sync().map_err(|e| {
        rust_log!("[debitum_rs] manual_sync failed: {}", e);
        e
    })
}

/// Drain buffered Rust log lines so Dart can show them (e.g. via debugPrint).
pub fn drain_rust_logs() -> Vec<String> {
    log_bridge::drain_rust_logs()
}

// Kept for compatibility
pub fn greet(name: String) -> String {
    format!("Hello, {} from Rust!", name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{self, StoredEvent};
    use std::path::PathBuf;

    fn temp_storage_path() -> PathBuf {
        let dir = tempfile::tempdir().expect("tempdir");
        dir.path().to_path_buf()
    }

    #[test]
    fn get_events_returns_empty_json_array_when_no_current_wallet() {
        let path = temp_storage_path();
        storage::init(path.to_str().unwrap()).expect("init");
        // Do not set current_wallet_id
        let json = get_events().expect("get_events");
        assert_eq!(json, "[]", "expected [] when no wallet set");
    }

    #[test]
    fn get_events_returns_empty_json_array_when_wallet_has_no_events() {
        let path = temp_storage_path();
        storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "f27978af-e56a-4b45-aede-fb450557699a";
        storage::config_set("current_wallet_id", wallet_id).expect("config_set");
        let json = get_events().expect("get_events");
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).expect("parse json");
        assert!(parsed.is_empty(), "expected no events for fresh wallet");
    }

    #[test]
    fn get_events_returns_events_after_insert() {
        let path = temp_storage_path();
        storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "f27978af-e56a-4b45-aede-fb450557699a";
        storage::config_set("current_wallet_id", wallet_id).expect("config_set");

        let event = StoredEvent {
            id: "event-1".to_string(),
            wallet_id: wallet_id.to_string(),
            aggregate_type: "contact".to_string(),
            aggregate_id: "contact-1".to_string(),
            event_type: "CREATED".to_string(),
            event_data: r#"{"name":"Test","total_debt":0}"#.to_string(),
            timestamp: "2026-02-04T12:00:00Z".to_string(),
            version: 1,
            synced: false,
        };
        storage::events_insert(&event).expect("events_insert");

        let json = get_events().expect("get_events");
        let parsed: Vec<serde_json::Value> = serde_json::from_str(&json).expect("parse json");
        assert_eq!(parsed.len(), 1, "expected one event");
        assert_eq!(parsed[0]["id"], "event-1");
        assert_eq!(parsed[0]["event_type"], "CREATED");
    }

    #[test]
    fn events_count_zero_for_new_wallet() {
        let path = temp_storage_path();
        storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "cb203efe-c27c-470e-bbc6-588172c3b1ae";
        let count = storage::events_count(wallet_id).expect("events_count");
        assert_eq!(count, 0);
    }

    #[test]
    fn set_and_get_current_wallet_id() {
        let path = temp_storage_path();
        storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "f27978af-e56a-4b45-aede-fb450557699a";
        set_current_wallet_id(wallet_id.to_string()).expect("set_current_wallet_id");
        let got = get_current_wallet_id();
        assert_eq!(got.as_deref(), Some(wallet_id));
    }

    #[test]
    fn init_storage_creates_db_file() {
        let path = temp_storage_path();
        let db_path = path.join("debitum.db");
        assert!(!db_path.exists());
        init_storage(path.to_str().unwrap().to_string()).expect("init_storage");
        assert!(db_path.exists(), "debitum.db should exist after init");
    }

    /// Sync does a full pull (no since) when local event count is 0. This test verifies
    /// that after init + set wallet, events_count is 0 so the next pull would be full.
    #[test]
    fn full_pull_condition_when_no_local_events() {
        let path = temp_storage_path();
        storage::init(path.to_str().unwrap()).expect("init");
        let wallet_id = "f27978af-e56a-4b45-aede-fb450557699a";
        storage::config_set("current_wallet_id", wallet_id).expect("config_set");
        let count = storage::events_count(wallet_id).expect("events_count");
        assert_eq!(count, 0, "new wallet should have 0 events so sync will do full pull");
    }
}
