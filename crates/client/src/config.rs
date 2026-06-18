//! Configuration and initialization: backend URLs, storage, logging context.

use crate::rust_log;
use crate::storage;
use once_cell::sync::Lazy;
use std::cell::RefCell;
use std::sync::Mutex;

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

// Thread-local: per-thread tag for multi-app integration tests.
thread_local! {
    static LOG_CONTEXT: RefCell<Option<String>> = RefCell::new(None);
}

/// Call once at startup with the app documents directory path (e.g. from path_provider).
/// Storage is process-wide; no need to call again from every thread.
pub fn init_storage(storage_path: String) -> Result<(), String> {
    let was_ready = storage::is_ready();
    storage::init(&storage_path)?;
    if !was_ready {
        rust_log!("[debitum_rs] sync loop: storage ready");
        crate::sync_control::start_sync_loop_if_ready();
    }
    Ok(())
}

pub fn set_backend_config(base_url: String, ws_url: String) {
    let already_same = get_base_url().as_deref() == Ok(base_url.as_str())
        && get_ws_url().as_deref() == Ok(ws_url.as_str());
    if already_same {
        return;
    }
    let cfg = BackendConfig { base_url, ws_url };
    BACKEND_CONFIG.with(|cell| {
        *cell.borrow_mut() = Some(BackendConfig {
            base_url: cfg.base_url.clone(),
            ws_url: cfg.ws_url.clone(),
        })
    });
    *BACKEND_CONFIG_GLOBAL.lock().unwrap() = Some(cfg);
    rust_log!("[debitum_rs] sync loop: backend config set");
    crate::sync_control::start_sync_loop_if_ready();
}

pub fn get_base_url() -> Result<String, String> {
    BACKEND_CONFIG
        .with(|cell| cell.borrow().as_ref().map(|c| c.base_url.clone()))
        .or_else(|| {
            BACKEND_CONFIG_GLOBAL
                .lock()
                .unwrap()
                .as_ref()
                .map(|c| c.base_url.clone())
        })
        .ok_or_else(|| "Backend not configured".to_string())
}

pub fn get_ws_url() -> Result<String, String> {
    BACKEND_CONFIG
        .with(|cell| cell.borrow().as_ref().map(|c| c.ws_url.clone()))
        .or_else(|| {
            BACKEND_CONFIG_GLOBAL
                .lock()
                .unwrap()
                .as_ref()
                .map(|c| c.ws_url.clone())
        })
        .ok_or_else(|| "Backend not configured".to_string())
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

/// Set or clear a per-thread log tag. When set, the multi-app log viewer can
/// distinguish which simulated app produced each log line. Stub today — the
/// log_bridge doesn't yet prepend it — but exposing the API unblocks the
/// integration test setup (`AppInstance::activate`) that calls it on every
/// app switch. If/when we want per-app prefixes, log_bridge::push can read
/// LOG_CONTEXT and prepend it.
pub fn set_log_context(ctx: String) {
    LOG_CONTEXT.with(|cell| {
        *cell.borrow_mut() = if ctx.is_empty() { None } else { Some(ctx) };
    });
}

/// Read the current per-thread log tag. Empty string if not set.
pub fn log_context() -> String {
    LOG_CONTEXT.with(|cell| cell.borrow().clone().unwrap_or_default())
}

pub(crate) fn get_backend_config() -> Option<String> {
    BACKEND_CONFIG.with(|cell| cell.borrow().as_ref().map(|c| c.base_url.clone()))
}
