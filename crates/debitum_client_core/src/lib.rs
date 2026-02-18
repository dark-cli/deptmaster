#![allow(unexpected_cfgs)] // flutter_rust_bridge macro emits frb_expand cfg
use std::cell::RefCell;
use std::sync::Mutex;
use std::time::Duration;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;
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
mod backoff;

struct BackendConfig {
    base_url: String,
    ws_url: String,
}

// Thread-local: each thread has its own backend config (e.g. each integration test).
// When a thread has no config, get_base_url falls back to this global so Flutter (which may
// dispatch Rust calls to different threads) still sees the config set by set_backend_config.
thread_local! {
    static BACKEND_CONFIG: RefCell<Option<BackendConfig>> = RefCell::new(None);
}
static BACKEND_CONFIG_GLOBAL: Lazy<Mutex<Option<BackendConfig>>> = Lazy::new(|| Mutex::new(None));

// Thread-local offline flag: when true, API calls return "Network offline" (see set_network_offline).
thread_local! {
    static NETWORK_OFFLINE: RefCell<bool> = RefCell::new(false);
}

// Thread-local so parallel integration tests (each on their own thread) don't block each other's sync.
thread_local! {
    static SYNC_BACKOFF: RefCell<backoff::Backoff> = RefCell::new(backoff::Backoff::new(vec![
        Duration::from_millis(500),
        Duration::from_millis(500),
        Duration::from_secs(1),
        Duration::from_secs(1),
        Duration::from_secs(1),
        Duration::from_secs(2),
        Duration::from_secs(2),
        Duration::from_secs(2),
        Duration::from_secs(3),
    ]));
}
thread_local! {
    static SYNC_IN_FLIGHT: RefCell<bool> = RefCell::new(false);
}
static SYNC_LOOP_STARTED: AtomicBool = AtomicBool::new(false);
static LAST_BACKOFF_SKIP_LOG: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));
static LAST_INFLIGHT_SKIP_LOG: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));
static LAST_NO_WALLET_SKIP_LOG: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));

struct SyncGuard;

impl SyncGuard {
    fn try_acquire() -> Option<Self> {
        SYNC_IN_FLIGHT.with(|c| {
            if *c.borrow() {
                return None;
            }
            *c.borrow_mut() = true;
            Some(Self)
        })
    }
}

impl Drop for SyncGuard {
    fn drop(&mut self) {
        SYNC_IN_FLIGHT.with(|c| *c.borrow_mut() = false);
    }
}

/// Sync is driven by WS notification (client pulls when server pushes). No background polling.
/// Set to true only to re-enable a fallback sync loop (interval ~1s).
const BACKGROUND_SYNC_LOOP_ENABLED: bool = false;

fn start_sync_loop_if_ready() {
    if !BACKGROUND_SYNC_LOOP_ENABLED {
        return;
    }
    if !storage::is_ready() {
        return;
    }
    let backend_ready = BACKEND_CONFIG.with(|c| c.borrow().is_some());
    if !backend_ready {
        return;
    }
    if SYNC_LOOP_STARTED.swap(true, Ordering::Relaxed) {
        return;
    }
    rust_log!("[debitum_rs] sync loop: started (interval=1000ms)");
    std::thread::spawn(|| {
        loop {
            // Only attempt sync when storage and backend are ready on this thread (sync loop has its own thread-local state; when disabled this is never true).
            if storage::is_ready() && BACKEND_CONFIG.with(|c| c.borrow().is_some()) {
                let _ = manual_sync_with_source("background_loop");
            }
            let delay_ms = SYNC_BACKOFF
                .with(|b| {
                    b.borrow()
                        .remaining()
                        .map(|d| d.as_millis().clamp(100, 3000) as u64)
                        .unwrap_or(1000)
                });
            std::thread::sleep(Duration::from_millis(delay_ms));
        }
    });
}

fn should_log_skip(last: &Lazy<Mutex<Option<Instant>>>, min_interval_ms: u64) -> bool {
    let mut guard = last.lock().unwrap();
    let now = Instant::now();
    match *guard {
        Some(t) if now.duration_since(t).as_millis() < min_interval_ms as u128 => false,
        _ => {
            *guard = Some(now);
            true
        }
    }
}

#[frb(init)]
pub fn init_app() {
    // Storage is initialized via init_storage(path) from Dart.
}

/// Call once at startup with the app documents directory path (e.g. from path_provider).
/// Storage is process-wide; no need to call again from every thread.
pub fn init_storage(storage_path: String) -> Result<(), String> {
    let was_ready = storage::is_ready();
    storage::init(&storage_path)?;
    if !was_ready {
        rust_log!("[debitum_rs] sync loop: storage ready");
        start_sync_loop_if_ready();
    }
    Ok(())
}

