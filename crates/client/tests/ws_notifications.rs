//! Regression test for the WebSocket "events_synced" broadcast path.
//!
//! Bug being captured: in production, when one client creates a
//! transaction, peer clients on the same wallet do not receive a
//! `events_synced` notification through the WebSocket and therefore
//! never trigger a sync. The multi_app_realtime tests prove the
//! plain push/pull works (i.e. an explicit `app2.sync()` does see
//! the new transaction). This test proves the missing piece:
//! does the SERVER actually emit an `events_synced` WS message
//! when a transaction event is appended? If yes, the bug is in the
//! Dart-side WS handler. If no, the bug is server-side.

use futures_util::{SinkExt, StreamExt};
use std::time::Duration;
use tokio::time::timeout;
use tokio_tungstenite::tungstenite::Message;

use crate::common::app_instance::AppInstance;
use crate::common::test_helpers::test_server_url;

fn ws_url_from_base(base: &str) -> String {
    if base.starts_with("https://") {
        base.replacen("https://", "wss://", 1) + "/ws"
    } else {
        base.replacen("http://", "ws://", 1) + "/ws"
    }
}

/// Subscribe to /ws with the given JWT, await an `events_synced`
/// message for at most `wait`. Returns the first matching JSON
/// payload it sees, or an error string.
async fn wait_for_events_synced(
    ws_url: &str,
    token: &str,
    wallet_id: &str,
    wait: Duration,
) -> Result<serde_json::Value, String> {
    let url = format!("{}?token={}&wallet_id={}", ws_url, token, wallet_id);
    let (mut ws, _) = tokio_tungstenite::connect_async(&url)
        .await
        .map_err(|e| format!("ws connect: {e}"))?;

    let result = timeout(wait, async {
        while let Some(msg) = ws.next().await {
            let msg = msg.map_err(|e| format!("ws read: {e}"))?;
            if let Message::Text(text) = msg {
                let v: serde_json::Value = serde_json::from_str(&text)
                    .map_err(|e| format!("ws msg not JSON: {e}; raw={}", text))?;
                if v.get("type").and_then(|t| t.as_str()) == Some("events_synced") {
                    return Ok(v);
                }
                // Ignore other broadcast types (heartbeat etc).
            }
        }
        Err::<serde_json::Value, String>("ws closed before events_synced arrived".to_string())
    })
    .await
    .map_err(|_| format!("timed out after {:?} waiting for events_synced", wait))??;

    let _ = ws.send(Message::Close(None)).await;
    Ok(result)
}

/// Pushing a transaction CREATED event from app1 must cause the server
/// to broadcast `events_synced` on the wallet's WS topic.
#[test]
#[ignore]
fn server_broadcasts_events_synced_when_transaction_created() {
    let server_url = test_server_url();
    let ws_url = ws_url_from_base(&server_url);
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("rt");

    // app1 is the actor; it owns the wallet + creates the transaction.
    let app1 = AppInstance::new("app1", &server_url);
    app1.initialize().expect("initialize app1");
    app1.signup().expect("signup app1");

    let token = client::get_token().expect("token after signup");
    let wallet_id = client::get_current_wallet_id().expect("wallet selected after signup");

    // Background task: subscribe to /ws and watch for events_synced.
    let ws_url_for_task = ws_url.clone();
    let token_for_task = token.clone();
    let wallet_for_task = wallet_id.clone();
    let watcher = std::thread::spawn(move || {
        rt.block_on(wait_for_events_synced(
            &ws_url_for_task,
            &token_for_task,
            &wallet_for_task,
            Duration::from_secs(5),
        ))
    });

    // Give the watcher a moment to actually subscribe before we fire.
    std::thread::sleep(Duration::from_millis(300));

    // Fire the transaction. crud::create_transaction calls
    // push_unsynced inline; the POST /api/sync handler then runs
    // websocket::broadcast_events_synced.
    app1.run_commands(&[
        "contact create \"Alice\" alice",
        "transaction create alice owed 1234 \"a\" t1",
    ])
    .expect("run_commands");

    let received = watcher
        .join()
        .expect("watcher thread join")
        .expect("events_synced must arrive within timeout");

    // Sanity: the broadcast carries something identifying it as the
    // sync trigger (the existing server code passes source="sync").
    let source = received.get("source").and_then(|v| v.as_str()).unwrap_or("");
    assert!(
        source == "sync" || source.is_empty(),
        "unexpected events_synced source: {}",
        source
    );
}
