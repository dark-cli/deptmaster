use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use bcrypt::verify;
use crate::AppState;

#[derive(Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Deserialize)]
#[allow(dead_code)]
pub struct RegisterRequest {
    pub username: String,
    pub email: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    pub token: String, // Simple token for now (could be JWT later)
    pub user_id: String,
    pub username: String,
}

#[derive(Serialize)]
pub struct RegisterResponse {
    pub user_id: String,
    pub username: String,
    pub message: String,
}

// Simple token generation (in production, use JWT)
fn generate_token(user_id: &Uuid) -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    format!("{}_{}", user_id, timestamp)
}

// Registration is disabled - users are created via seed_data
// pub async fn register(...) { ... }

pub async fn login(
    State(state): State<AppState>,
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

    // Find user by email (username field is treated as email)
    let user = sqlx::query(
        "SELECT id, email, password_hash FROM users_projection WHERE email = $1 LIMIT 1"
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

    let user = user.ok_or_else(|| {
        (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Invalid username or password"})),
        )
    })?;

    let user_id: Uuid = user.get::<Uuid, _>("id");
    let password_hash: String = user.get::<String, _>("password_hash");
    let email: String = user.get::<String, _>("email");

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
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Invalid username or password"})),
        ));
    }

    // Generate token
    let token = generate_token(&user_id);

    Ok((
        StatusCode::OK,
        Json(AuthResponse {
            token,
            user_id: user_id.to_string(),
            username: email,
        }),
    ))
}