pub fn set_backend_config(base_url: String, ws_url: String) {
    let already_same = get_base_url().as_deref() == Some(base_url.as_str())
        && get_ws_url().as_deref() == Some(ws_url.as_str());
    if already_same {
        return;
    }
    let cfg = BackendConfig { base_url, ws_url };
    BACKEND_CONFIG.with(|cell| *cell.borrow_mut() = Some(BackendConfig { base_url: cfg.base_url.clone(), ws_url: cfg.ws_url.clone() }));
    *BACKEND_CONFIG_GLOBAL.lock().unwrap() = Some(cfg);
    rust_log!("[debitum_rs] sync loop: backend config set");
    start_sync_loop_if_ready();
}

pub fn get_base_url() -> Option<String> {
    BACKEND_CONFIG
        .with(|cell| cell.borrow().as_ref().map(|c| c.base_url.clone()))
        .or_else(|| BACKEND_CONFIG_GLOBAL.lock().unwrap().as_ref().map(|c| c.base_url.clone()))
}

pub fn get_ws_url() -> Option<String> {
    BACKEND_CONFIG
        .with(|cell| cell.borrow().as_ref().map(|c| c.ws_url.clone()))
        .or_else(|| BACKEND_CONFIG_GLOBAL.lock().unwrap().as_ref().map(|c| c.ws_url.clone()))
}

/// Set whether the client is in "offline" mode. When true, all API requests return an error without hitting the network.
/// The app reconnects WS when going online; WS connection triggers sync (app logic, not here).
/// Thread-local (per test / per app when using multiple instances).
pub fn set_network_offline(offline: bool) {
    NETWORK_OFFLINE.with(|cell| *cell.borrow_mut() = offline);
}

/// True if the client is in offline mode (network requests will fail).
pub fn is_network_offline() -> bool {
    NETWORK_OFFLINE.with(|cell| *cell.borrow())
}

// --- Auth ---
pub fn login(username: String, password: String) -> Result<(), String> {
    api::login(username, password)
}

