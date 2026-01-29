use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use bcrypt::verify;
use jsonwebtoken::{encode, EncodingKey, Header, Algorithm};
use chrono::{Utc, Duration};
use crate::AppState;
use crate::middleware::auth::Claims;

#[derive(Deserialize)]
pub struct AdminLoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AdminAuthResponse {
    pub token: String,
    pub admin_id: String,
    pub username: String,
}

// Generate JWT token for admin
fn generate_admin_jwt_token(admin_id: &Uuid, username: &str, secret: &str, expiration_secs: u64) -> Result<String, jsonwebtoken::errors::Error> {
    let exp = (Utc::now() + Duration::seconds(expiration_secs as i64)).timestamp() as usize;
    let claims = Claims {
        user_id: admin_id.to_string(),
        email: username.to_string(), // Use username as email in claims
        exp,
    };
    
    let header = Header::new(Algorithm::HS256);
    let encoding_key = EncodingKey::from_secret(secret.as_ref());
    encode(&header, &claims, &encoding_key)
}

pub async fn admin_login(
    State(state): State<AppState>,
    Json(payload): Json<AdminLoginRequest>,
) -> Result<(StatusCode, Json<AdminAuthResponse>), (StatusCode, Json<serde_json::Value>)> {
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

    // Find admin user by username
    let admin = sqlx::query(
        "SELECT id, username, password_hash, is_active FROM admin_users WHERE username = $1 AND is_active = true LIMIT 1"
    )
    .bind(&payload.username.trim())
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching admin user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let admin = match admin {
        Some(a) => a,
        None => {
            return Err((
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({"error": "Invalid username or password"})),
            ));
        }
    };

    let admin_id: Uuid = admin.get::<Uuid, _>("id");
    let password_hash: String = admin.get::<String, _>("password_hash");
    let username: String = admin.get::<String, _>("username");
    let is_active: bool = admin.get::<bool, _>("is_active");

    if !is_active {
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Admin account is disabled"})),
        ));
    }

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

    // Update last login time
    let _ = sqlx::query("UPDATE admin_users SET last_login_at = NOW() WHERE id = $1")
        .bind(&admin_id)
        .execute(&*state.db_pool)
        .await;

    // Generate JWT token
    let token = generate_admin_jwt_token(
        &admin_id,
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
        Json(AdminAuthResponse {
            token,
            admin_id: admin_id.to_string(),
            username,
        }),
    ))
}
