use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use bcrypt::{hash, DEFAULT_COST};
use crate::AppState;

#[derive(Serialize)]
pub struct UserResponse {
    pub id: String,
    pub username: String,
    pub created_at: chrono::NaiveDateTime,
}

#[derive(Serialize)]
pub struct LoginLogResponse {
    pub id: i64,
    pub user_id: String,
    pub login_at: chrono::NaiveDateTime,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub success: bool,
    pub failure_reason: Option<String>,
}

#[derive(Deserialize)]
pub struct CreateUserRequest {
    pub username: String,
    pub password: String,
}

#[derive(Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password: String,
}

#[derive(Deserialize)]
pub struct AdminChangePasswordRequest {
    pub new_password: String,
}

// Get all users (admin only)
pub async fn get_users(
    State(state): State<AppState>,
) -> Result<Json<Vec<UserResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let users = sqlx::query(
        "SELECT id, username, created_at FROM users_projection ORDER BY created_at DESC"
    )
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching users: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let user_responses: Vec<UserResponse> = users
        .into_iter()
        .map(|row| UserResponse {
            id: row.get::<Uuid, _>("id").to_string(),
            username: row.get::<String, _>("username"),
            created_at: row.get::<chrono::NaiveDateTime, _>("created_at"),
        })
        .collect();

    Ok(Json(user_responses))
}

// Create new user (admin only)
pub async fn create_user(
    State(state): State<AppState>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<(StatusCode, Json<UserResponse>), (StatusCode, Json<serde_json::Value>)> {
    // Validate input
    if payload.username.trim().is_empty() {
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

    // Check if user already exists
    let existing = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users_projection WHERE username = $1)"
    )
    .bind(&payload.username.trim())
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking existing user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if existing {
        return Err((
            StatusCode::CONFLICT,
            Json(serde_json::json!({"error": "User with this username already exists"})),
        ));
    }

    // Hash password
    let password_hash = hash(&payload.password, DEFAULT_COST)
        .map_err(|e| {
            tracing::error!("Error hashing password: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to hash password"})),
            )
        })?;

    // Create user
    let user_id = Uuid::new_v4();
    let username = payload.username.trim().to_string();
    let created_at = chrono::Utc::now().naive_utc();

    sqlx::query(
        "INSERT INTO users_projection (id, username, password_hash, created_at, last_event_id) 
         VALUES ($1, $2, $3, $4, 0)"
    )
    .bind(&user_id)
    .bind(&username)
    .bind(&password_hash)
    .bind(&created_at)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create user"})),
        )
    })?;

    Ok((
        StatusCode::CREATED,
        Json(UserResponse {
            id: user_id.to_string(),
            username,
            created_at,
        }),
    ))
}

// Delete user (admin only)
pub async fn delete_user(
    State(state): State<AppState>,
    Path(user_id): Path<String>,
) -> Result<StatusCode, (StatusCode, Json<serde_json::Value>)> {
    let user_uuid = Uuid::parse_str(&user_id)
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "Invalid user ID"})),
            )
        })?;

    // Check if user exists
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users_projection WHERE id = $1)"
    )
    .bind(&user_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if !exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "User not found"})),
        ));
    }

    // Delete user (cascade will handle related data)
    sqlx::query("DELETE FROM users_projection WHERE id = $1")
        .bind(&user_uuid)
        .execute(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Error deleting user: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to delete user"})),
            )
        })?;

    Ok(StatusCode::NO_CONTENT)
}

// Change own password
pub async fn change_password(
    State(state): State<AppState>,
    axum::extract::Extension(auth_user): axum::extract::Extension<crate::middleware::auth::AuthUser>,
    Json(payload): Json<ChangePasswordRequest>,
) -> Result<StatusCode, (StatusCode, Json<serde_json::Value>)> {
    if payload.new_password.len() < 8 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "New password must be at least 8 characters"})),
        ));
    }

    // Get current password hash
    let password_hash: String = sqlx::query_scalar(
        "SELECT password_hash FROM users_projection WHERE id = $1"
    )
    .bind(&auth_user.user_id)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    // Verify current password
    let valid = bcrypt::verify(&payload.current_password, &password_hash)
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
            Json(serde_json::json!({"error": "Current password is incorrect"})),
        ));
    }

    // Hash new password
    let new_password_hash = hash(&payload.new_password, DEFAULT_COST)
        .map_err(|e| {
            tracing::error!("Error hashing password: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to hash password"})),
            )
        })?;

    // Update password
    sqlx::query("UPDATE users_projection SET password_hash = $1 WHERE id = $2")
        .bind(&new_password_hash)
        .bind(&auth_user.user_id)
        .execute(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Error updating password: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to update password"})),
            )
        })?;

    Ok(StatusCode::NO_CONTENT)
}

