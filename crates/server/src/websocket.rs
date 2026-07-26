use crate::database::repository::{Database, DatabaseRepository};
use crate::middleware::auth::AuthUser;
use crate::AppState;
use axum::{
    extract::{
        ws::{Message, WebSocket},
        Extension, Query, State, WebSocketUpgrade,
    },
    http::StatusCode,
    response::Response,
};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use std::collections::HashSet;
use tokio::sync::broadcast;
use uuid::Uuid;

/// Wallet-scoped broadcast channel.
/// The first element is the wallet_id the message is for.
pub type BroadcastChannel = broadcast::Sender<(Uuid, String)>; // (wallet_id, message)

#[derive(Deserialize)]
pub struct WebSocketQuery {
    wallet_id: Option<String>,
}

pub fn create_broadcast_channel() -> BroadcastChannel {
    broadcast::channel(100).0
}

pub async fn websocket_handler(
    ws: WebSocketUpgrade,
    Query(query): Query<WebSocketQuery>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Response, StatusCode> {
    let user_id = auth_user.user_id;
    let is_admin = auth_user.is_admin;

    let db = Database::new((*state.db_pool).clone());

    tracing::info!("WebSocket connection authenticated for user: {} (admin={})", user_id, is_admin);

    // Load accessible wallets based on user type
    let allowed_wallet_ids: HashSet<Uuid> = if is_admin {
        db.get_all_active_wallets()
            .await
            .map_err(|e| {
                tracing::error!("WebSocket database error loading wallets for admin: {:?}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?
            .into_iter()
            .map(|w| w.id)
            .collect()
    } else {
        db.get_user_wallets(user_id)
            .await
            .map_err(|e| {
                tracing::error!("WebSocket database error loading user wallets: {:?}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?
            .into_iter()
            .map(|w| w.id)
            .collect()
    };

    // Determine active wallet(s) to subscribe to
    let active_wallet_ids: HashSet<Uuid> = if is_admin {
        allowed_wallet_ids.clone()
    } else {
        match query.wallet_id.as_deref() {
            None => {
                tracing::warn!(
                    "WebSocket connection attempt without wallet_id (user={})",
                    user_id
                );
                return Err(StatusCode::BAD_REQUEST);
            }
            Some(s) if s.trim().is_empty() => {
                tracing::warn!(
                    "WebSocket connection attempt with empty wallet_id (user={})",
                    user_id
                );
                return Err(StatusCode::BAD_REQUEST);
            }
            Some(s) => {
                let parsed = Uuid::parse_str(s).map_err(|_| {
                    tracing::warn!("WebSocket invalid wallet_id in query: {}", s);
                    StatusCode::BAD_REQUEST
                })?;
                if !allowed_wallet_ids.contains(&parsed) {
                    tracing::warn!(
                        "WebSocket user {} tried to subscribe to wallet {} without access",
                        user_id,
                        parsed
                    );
                    return Err(StatusCode::FORBIDDEN);
                }
                std::iter::once(parsed).collect()
            }
        }
    };

    Ok(ws.on_upgrade(move |socket| {
        handle_socket(socket, state, allowed_wallet_ids, active_wallet_ids)
    }))
}

async fn handle_socket(
    socket: WebSocket,
    state: AppState,
    allowed_wallet_ids: HashSet<Uuid>,
    active_wallet_ids: HashSet<Uuid>,
) {
    let (mut sender, mut receiver) = socket.split();
    let mut rx = state.broadcast_tx.subscribe();

    // Spawn task to send messages from broadcast channel to client
    let mut send_task = tokio::spawn(async move {
        while let Ok((wallet_id, msg)) = rx.recv().await {
            // Filter: only send messages for wallets the client is subscribed to
            if !active_wallet_ids.contains(&wallet_id) {
                continue;
            }
            // Safety: wallet must still be in allowed list
            if !allowed_wallet_ids.contains(&wallet_id) {
                continue;
            }
            if sender.send(Message::Text(msg)).await.is_err() {
                break;
            }
        }
    });

    // Spawn task to receive messages from client (for ping/pong)
    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            if let Message::Close(_) = msg {
                break;
            }
        }
    });

    // Wait for either task to complete
    tokio::select! {
        _ = (&mut send_task) => recv_task.abort(),
        _ = (&mut recv_task) => send_task.abort(),
    };
}

/// Broadcast a realtime message scoped to a specific wallet.
///
/// Only websocket connections belonging to users that are members of `wallet_id` will receive it.
pub fn broadcast_wallet_change(
    channel: &BroadcastChannel,
    wallet_id: Uuid,
    event_type: &str,
    data: &str,
) {
    let message = format!(
        r#"{{"type":"{}","wallet_id":"{}","data":{}}}"#,
        event_type, wallet_id, data
    );
    let _ = channel.send((wallet_id, message));
}

/// Canonical refresh notification for any event (contact, transaction, permission, or future types).
/// Call this whenever an event is written so clients run manualSync and see up-to-date data.
/// - Events that go through `apply_single_event_to_projections` get this automatically.
/// - For handlers that write events directly (e.g. contact/transaction API), call this after the write.
pub fn broadcast_events_synced(channel: &BroadcastChannel, wallet_id: Uuid, source: &str) {
    let data = serde_json::json!({ "source": source }).to_string();
    broadcast_wallet_change(channel, wallet_id, "events_synced", &data);
}
