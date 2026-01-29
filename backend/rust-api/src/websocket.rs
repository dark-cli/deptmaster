use axum::{
    extract::{
        ws::{Message, WebSocket},
        Query, State, WebSocketUpgrade,
    },
    http::{header::AUTHORIZATION, StatusCode},
    response::Response,
};
use futures_util::{SinkExt, StreamExt};
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};
use serde::Deserialize;
use tokio::sync::broadcast;
use uuid::Uuid;
use crate::AppState;
use crate::middleware::auth::Claims;

pub type BroadcastChannel = broadcast::Sender<(Uuid, String)>; // (user_id, message)

#[derive(Deserialize)]
pub struct WebSocketQuery {
    token: Option<String>,
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

    let token_data = decode::<Claims>(&token, &decoding_key, &validation)
        .map_err(|e| {
            tracing::warn!("WebSocket token validation failed: {:?}", e);
            StatusCode::UNAUTHORIZED
        })?;

    let claims = token_data.claims;
    let user_id = Uuid::parse_str(&claims.user_id)
        .map_err(|e| {
            tracing::warn!("WebSocket invalid user_id in token: {:?}", e);
            StatusCode::UNAUTHORIZED
        })?;

    // Verify user exists in either users_projection or admin_users
    let user_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users_projection WHERE id = $1) OR EXISTS(SELECT 1 FROM admin_users WHERE id = $1 AND is_active = true)"
    )
    .bind(user_id)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("WebSocket database error checking user: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    if !user_exists {
        tracing::warn!("WebSocket connection attempt for non-existent user: {}", user_id);
        return Err(StatusCode::UNAUTHORIZED);
    }
    
    tracing::info!("WebSocket connection authenticated for user: {}", user_id);

    Ok(ws.on_upgrade(move |socket| handle_socket(socket, state, user_id)))
}

async fn handle_socket(socket: WebSocket, state: AppState, user_id: Uuid) {
    let (mut sender, mut receiver) = socket.split();
    let mut rx = state.broadcast_tx.subscribe();

    // Spawn task to send messages from broadcast channel to client
    // Only send messages intended for this user
    let mut send_task = tokio::spawn(async move {
        while let Ok((target_user_id, msg)) = rx.recv().await {
            // Only send if message is for this user or broadcast (user_id is NULL/UUID::nil)
            if target_user_id == user_id || target_user_id == Uuid::nil() {
                if sender.send(Message::Text(msg)).await.is_err() {
                    break;
                }
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

// Broadcast to all users (user_id = nil)
pub fn broadcast_change(channel: &BroadcastChannel, event_type: &str, data: &str) {
    broadcast_to_user(channel, None, event_type, data);
}

// Broadcast to specific user or all users if user_id is None
pub fn broadcast_to_user(channel: &BroadcastChannel, user_id: Option<Uuid>, event_type: &str, data: &str) {
    let message = format!(r#"{{"type":"{}","data":{}}}"#, event_type, data);
    let target_user_id = user_id.unwrap_or(Uuid::nil());
    let _ = channel.send((target_user_id, message));
}
