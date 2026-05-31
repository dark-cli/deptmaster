use crate::database::repository::{Database, DatabaseRepository};
use crate::middleware::auth::Claims;
use crate::AppState;
use axum::{extract::State, http::StatusCode, response::Json};
use bcrypt::verify;
use chrono::{Duration, Utc};
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

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
fn generate_admin_jwt_token(
    admin_id: &Uuid,
    username: &str,
    secret: &str,
    expiration_secs: u64,
) -> Result<String, jsonwebtoken::errors::Error> {
    let exp = (Utc::now() + Duration::seconds(expiration_secs as i64)).timestamp() as usize;
    let claims = Claims {
        user_id: admin_id.to_string(),
        username: username.to_string(),
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
    let username = payload.username.trim();
    if username.is_empty() {
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

    // Find admin user by username
    let admin = db.get_admin_by_username(username).await.map_err(|e| {
        tracing::error!("Error fetching admin user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let (admin_id, username_result, password_hash, is_active) = match admin {
        Some(a) => a,
        None => {
            return Err((
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({"error": "Invalid username or password"})),
            ));
        }
    };

    if !is_active {
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Admin account is disabled"})),
        ));
    }

    // Verify password
    let valid = verify(&payload.password, &password_hash).map_err(|e| {
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
    let _ = db.update_admin_last_login(admin_id).await;

    // Generate JWT token
    let token = generate_admin_jwt_token(
        &admin_id,
        &username_result,
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
            username: username_result,
        }),
    ))
}
