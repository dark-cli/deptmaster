//! Realtime WebSocket worker.
//!
//! Subscribes to the server's `/ws` topic for the current wallet,
//! listens for `events_synced` pushes, and triggers an internal
//! [`crate::manual_sync`] whenever one arrives. This replaces the
//! Dart-side WebSocket handling in `mobile/lib/api.dart` per the
//! dart-is-ui-only rule: Dart's `Api.connectRealtime()` is now a
//! thin FFI passthrough to [`connect_realtime`].
//!
//! Lifecycle:
//! - `connect_realtime` spawns a single worker thread that owns its
//!   own current-thread tokio runtime and the WS connection.
//! - The worker auto-reconnects every 2 s on lost connection, every
//!   5 s on connect failure.
//! - `disconnect_realtime` signals the worker to exit cleanly.
//! - Calling `connect_realtime` again when one is already running
//!   is a no-op; calling `disconnect_realtime` when none is running
//!   is a no-op.

use std::sync::Arc;
use std::sync::Mutex;
use std::time::Duration;

use futures_util::StreamExt;
use once_cell::sync::Lazy;
use tokio::sync::Notify;
use tokio_tungstenite::tungstenite::Message;

use crate::rust_log;

/// `Some(Notify)` while a worker is running. `disconnect_realtime`
/// takes() and signals; the worker observes the notify and exits.
static CANCEL: Lazy<Mutex<Option<Arc<Notify>>>> = Lazy::new(|| Mutex::new(None));

/// Start the realtime WS worker. Picks up token + wallet + ws_url
/// from the client state at call time. Idempotent — if a worker is
/// already running, returns `Ok(())` and does nothing.
pub fn connect_realtime() -> Result<(), String> {
    rust_log!("[debitum_rs] connect_realtime called");
    {
        if CANCEL.lock().unwrap().is_some() {
            rust_log!("[debitum_rs] connect_realtime: already running");
            return Ok(()); // already running
        }
    }

    let token = crate::get_token()
        .map_err(|e| { rust_log!("[debitum_rs] connect_realtime: no token: {}", e); e })?;
    let wallet_id = crate::get_current_wallet_id()
        .map_err(|e| { rust_log!("[debitum_rs] connect_realtime: no wallet: {}", e); e })?;
    let ws_url = crate::get_ws_url()
        .map_err(|e| { rust_log!("[debitum_rs] connect_realtime: no ws_url: {}", e); e })?;

    let cancel = Arc::new(Notify::new());
    *CANCEL.lock().unwrap() = Some(cancel.clone());
    rust_log!("[debitum_rs] connect_realtime spawning worker (wallet={})", wallet_id);

    std::thread::spawn(move || {
        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                rust_log!("[debitum_rs] ws runtime build failed: {:?}", e);
                *CANCEL.lock().unwrap() = None;
                return;
            }
        };
        rt.block_on(ws_loop(token, wallet_id, ws_url, cancel));
        *CANCEL.lock().unwrap() = None;
    });
    Ok(())
}

/// Stop the realtime WS worker. Idempotent.
pub fn disconnect_realtime() -> Result<(), String> {
    if let Some(cancel) = CANCEL.lock().unwrap().take() {
        cancel.notify_waiters();
    }
    Ok(())
}

async fn ws_loop(token: String, wallet_id: String, ws_url: String, cancel: Arc<Notify>) {
    loop {
        // Did we get cancelled between iterations? Check before
        // burning a connect attempt.
        if check_cancel(&cancel) {
            return;
        }

        let url = format!("{}?token={}&wallet_id={}", ws_url, token, wallet_id);
        rust_log!("[debitum_rs] ws connecting wallet_id={}", wallet_id);

        let (mut ws, _) = match tokio_tungstenite::connect_async(&url).await {
            Ok(c) => c,
            Err(e) => {
                rust_log!("[debitum_rs] ws connect failed: {}; retrying in 5s", e);
                if wait_or_cancel(&cancel, Duration::from_secs(5)).await {
                    return;
                }
                continue;
            }
        };
        rust_log!("[debitum_rs] ws connected");

        loop {
            tokio::select! {
                _ = cancel.notified() => {
                    rust_log!("[debitum_rs] ws cancelled, closing");
                    let _ = ws.close(None).await;
                    return;
                }
                msg = ws.next() => match msg {
                    Some(Ok(Message::Text(text))) => {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                            let kind = v.get("type").and_then(|t| t.as_str()).unwrap_or("");
                            if kind == "events_synced" {
                                rust_log!("[debitum_rs] ws got events_synced, syncing");
                                // manual_sync calls the api.rs static
                                // multi-thread RUNTIME.block_on, which
                                // panics if invoked from inside another
                                // runtime (this WS loop runs in one).
                                // Detach to a fresh OS thread that has no
                                // tokio context.
                                std::thread::spawn(|| {
                                    if let Err(e) = crate::manual_sync() {
                                        rust_log!("[debitum_rs] ws-triggered sync failed: {}", e);
                                    }
                                });
                            }
                            // Other broadcast types (heartbeats etc) are ignored.
                        }
                    }
                    Some(Ok(Message::Ping(_) | Message::Pong(_) | Message::Binary(_) | Message::Frame(_))) => {
                        // Library handles ping/pong internally; nothing for us.
                    }
                    Some(Ok(Message::Close(_))) | None => {
                        rust_log!("[debitum_rs] ws closed by peer");
                        break;
                    }
                    Some(Err(e)) => {
                        rust_log!("[debitum_rs] ws read error: {}", e);
                        break;
                    }
                }
            }
        }

        rust_log!("[debitum_rs] ws disconnected; reconnecting in 2s");
        if wait_or_cancel(&cancel, Duration::from_secs(2)).await {
            return;
        }
    }
}

/// Wait for `dur` OR a cancel signal. Returns `true` if cancelled.
async fn wait_or_cancel(cancel: &Arc<Notify>, dur: Duration) -> bool {
    tokio::select! {
        _ = cancel.notified() => true,
        _ = tokio::time::sleep(dur) => false,
    }
}

/// Non-blocking check: have we been cancelled? Useful between
/// reconnect iterations.
fn check_cancel(cancel: &Arc<Notify>) -> bool {
    // `Notify::notified()` requires await; a quick poll would need
    // a runtime. Easier: rely on wait_or_cancel for sleeps and the
    // select! arm in the read loop. This helper is here for
    // documentation symmetry — currently a no-op.
    let _ = cancel;
    false
}
