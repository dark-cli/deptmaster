use crate::database::repository::{Database, DatabaseRepository};
use crate::middleware::auth::Claims;
use crate::AppState;
use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::Json,
    Extension,
};
use bcrypt::{hash, verify, DEFAULT_COST};
use chrono::{Duration, Utc};
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    /// Short-lived JWT used as the Bearer token on every API call.
    /// Lifetime is `Config::jwt_expiration` (default 15 minutes). Once it
    /// expires the client trades `refresh_token` at `/api/auth/refresh`
    /// for a new pair rather than asking the user to log in again.
    pub token: String,
    /// Long-lived opaque token (rotated on every refresh, see
    /// [`crate::database::repository::refresh_tokens`]). The raw value
    /// is only ever shown here — at rest we keep just a SHA-256 hash.
    pub refresh_token: String,
    pub user_id: String,
    pub username: String,
}

#[derive(Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Deserialize)]
pub struct LogoutRequest {
    /// Optional: the refresh token belonging to *this* device. If
    /// present and it belongs to the authenticated user, the server
    /// revokes that row so a stolen copy cannot be used after logout.
    /// If absent (or invalid) logout still succeeds — the access
    /// token expires in minutes anyway, so worst-case the leaked
    /// refresh keeps working for its full lifetime.
    pub refresh_token: Option<String>,
}

// Generate JWT token
fn generate_jwt_token(
    user_id: &Uuid,
    username: &str,
    secret: &str,
    expiration_secs: u64,
) -> Result<String, jsonwebtoken::errors::Error> {
    let exp = (Utc::now() + Duration::seconds(expiration_secs as i64)).timestamp() as usize;
    let claims = Claims {
        user_id: user_id.to_string(),
        username: username.to_string(),
        exp,
    };

    let header = Header::new(Algorithm::HS256);
    let encoding_key = EncodingKey::from_secret(secret.as_ref());
    encode(&header, &claims, &encoding_key)
}

// Helper function to extract IP address from headers
fn extract_ip_address(headers: &HeaderMap) -> String {
    // Try X-Forwarded-For first (for reverse proxy)
    if let Some(forwarded_for) = headers.get("x-forwarded-for") {
        if let Ok(ip) = forwarded_for.to_str() {
            // Take the first IP if there are multiple
            return ip.split(',').next().unwrap_or("unknown").trim().to_string();
        }
    }

    // Try X-Real-IP
    if let Some(real_ip) = headers.get("x-real-ip") {
        if let Ok(ip) = real_ip.to_str() {
            return ip.to_string();
        }
    }

    "unknown".to_string()
}

// Helper function to extract user agent from headers
fn extract_user_agent(headers: &HeaderMap) -> String {
    if let Some(user_agent) = headers.get("user-agent") {
        if let Ok(ua) = user_agent.to_str() {
            return ua.to_string();
        }
    }

    "unknown".to_string()
}

