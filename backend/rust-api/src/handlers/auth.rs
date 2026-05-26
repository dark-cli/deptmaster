use axum::{
    extract::State,
    http::{StatusCode, HeaderMap},
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use bcrypt::{hash, verify, DEFAULT_COST};
use jsonwebtoken::{encode, EncodingKey, Header, Algorithm};
use chrono::{Utc, Duration};
use crate::AppState;
use crate::middleware::auth::Claims;

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

    // Find user by username
    let user = sqlx::query(
        "SELECT id, username, password_hash FROM users_projection WHERE username = $1 LIMIT 1"
    )
    .bind(&payload.username.trim())
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let ip_address = extract_ip_address(&headers);
    let user_agent = extract_user_agent(&headers);

    let user = match user {
        Some(u) => u,
        None => {
            // Log failed login attempt
            let _ = sqlx::query(
                "INSERT INTO login_logs (user_id, login_at, ip_address, user_agent, success, failure_reason) 
                 VALUES (NULL, NOW(), $1, $2, false, 'user_not_found')"
            )
            .bind(&ip_address)
            .bind(&user_agent)
            .execute(&*state.db_pool)
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

    let user_id: Uuid = user.get::<Uuid, _>("id");
    let password_hash: String = user.get::<String, _>("password_hash");
    let username: String = user.get::<String, _>("username");

    // Verify password
    let valid = verify(&payload.password, &password_hash)
        .map_err(|e| {
            tracing::error!("Error verifying password: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Authentication error"})),
            )
        })?;

    if !valid {
        // Log failed login attempt
        let _ = sqlx::query(
            "INSERT INTO login_logs (user_id, login_at, ip_address, user_agent, success, failure_reason) 
             VALUES ($1, NOW(), $2, $3, false, 'invalid_password')"
        )
        .bind(&user_id)
        .bind(&ip_address)
        .bind(&user_agent)
        .execute(&*state.db_pool)
        .await;
        
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "code": "DEBITUM_AUTH_DECLINED",
                "message": "Invalid username or password"
            })),
        ));
    }

    // Log successful login
    let _ = sqlx::query(
        "INSERT INTO login_logs (user_id, login_at, ip_address, user_agent, success) 
         VALUES ($1, NOW(), $2, $3, true)"
    )
    .bind(&user_id)
    .bind(&ip_address)
    .bind(&user_agent)
    .execute(&*state.db_pool)
    .await;

    // Generate JWT token
    let token = generate_jwt_token(
        &user_id,
        &username,
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
            user_id: user_id.to_string(),
            username: username,
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

    let existing = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users_projection WHERE username = $1)"
    )
    .bind(&username)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("register: check existing: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

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
    let created_at = chrono::Utc::now().naive_utc();

    sqlx::query(
        "INSERT INTO users_projection (id, username, password_hash, created_at, last_event_id) VALUES ($1, $2, $3, $4, 0)"
    )
    .bind(&user_id)
    .bind(&username)
    .bind(&password_hash)
    .bind(&created_at)
    .execute(&*state.db_pool)
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
