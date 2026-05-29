use axum::{
    extract::State,
    http::{StatusCode, HeaderMap},
    response::Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use bcrypt::{hash, verify, DEFAULT_COST};
use jsonwebtoken::{encode, EncodingKey, Header, Algorithm};
use chrono::{Utc, Duration};
use crate::AppState;
use crate::middleware::auth::Claims;
use crate::database::repository::{DatabaseRepository, Database};

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
    pub token: String,
    pub user_id: String,
    pub username: String,
}


// Generate JWT token
fn generate_jwt_token(user_id: &Uuid, username: &str, secret: &str, expiration_secs: u64) -> Result<String, jsonwebtoken::errors::Error> {
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
    let user = db.get_user_by_username(username)
        .await
        .map_err(|e| {
            tracing::error!("Error fetching user: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?;

    let user = match user {
        Some(u) => u,
        None => {
            let _ = db.insert_login_log(
                None,
                &ip_address,
                &user_agent,
                false,
                Some("user_not_found"),
            ).await;

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
    let valid = verify(&payload.password, &user.password_hash)
        .map_err(|e| {
            tracing::error!("Error verifying password: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Authentication error"})),
            )
        })?;

    if !valid {
        let _ = db.insert_login_log(
            Some(user.id),
            &ip_address,
            &user_agent,
            false,
            Some("invalid_password"),
        ).await;

        return Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "code": "DEBITUM_AUTH_DECLINED",
                "message": "Invalid username or password"
            })),
        ));
    }

    let _ = db.insert_login_log(
        Some(user.id),
        &ip_address,
        &user_agent,
        true,
        None,
    ).await;

    // Generate JWT token
    let username = user.username.as_deref().unwrap_or(&user.email);
    let token = generate_jwt_token(
        &user.id,
        username,
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

    Ok((
        StatusCode::OK,
        Json(AuthResponse {
            token,
            user_id: user.id.to_string(),
            username: user.username.unwrap_or(user.email),
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
    let existing = db.get_user_by_username(username)
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

    let password_hash = hash(&payload.password, DEFAULT_COST)
        .map_err(|e| {
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
        &username,
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

    Ok((
        StatusCode::CREATED,
        Json(AuthResponse {
            token,
            user_id: user_id.to_string(),
            username: username.to_string(),
        }),
    ))
}