pub fn register(username: String, password: String) -> Result<(), String> {
    api::register(username, password)
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

// --- Wallet management (manage wallet screen: users, groups, matrix) ---
pub fn list_wallet_users(wallet_id: String) -> Result<String, String> {
    api::list_wallet_users_api(&wallet_id)
}

pub fn search_wallet_users(wallet_id: String, query: String) -> Result<String, String> {
    api::search_wallet_users_api(&wallet_id, &query)
}

pub fn add_user_to_wallet(wallet_id: String, username: String) -> Result<(), String> {
    api::add_user_to_wallet_api(&wallet_id, &username)
}

/// Create or replace 4-digit invite code for the wallet. Returns the code string.
pub fn create_wallet_invite_code(wallet_id: String) -> Result<String, String> {
    api::create_wallet_invite_api(&wallet_id)
}

/// Join a wallet by invite code. Returns the wallet_id of the joined wallet.
pub fn join_wallet_by_code(code: String) -> Result<String, String> {
    api::join_wallet_by_code_api(&code)
}

pub fn update_wallet_user_role(wallet_id: String, user_id: String, role: String) -> Result<(), String> {
    api::update_wallet_user_api(&wallet_id, &user_id, &role)
}

pub fn remove_wallet_user(wallet_id: String, user_id: String) -> Result<(), String> {
    api::remove_wallet_user_api(&wallet_id, &user_id)
}

pub fn list_wallet_user_groups(wallet_id: String) -> Result<String, String> {
    api::list_user_groups_api(&wallet_id)
}

pub fn create_wallet_user_group(wallet_id: String, name: String) -> Result<String, String> {
    api::create_user_group_api(&wallet_id, &name)
}

pub fn update_wallet_user_group(wallet_id: String, group_id: String, name: String) -> Result<(), String> {
    api::update_user_group_api(&wallet_id, &group_id, &name)
}

pub fn delete_wallet_user_group(wallet_id: String, group_id: String) -> Result<(), String> {
    api::delete_user_group_api(&wallet_id, &group_id)
}

pub fn list_wallet_user_group_members(wallet_id: String, group_id: String) -> Result<String, String> {
    api::list_user_group_members_api(&wallet_id, &group_id)
}

pub fn add_wallet_user_group_member(wallet_id: String, group_id: String, user_id: String) -> Result<(), String> {
    api::add_user_group_member_api(&wallet_id, &group_id, &user_id)
}

pub fn remove_wallet_user_group_member(wallet_id: String, group_id: String, user_id: String) -> Result<(), String> {
    api::remove_user_group_member_api(&wallet_id, &group_id, &user_id)
}

pub fn list_wallet_contact_groups(wallet_id: String) -> Result<String, String> {
    api::list_contact_groups_api(&wallet_id)
}

pub fn create_wallet_contact_group(wallet_id: String, name: String) -> Result<String, String> {
    api::create_contact_group_api(&wallet_id, &name)
}

pub fn update_wallet_contact_group(wallet_id: String, group_id: String, name: String) -> Result<(), String> {
    api::update_contact_group_api(&wallet_id, &group_id, &name)
}

pub fn delete_wallet_contact_group(wallet_id: String, group_id: String) -> Result<(), String> {
    api::delete_contact_group_api(&wallet_id, &group_id)
}

pub fn list_wallet_contact_group_members(wallet_id: String, group_id: String) -> Result<String, String> {
    api::list_contact_group_members_api(&wallet_id, &group_id)
}

/// Returns JSON array of contact group ids that contain this contact. Used by edit-contact UI.
pub fn get_contact_group_ids_for_contact(wallet_id: String, contact_id: String) -> Result<String, String> {
    let groups_json = api::list_contact_groups_api(&wallet_id)?;
    let groups: Vec<serde_json::Value> = serde_json::from_str(&groups_json).map_err(|e| e.to_string())?;
    let mut result = Vec::new();
    for g in groups {
        let group_id = match g.get("id").and_then(|v| v.as_str()) {
            Some(id) => id.to_string(),
            None => continue,
        };
        let members_json = api::list_contact_group_members_api(&wallet_id, &group_id)?;
        let members: Vec<serde_json::Value> = serde_json::from_str(&members_json).unwrap_or_default();
        for m in members {
            if m.get("contact_id").and_then(|v| v.as_str()) == Some(contact_id.as_str()) {
                result.push(group_id);
                break;
            }
        }
    }
    serde_json::to_string(&result).map_err(|e| e.to_string())
}

pub fn add_wallet_contact_group_member(wallet_id: String, group_id: String, contact_id: String) -> Result<(), String> {
    api::add_contact_group_member_api(&wallet_id, &group_id, &contact_id)?;
    if let Ok(Some(current)) = storage::config_get("current_wallet_id") {
        if current == wallet_id {
            let _ = sync::invalidate_perms_cache_and_pull(&wallet_id);
        }
    }
    Ok(())
}

pub fn remove_wallet_contact_group_member(wallet_id: String, group_id: String, contact_id: String) -> Result<(), String> {
    api::remove_contact_group_member_api(&wallet_id, &group_id, &contact_id)?;
    if let Ok(Some(current)) = storage::config_get("current_wallet_id") {
        if current == wallet_id {
            let _ = sync::invalidate_perms_cache_and_pull(&wallet_id);
        }
    }
    Ok(())
}

pub fn list_wallet_permission_actions(wallet_id: String) -> Result<String, String> {
    api::list_permission_actions_api(&wallet_id)
}

pub fn get_my_permissions(wallet_id: String) -> Result<String, String> {
    api::get_my_permissions_api(&wallet_id)
}

pub fn clear_wallet_data(wallet_id: String) -> Result<(), String> {
    storage::clear_wallet(&wallet_id)
}

pub fn get_wallet_permission_matrix(wallet_id: String) -> Result<String, String> {
    api::get_permission_matrix_api(&wallet_id)
}

pub fn put_wallet_permission_matrix(wallet_id: String, entries_json: String) -> Result<(), String> {
    api::put_permission_matrix_api(&wallet_id, &entries_json)?;
    if let Ok(Some(current)) = storage::config_get("current_wallet_id") {
        if current == wallet_id {
            let _ = sync::clear_wallet_and_resync(&wallet_id);
        }
    }
    Ok(())
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
/// Sync with server. If server responds with DEBITUM_AUTH_DECLINED, Rust clears session (logout) and returns that error; Dart only needs to react (e.g. show login).
pub fn manual_sync() -> Result<(), String> {
    manual_sync_with_source("ffi")
}

fn manual_sync_with_source(source: &str) -> Result<(), String> {
    {
        let skip = SYNC_BACKOFF.with(|b| {
            let backoff = b.borrow();
            if !backoff.can_attempt() {
                backoff.remaining()
            } else {
                None
            }
        });
        if let Some(wait) = skip {
            if should_log_skip(&LAST_BACKOFF_SKIP_LOG, 1000) {
                rust_log!(
                    "[debitum_rs] manual_sync skipped (backoff active, remaining={}ms, source={})",
                    wait.as_millis(),
                    source
                );
            }
            return Ok(());
        }
    }
    if get_current_wallet_id().is_none() {
        if should_log_skip(&LAST_NO_WALLET_SKIP_LOG, 5000) {
            rust_log!(
                "[debitum_rs] manual_sync skipped (no wallet selected, source={})",
                source
            );
        }
        return Ok(());
    }
    let _guard = match SyncGuard::try_acquire() {
        Some(g) => g,
        None => {
            if should_log_skip(&LAST_INFLIGHT_SKIP_LOG, 1000) {
                rust_log!("[debitum_rs] manual_sync skipped (in-flight, source={})", source);
            }
            return Ok(());
        }
    };

    rust_log!("[debitum_rs] manual_sync start (source={})", source);
    match sync::full_sync() {
        Ok(()) => {
            SYNC_BACKOFF.with(|b| b.borrow_mut().reset());
            rust_log!("[debitum_rs] manual_sync success (source={})", source);
            Ok(())
        }
        Err(e) => {
            if e.contains("DEBITUM_AUTH_DECLINED") {
                let _ = crud::logout();
            }
            if is_network_error(&e) || is_rate_limited(&e) {
                let delay = SYNC_BACKOFF.with(|b| b.borrow_mut().on_failure());
                rust_log!(
                    "[debitum_rs] manual_sync backoff set={}ms (source={})",
                    delay.as_millis(),
                    source
                );
            }
            rust_log!("[debitum_rs] manual_sync failed: {}", e);
            Err(e)
        }
    }
}

fn is_network_error(err: &str) -> bool {
    let s = err.to_lowercase();
    s.contains("error sending request")
        || s.contains("connection refused")
        || s.contains("network is unreachable")
        || s.contains("timed out")
        || s.contains("connection timed out")
        || s.contains("connection reset")
        || s.contains("host is down")
}

fn is_rate_limited(err: &str) -> bool {
    let s = err.to_lowercase();
    s.contains("429") || s.contains("too many requests")
}

/// Drain buffered Rust log lines so Dart can show them (e.g. via debugPrint).
pub fn drain_rust_logs() -> Vec<String> {
    log_bridge::drain_rust_logs()
}

// --- UI preferences (stored in Rust config; Dart only reads/writes via these) ---
const PREF_PREFIX: &str = "pref_";

pub fn get_preference(key: String) -> Option<String> {
    let storage_key = format!("{}{}", PREF_PREFIX, key);
    storage::config_get(&storage_key).ok().and_then(|o| o)
}

pub fn set_preference(key: String, value: String) -> Result<(), String> {
    let storage_key = format!("{}{}", PREF_PREFIX, key);
    storage::config_set(&storage_key, &value)
}

// --- JWT (single place for token parsing; Dart no longer decodes) ---
pub fn get_username() -> Option<String> {
    let token = storage::config_get("token").ok().and_then(|o| o)?;
    if token.is_empty() {
        return None;
    }
    jwt_payload(&token).and_then(|p| p.username)
}

/// True if JWT is expired or invalid. Used to avoid WebSocket 401 spam.
pub fn is_token_expired() -> bool {
    let token = match storage::config_get("token").ok().and_then(|o| o) {
        Some(t) if !t.is_empty() => t,
        _ => return true,
    };
    match jwt_payload(&token) {
        Some(p) => p.expired,
        None => true,
    }
}

#[derive(Default)]
struct JwtPayload {
    username: Option<String>,
    expired: bool,
}

fn jwt_payload(token: &str) -> Option<JwtPayload> {
    use base64::Engine;
    let parts: Vec<&str> = token.splitn(3, '.').collect();
    if parts.len() != 3 {
        return None;
    }
    let payload_b64 = parts[1];
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload_b64.as_bytes())
        .ok()?;
    let payload_str = String::from_utf8(decoded).ok()?;
    let json: serde_json::Value = serde_json::from_str(&payload_str).ok()?;
    let obj = json.as_object()?;
    let username = obj
        .get("username")
        .and_then(|v| v.as_str())
        .map(String::from);
    let expired = obj.get("exp").and_then(|v| v.as_i64()).map_or(true, |exp_sec| {
        chrono::Utc::now().timestamp() >= exp_sec
    });
    Some(JwtPayload { username, expired })
}

// Kept for compatibility
pub fn greet(name: String) -> String {
    format!("Hello, {} from Rust!", name)
}

#[cfg(test)]
mod tests {
    // Storage is process-wide; run with: cargo test --lib -- --test-threads=1
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