// Admin change user password
pub async fn admin_change_password(
    State(state): State<AppState>,
    Path(user_id): Path<String>,
    Json(payload): Json<AdminChangePasswordRequest>,
) -> Result<StatusCode, (StatusCode, Json<serde_json::Value>)> {
    if payload.new_password.len() < 8 {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Password must be at least 8 characters"})),
        ));
    }

    let user_uuid = Uuid::parse_str(&user_id)
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "Invalid user ID"})),
            )
        })?;

    // Hash new password
    let new_password_hash = hash(&payload.new_password, DEFAULT_COST)
        .map_err(|e| {
            tracing::error!("Error hashing password: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to hash password"})),
            )
        })?;

    // Update password
    let rows_affected = sqlx::query("UPDATE users_projection SET password_hash = $1 WHERE id = $2")
        .bind(&new_password_hash)
        .bind(&user_uuid)
        .execute(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Error updating password: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to update password"})),
            )
        })?;

    if rows_affected.rows_affected() == 0 {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "User not found"})),
        ));
    }

    Ok(StatusCode::NO_CONTENT)
}

// Get login logs for a user
pub async fn get_user_login_logs(
    State(state): State<AppState>,
    Path(user_id): Path<String>,
) -> Result<Json<Vec<LoginLogResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let user_uuid = Uuid::parse_str(&user_id)
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "Invalid user ID"})),
            )
        })?;

    let logs = sqlx::query(
        "SELECT id, user_id, login_at, ip_address, user_agent, success, failure_reason 
         FROM login_logs 
         WHERE user_id = $1 
         ORDER BY login_at DESC 
         LIMIT 100"
    )
    .bind(&user_uuid)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching login logs: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let log_responses: Vec<LoginLogResponse> = logs
        .into_iter()
        .map(|row| LoginLogResponse {
            id: row.get::<i64, _>("id"),
            user_id: row.get::<Uuid, _>("user_id").to_string(),
            login_at: row.get::<chrono::NaiveDateTime, _>("login_at"),
            ip_address: row.get::<Option<String>, _>("ip_address"),
            user_agent: row.get::<Option<String>, _>("user_agent"),
            success: row.get::<bool, _>("success"),
            failure_reason: row.get::<Option<String>, _>("failure_reason"),
        })
        .collect();

    Ok(Json(log_responses))
}

// Backup user data (export all user's data as JSON)
pub async fn backup_user_data(
    State(state): State<AppState>,
    Path(user_id): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let user_uuid = Uuid::parse_str(&user_id)
        .map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "Invalid user ID"})),
            )
        })?;

    // Get user info
    let user: Option<(String, chrono::NaiveDateTime)> = sqlx::query_as(
        "SELECT username, created_at FROM users_projection WHERE id = $1"
    )
    .bind(&user_uuid)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let (username, created_at) = user.ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "User not found"})),
        )
    })?;

    // Get contacts
    let contacts = sqlx::query(
        "SELECT id, name, phone, email, notes, created_at, updated_at 
         FROM contacts_projection 
         WHERE user_id = $1 AND is_deleted = false"
    )
    .bind(&user_uuid)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching contacts: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    // Get transactions
    let transactions = sqlx::query(
        "SELECT id, contact_id, type, direction, amount, currency, description, 
                transaction_date, due_date, created_at, updated_at 
         FROM transactions_projection 
         WHERE user_id = $1 AND is_deleted = false"
    )
    .bind(&user_uuid)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching transactions: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    // Build backup JSON
    let backup = serde_json::json!({
        "user": {
            "id": user_uuid.to_string(),
            "username": username,
            "created_at": created_at,
        },
        "contacts": contacts.iter().map(|row| {
            serde_json::json!({
                "id": row.get::<Uuid, _>("id").to_string(),
                "name": row.get::<String, _>("name"),
                "phone": row.get::<Option<String>, _>("phone"),
                "email": row.get::<Option<String>, _>("email"),
                "notes": row.get::<Option<String>, _>("notes"),
                "created_at": row.get::<chrono::NaiveDateTime, _>("created_at"),
                "updated_at": row.get::<chrono::NaiveDateTime, _>("updated_at"),
            })
        }).collect::<Vec<_>>(),
        "transactions": transactions.iter().map(|row| {
            serde_json::json!({
                "id": row.get::<Uuid, _>("id").to_string(),
                "contact_id": row.get::<Uuid, _>("contact_id").to_string(),
                "type": row.get::<String, _>("type"),
                "direction": row.get::<String, _>("direction"),
                "amount": row.get::<i64, _>("amount"),
                "currency": row.get::<Option<String>, _>("currency"),
                "description": row.get::<Option<String>, _>("description"),
                "transaction_date": row.get::<chrono::NaiveDate, _>("transaction_date"),
                "due_date": row.get::<Option<chrono::NaiveDate>, _>("due_date"),
                "created_at": row.get::<chrono::NaiveDateTime, _>("created_at"),
                "updated_at": row.get::<chrono::NaiveDateTime, _>("updated_at"),
            })
        }).collect::<Vec<_>>(),
        "backup_date": chrono::Utc::now().to_rfc3339(),
    });

    Ok(Json(backup))
}
