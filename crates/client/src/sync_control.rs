//! Sync orchestration: backoff, guards, and sync entry points.

use crate::{config, rust_log, services, storage};
use once_cell::sync::Lazy;
use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

// Thread-local so parallel integration tests (each on their own thread) don't block each other's sync.
thread_local! {
    static SYNC_BACKOFF: RefCell<crate::backoff::Backoff> = RefCell::new(crate::backoff::Backoff::new(vec![
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

// PROCESS-WIDE (not thread-local) — the WS worker spawns a fresh
// std::thread per events_synced message, so each spawn would get a
// fresh thread-local "not in flight" and bypass the guard entirely.
// pull_and_merge then runs in parallel, racing on storage writes
// (last_sync_timestamp + server_hash) and producing stale state for
// the next sync to mis-diagnose as hash-divergence → wipe.
static SYNC_IN_FLIGHT: AtomicBool = AtomicBool::new(false);
static SYNC_LOOP_STARTED: AtomicBool = AtomicBool::new(false);
static LAST_BACKOFF_SKIP_LOG: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));
static LAST_INFLIGHT_SKIP_LOG: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));
static LAST_NO_WALLET_SKIP_LOG: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));

#[flutter_rust_bridge::frb(opaque)]
struct SyncGuard;

impl SyncGuard {
    fn try_acquire() -> Option<Self> {
        // compare_exchange: only the first caller wins; subsequent
        // calls see `true` and return None until the holder drops.
        match SYNC_IN_FLIGHT.compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire) {
            Ok(_) => Some(Self),
            Err(_) => None,
        }
    }
}

impl Drop for SyncGuard {
    fn drop(&mut self) {
        SYNC_IN_FLIGHT.store(false, Ordering::Release);
    }
}

/// Sync is driven by WS notification (client pulls when server pushes). No background polling.
/// Set to true only to re-enable a fallback sync loop (interval ~1s).
const BACKGROUND_SYNC_LOOP_ENABLED: bool = false;

pub(crate) fn start_sync_loop_if_ready() {
    if !BACKGROUND_SYNC_LOOP_ENABLED {
        return;
    }
    if !storage::is_ready() {
        return;
    }
    let backend_ready = config::get_backend_config().is_some();
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
            if storage::is_ready() && config::get_backend_config().is_some() {
                let _ = manual_sync_with_source("background_loop");
            }
            let delay_ms = SYNC_BACKOFF.with(|b| {
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

/// Sync with server. If server responds with DEBITUM_AUTH_DECLINED, Rust clears session (logout) and returns that error; Dart only needs to react (e.g. show login).
pub fn manual_sync() -> Result<(), String> {
    manual_sync_with_source("ffi")
}

pub(crate) fn manual_sync_with_source(source: &str) -> Result<(), String> {
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
    if crate::get_current_wallet_id().is_err() {
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
                rust_log!(
                    "[debitum_rs] manual_sync skipped (in-flight, source={})",
                    source
                );
            }
            return Ok(());
        }
    };

    rust_log!("[debitum_rs] manual_sync start (source={})", source);
    match services::sync::full_sync() {
        Ok(()) => {
            SYNC_BACKOFF.with(|b| b.borrow_mut().reset());
            rust_log!("[debitum_rs] manual_sync success (source={})", source);
            Ok(())
        }
        Err(e) => {
            if e.contains("DEBITUM_AUTH_DECLINED") {
                let _ = services::crud::logout();
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