pub async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<LoginRequest>,
) -> Result<(StatusCode, Json<AuthResponse>), (StatusCode, Json<serde_json::Value>)> {
    // Validate input
    if payload.username.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Username is required"})),
        ));
    }
    if payload.password.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Password is required"})),
        ));
    }

    let db = Database::new((*state.db_pool).clone());
    let username = payload.username.trim();
    let ip_address = extract_ip_address(&headers);
    let user_agent = extract_user_agent(&headers);

    // Find user by username
    let user = db.get_user_by_username(username).await.map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let user = match user {
        Some(u) => u,
        None => {
            let _ = db
                .insert_login_log(
                    None,
                    &ip_address,
                    &user_agent,
                    false,
                    Some("user_not_found"),
                )
                .await;

            return Err((
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "code": "DEBITUM_AUTH_DECLINED",
                    "message": "Invalid username or password"
                })),
            ));
        }
    };

    // Verify password
    let valid = verify(&payload.password, &user.password_hash).map_err(|e| {
        tracing::error!("Error verifying password: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Authentication error"})),
        )
    })?;

    if !valid {
        let _ = db
            .insert_login_log(
                Some(user.id),
                &ip_address,
                &user_agent,
                false,
                Some("invalid_password"),
            )
            .await;

        return Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "code": "DEBITUM_AUTH_DECLINED",
                "message": "Invalid username or password"
            })),
        ));
    }

    let _ = db
        .insert_login_log(Some(user.id), &ip_address, &user_agent, true, None)
        .await;

    // Generate JWT token
    let token = generate_jwt_token(
        &user.id,
        &user.username,
        &state.config.jwt_secret,
        state.config.jwt_expiration,
    )
    .map_err(|e| {
        tracing::error!("Error generating JWT: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to generate token"})),
        )
    })?;

    let refresh = db
        .mint_refresh_token(user.id, state.config.refresh_token_expiration)
        .await
        .map_err(|e| {
            tracing::error!("Error minting refresh token: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to generate token"})),
            )
        })?;

    Ok((
        StatusCode::OK,
        Json(AuthResponse {
            token,
            refresh_token: refresh.raw,
            user_id: user.id.to_string(),
            username: user.username,
        }),
    ))
}

/// Public registration: create account and return auth (auto sign-in).
pub async fn register(
    State(state): State<AppState>,
    Json(payload): Json<RegisterRequest>,
) -> Result<(StatusCode, Json<AuthResponse>), (StatusCode, Json<serde_json::Value>)> {
    let username = payload.username.trim();
    if username.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Username is required"})),
        ));
    }
    if payload.password.len() < 8 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Password must be at least 8 characters"})),
        ));
    }

    let db = Database::new((*state.db_pool).clone());

    // Check if user exists
    let existing = db
        .get_user_by_username(username)
        .await
        .map_err(|e| {
            tracing::error!("register: check existing: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?
        .is_some();

    if existing {
        return Err((
            StatusCode::CONFLICT,
            Json(serde_json::json!({"error": "This username is already taken"})),
        ));
    }

    let password_hash = hash(&payload.password, DEFAULT_COST).map_err(|e| {
        tracing::error!("register: hash: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create account"})),
        )
    })?;

    let user_id = Uuid::new_v4();

    db.create_user(user_id, username.to_string(), password_hash)
        .await
        .map_err(|e| {
            tracing::error!("register: insert: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to create account"})),
            )
        })?;

    let token = generate_jwt_token(
        &user_id,
        username,
        &state.config.jwt_secret,
        state.config.jwt_expiration,
    )
    .map_err(|e| {
        tracing::error!("register: jwt: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create account"})),
        )
    })?;

    let refresh = db
        .mint_refresh_token(user_id, state.config.refresh_token_expiration)
        .await
        .map_err(|e| {
            tracing::error!("register: refresh mint: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to create account"})),
            )
        })?;

    Ok((
        StatusCode::CREATED,
        Json(AuthResponse {
            token,
            refresh_token: refresh.raw,
            user_id: user_id.to_string(),
            username: username.to_string(),
        }),
    ))
}

