use crate::middleware::auth::Claims;
use crate::AppState;
use axum::{
    extract::{
        ws::{Message, WebSocket},
        Query, State, WebSocketUpgrade,
    },
    http::{header::AUTHORIZATION, StatusCode},
    response::Response,
};
use futures_util::{SinkExt, StreamExt};
use jsonwebtoken::{decode, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use std::collections::HashSet;
use tokio::sync::broadcast;
use uuid::Uuid;

/// Wallet-scoped broadcast channel.
/// The first element is the wallet_id the message is for.
pub type BroadcastChannel = broadcast::Sender<(Uuid, String)>; // (wallet_id, message)

#[derive(Deserialize)]
pub struct WebSocketQuery {
    token: Option<String>,
    wallet_id: Option<String>,
}

pub fn create_broadcast_channel() -> BroadcastChannel {
    broadcast::channel(100).0
}

pub async fn websocket_handler(
    ws: WebSocketUpgrade,
    Query(query): Query<WebSocketQuery>,
    State(state): State<AppState>,
    headers: axum::http::HeaderMap,
) -> Result<Response, StatusCode> {
    // Extract token from query parameter or Authorization header
    let token = query.token.or_else(|| {
        headers
            .get(AUTHORIZATION)
            .and_then(|h| h.to_str().ok())
            .map(|s| s.strip_prefix("Bearer ").unwrap_or(s).to_string())
    });

    let token = token.ok_or_else(|| {
        tracing::warn!("WebSocket connection attempt without token");
        StatusCode::UNAUTHORIZED
    })?;

    // Validate JWT token
    let decoding_key = DecodingKey::from_secret(state.config.jwt_secret.as_ref());
    let validation = Validation::new(Algorithm::HS256);

    let token_data = decode::<Claims>(&token, &decoding_key, &validation).map_err(|e| {
        tracing::warn!("WebSocket token validation failed: {:?}", e);
        StatusCode::UNAUTHORIZED
    })?;

    let claims = token_data.claims;
    let user_id = Uuid::parse_str(&claims.user_id).map_err(|e| {
        tracing::warn!("WebSocket invalid user_id in token: {:?}", e);
        StatusCode::UNAUTHORIZED
    })?;

    // Determine if user is admin or regular user
    let is_admin = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM admin_users WHERE id = $1 AND is_active = true)",
    )
    .bind(user_id)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("WebSocket database error checking admin: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let is_regular_user = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users_projection WHERE id = $1)",
    )
    .bind(user_id)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("WebSocket database error checking user: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    if !is_admin && !is_regular_user {
        tracing::warn!("WebSocket connection attempt for invalid user: {}", user_id);
        return Err(StatusCode::UNAUTHORIZED);
    }

    tracing::info!("WebSocket connection authenticated for user: {} (admin={})", user_id, is_admin);

    // Load accessible wallets based on user type
    let allowed_wallet_ids: HashSet<Uuid> = if is_admin {
        // Admins can access all wallets
        sqlx::query_scalar::<_, Uuid>("SELECT id FROM wallets WHERE deleted_at IS NULL")
            .fetch_all(&*state.db_pool)
            .await
            .map_err(|e| {
                tracing::error!("WebSocket database error loading wallets for admin: {:?}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?
            .into_iter()
            .collect()
    } else {
        // Regular users can only access their own wallets
        sqlx::query_scalar::<_, Uuid>("SELECT wallet_id FROM wallet_users WHERE user_id = $1")
            .bind(user_id)
            .fetch_all(&*state.db_pool)
            .await
            .map_err(|e| {
                tracing::error!("WebSocket database error loading user wallets: {:?}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?
            .into_iter()
            .collect()
    };

    // Determine active wallet(s) to subscribe to
    let active_wallet_ids: HashSet<Uuid> = if is_admin {
        // Admins receive updates for all wallets they can access
        allowed_wallet_ids.clone()
    } else {
        // Regular users must specify exactly one wallet
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