/// `POST /api/auth/refresh` — trade a valid refresh token for a fresh
/// access+refresh pair. This is the *only* mechanism the client should
/// use to stay logged in beyond the JWT lifetime; never extend or
/// re-issue access tokens server-side.
///
/// Three terminal states:
/// - **Unknown token**: 401. (No log noise; could be a probe.)
/// - **Already redeemed** (revoked + replaced): treat as theft. Revoke
///   every refresh token this user owns and return 401. Both the
///   attacker and the legitimate client will be forced to log in
///   again, which is the desired blast radius.
/// - **Expired or plain-revoked**: 401. Just a stale session.
///
/// Success path: atomically mark the old token revoked, mint a new
/// one, and return a new JWT + the new refresh token.
pub async fn refresh(
    State(state): State<AppState>,
    Json(payload): Json<RefreshRequest>,
) -> Result<(StatusCode, Json<AuthResponse>), (StatusCode, Json<serde_json::Value>)> {
    let db = Database::new((*state.db_pool).clone());

    let raw = payload.refresh_token.trim();
    if raw.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "refresh_token is required"})),
        ));
    }

    let stored = db.find_refresh_token_by_raw(raw).await.map_err(|e| {
        tracing::error!("refresh: lookup: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let stored = match stored {
        Some(s) => s,
        None => {
            return Err((
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "code": "DEBITUM_REFRESH_INVALID",
                    "message": "Unknown refresh token"
                })),
            ));
        }
    };

    if stored.was_already_redeemed() {
        // Token theft signal: the legitimate redemption already
        // happened (revoked_at + replaced_by_id are set) yet someone
        // is presenting the original again. Wipe all sessions for
        // this user so both copies of the stolen chain die.
        tracing::warn!(
            "refresh: token reuse detected for user {} — revoking all sessions",
            stored.user_id
        );
        let _ = db.revoke_all_refresh_tokens_for_user(stored.user_id).await;
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "code": "DEBITUM_REFRESH_REUSED",
                "message": "Refresh token has already been used; please sign in again"
            })),
        ));
    }

    if !stored.is_redeemable() {
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "code": "DEBITUM_REFRESH_EXPIRED",
                "message": "Refresh token expired or revoked; please sign in again"
            })),
        ));
    }

    // Load user for the new JWT's username claim.
    let user = db.get_user_by_id(stored.user_id).await.map_err(|e| {
        tracing::error!("refresh: get_user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;
    let user = match user {
        Some(u) => u,
        None => {
            // User row vanished out from under a still-valid refresh
            // token (manual delete?). Revoke the chain and bail.
            let _ = db.revoke_all_refresh_tokens_for_user(stored.user_id).await;
            return Err((
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "code": "DEBITUM_REFRESH_INVALID",
                    "message": "Account no longer exists"
                })),
            ));
        }
    };

    let new_refresh = db
        .rotate_refresh_token(
            stored.id,
            stored.user_id,
            state.config.refresh_token_expiration,
        )
        .await
        .map_err(|e| {
            tracing::error!("refresh: rotate: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to rotate token"})),
            )
        })?;

    let token = generate_jwt_token(
        &user.id,
        &user.username,
        &state.config.jwt_secret,
        state.config.jwt_expiration,
    )
    .map_err(|e| {
        tracing::error!("refresh: jwt: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to generate token"})),
        )
    })?;

    Ok((
        StatusCode::OK,
        Json(AuthResponse {
            token,
            refresh_token: new_refresh.raw,
            user_id: user.id.to_string(),
            username: user.username,
        }),
    ))
}

/// `POST /api/auth/logout` — revoke the refresh token for *this*
/// device so a leaked copy stops working immediately, instead of
/// living until its 30-day expiry. Best-effort and idempotent:
/// missing/foreign/already-revoked tokens still return 200, because
/// the client is going to wipe local storage either way and we don't
/// want a stuck logout button. Other devices' refresh tokens are
/// untouched — single-device logout, not "log out everywhere."
pub async fn logout(
    State(state): State<AppState>,
    Extension(auth_user): Extension<crate::middleware::auth::AuthUser>,
    Json(payload): Json<LogoutRequest>,
) -> (StatusCode, Json<serde_json::Value>) {
    let db = Database::new((*state.db_pool).clone());
    if let Some(raw) = payload.refresh_token.as_deref() {
        let raw = raw.trim();
        if !raw.is_empty() {
            // Ownership check: only let the authenticated user revoke
            // their own row. Without this an attacker with any valid
            // access token could log other users out by guessing or
            // replaying their refresh tokens.
            if let Ok(Some(stored)) = db.find_refresh_token_by_raw(raw).await {
                if stored.user_id == auth_user.user_id {
                    let _ = db.revoke_refresh_token(stored.id).await;
                }
            }
        }
    }
    (StatusCode::OK, Json(serde_json::json!({"ok": true})))
}
