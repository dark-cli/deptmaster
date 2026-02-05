use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use chrono::Utc;
use crate::AppState;
use crate::middleware::auth::AuthUser;
use crate::websocket;

async fn require_wallet_role_at_least(
    state: &AppState,
    wallet_id: Uuid,
    auth_user: &AuthUser,
    required_role: &str,
) -> Result<String, (StatusCode, Json<serde_json::Value>)> {
    if auth_user.is_admin {
        return Ok("admin".to_string());
    }
    let role = sqlx::query_scalar::<_, String>(
        r#"
        SELECT role
        FROM wallet_users
        WHERE wallet_id = $1 AND user_id = $2
        "#
    )
    .bind(wallet_id)
    .bind(auth_user.user_id)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet role: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?
    .ok_or_else(|| {
        (
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({"error": "You do not have access to this wallet"})),
        )
    })?;

    // member < admin < owner
    let role_hierarchy = ["member", "admin", "owner"];
    let user_level = role_hierarchy
        .iter()
        .position(|&r| r == role.as_str())
        .unwrap_or(0);
    let required_level = role_hierarchy
        .iter()
        .position(|&r| r == required_role)
        .unwrap_or(0);

    if user_level < required_level {
        return Err((
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({"error": "Insufficient wallet permissions"})),
        ));
    }

    Ok(role)
}

#[derive(Serialize, Deserialize)]
pub struct Wallet {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub created_by: Option<String>,
    pub is_active: bool,
}

#[derive(Serialize, Deserialize)]
pub struct WalletUser {
    pub id: String,
    pub wallet_id: String,
    pub user_id: String,
    pub role: String, // 'owner', 'admin', 'member'
    pub subscribed_at: String,
}

#[derive(Deserialize)]
pub struct CreateWalletRequest {
    pub name: String,
    pub description: Option<String>,
}

#[derive(Deserialize)]
pub struct UpdateWalletRequest {
    pub name: Option<String>,
    pub description: Option<String>,
    pub is_active: Option<bool>,
}

#[derive(Deserialize)]
pub struct AddUserToWalletRequest {
    pub user_id: String,
    pub role: String, // 'owner', 'admin', 'member'
}

#[derive(Deserialize)]
pub struct UpdateWalletUserRequest {
    pub role: String, // 'owner', 'admin', 'member'
}

#[derive(Serialize)]
pub struct CreateWalletResponse {
    pub id: String,
    pub name: String,
    pub message: String,
}

#[derive(Serialize)]
pub struct WalletListResponse {
    pub wallets: Vec<Wallet>,
}

#[derive(Serialize)]
pub struct WalletUsersResponse {
    pub users: Vec<WalletUser>,
}

/// Create a new wallet for the current user (authenticated user becomes owner)
/// Used when user has no wallets yet - forces them into a wallet for all actions.
pub async fn create_my_wallet(
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<CreateWalletRequest>,
) -> Result<(StatusCode, Json<CreateWalletResponse>), (StatusCode, Json<serde_json::Value>)> {
    let user_id = auth_user.user_id;
    let wallet_id = Uuid::new_v4();
    let now = Utc::now();

    sqlx::query(
        r#"
        INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#
    )
    .bind(wallet_id)
    .bind(&payload.name)
    .bind(&payload.description)
    .bind(user_id)
    .bind(now)
    .bind(now)
    .bind(true)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create wallet"})),
        )
    })?;

    sqlx::query(
        r#"
        INSERT INTO wallet_users (wallet_id, user_id, role, subscribed_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (wallet_id, user_id) DO NOTHING
        "#
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind("owner")
    .bind(now)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error adding user to wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to add user to wallet"})),
        )
    })?;

    let response = CreateWalletResponse {
        id: wallet_id.to_string(),
        name: payload.name.clone(),
        message: "Wallet created successfully".to_string(),
    };

    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_id,
        "wallet_created",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::CREATED,
        Json(response),
    ))
}

/// Create a new wallet (Admin only)
pub async fn create_wallet(
    State(state): State<AppState>,
    Json(payload): Json<CreateWalletRequest>,
) -> Result<(StatusCode, Json<CreateWalletResponse>), (StatusCode, Json<serde_json::Value>)> {
    // TODO: Get user_id from auth middleware
    // For now, we'll use a placeholder - this will be replaced with actual auth
    let user_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM users_projection LIMIT 1"
    )
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let wallet_id = Uuid::new_v4();
    let now = Utc::now();

    // Create wallet
    sqlx::query(
        r#"
        INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#
    )
    .bind(wallet_id)
    .bind(&payload.name)
    .bind(&payload.description)
    .bind(user_id)
    .bind(now)
    .bind(now)
    .bind(true)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error creating wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create wallet"})),
        )
    })?;

    // Add creator as owner
    sqlx::query(
        r#"
        INSERT INTO wallet_users (wallet_id, user_id, role, subscribed_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (wallet_id, user_id) DO NOTHING
        "#
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind("owner")
    .bind(now)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error adding user to wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to add user to wallet"})),
        )
    })?;

    let response = CreateWalletResponse {
        id: wallet_id.to_string(),
        name: payload.name,
        message: "Wallet created successfully".to_string(),
    };

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_id,
        "wallet_created",
        &serde_json::to_string(&response).unwrap_or_default(),
    );

    Ok((
        StatusCode::CREATED,
        Json(response),
    ))
}

/// List all wallets (Admin only)
pub async fn list_wallets(
    State(state): State<AppState>,
) -> Result<Json<WalletListResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallets = sqlx::query(
        r#"
        SELECT id, name, description, created_at, updated_at, created_by, is_active
        FROM wallets
        WHERE is_active = true
        ORDER BY created_at DESC
        "#
    )
    .map(|row: sqlx::postgres::PgRow| Wallet {
        id: row.get::<Uuid, _>("id").to_string(),
        name: row.get("name"),
        description: row.get("description"),
        created_at: row.get::<chrono::NaiveDateTime, _>("created_at").to_string(),
        updated_at: row.get::<chrono::NaiveDateTime, _>("updated_at").to_string(),
        created_by: row.get::<Option<Uuid>, _>("created_by").map(|u| u.to_string()),
        is_active: row.get("is_active"),
    })
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching wallets: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch wallets"})),
        )
    })?;

    Ok(Json(WalletListResponse { wallets }))
}

/// Get wallet details
pub async fn get_wallet(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Wallet>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;

    let wallet = sqlx::query(
        r#"
        SELECT id, name, description, created_at, updated_at, created_by, is_active
        FROM wallets
        WHERE id = $1 AND is_active = true
        "#
    )
    .bind(wallet_uuid)
    .map(|row: sqlx::postgres::PgRow| Wallet {
        id: row.get::<Uuid, _>("id").to_string(),
        name: row.get("name"),
        description: row.get("description"),
        created_at: row.get::<chrono::NaiveDateTime, _>("created_at").to_string(),
        updated_at: row.get::<chrono::NaiveDateTime, _>("updated_at").to_string(),
        created_by: row.get::<Option<Uuid>, _>("created_by").map(|u| u.to_string()),
        is_active: row.get("is_active"),
    })
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    match wallet {
        Some(w) => Ok(Json(w)),
        None => Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Wallet not found"})),
        )),
    }
}

/// Update wallet
pub async fn update_wallet(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<UpdateWalletRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;

    // Enforce permissions: only wallet admins/owners may edit wallet details.
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;

    // Check if wallet exists
    let wallet_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)"
    )
    .bind(wallet_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if !wallet_exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Wallet not found"})),
        ));
    }

    // Build update query dynamically
    let mut updates = Vec::new();
    let mut bind_index = 1;

    if payload.name.is_some() {
        updates.push(format!("name = ${}", bind_index));
        bind_index += 1;
    }
    if payload.description.is_some() {
        updates.push(format!("description = ${}", bind_index));
        bind_index += 1;
    }
    if payload.is_active.is_some() {
        updates.push(format!("is_active = ${}", bind_index));
        bind_index += 1;
    }

    if updates.is_empty() {
        return Ok((
            StatusCode::OK,
            Json(serde_json::json!({"message": "No changes provided"})),
        ));
    }

    updates.push(format!("updated_at = ${}", bind_index));

    let query = format!(
        "UPDATE wallets SET {} WHERE id = ${}",
        updates.join(", "),
        bind_index + 1
    );

    let mut query_builder = sqlx::query(&query);

    if let Some(name) = &payload.name {
        query_builder = query_builder.bind(name);
    }
    if let Some(description) = &payload.description {
        query_builder = query_builder.bind(description);
    }
    if let Some(is_active) = payload.is_active {
        query_builder = query_builder.bind(is_active);
    }
    query_builder = query_builder.bind(Utc::now());
    query_builder = query_builder.bind(wallet_uuid);

    query_builder
        .execute(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("Error updating wallet: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to update wallet"})),
            )
        })?;

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_uuid,
        "wallet_updated",
        &serde_json::json!({"wallet_id": wallet_id}).to_string(),
    );

    Ok((
        StatusCode::OK,
        Json(serde_json::json!({"message": "Wallet updated successfully"})),
    ))
}

/// Delete wallet (soft delete)
pub async fn delete_wallet(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;

    // Enforce permissions: only wallet owners may delete a wallet.
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "owner").await?;

    // Soft delete by setting is_active = false
    sqlx::query(
        "UPDATE wallets SET is_active = false, updated_at = $1 WHERE id = $2"
    )
    .bind(Utc::now())
    .bind(wallet_uuid)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error deleting wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to delete wallet"})),
        )
    })?;

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_uuid,
        "wallet_deleted",
        &serde_json::json!({"wallet_id": wallet_id}).to_string(),
    );

    Ok((
        StatusCode::OK,
        Json(serde_json::json!({"message": "Wallet deleted successfully"})),
    ))
}

/// Add user to wallet
pub async fn add_user_to_wallet(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<AddUserToWalletRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;

    // Enforce permissions: only wallet admins/owners may manage members.
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;

    let user_uuid = Uuid::parse_str(&payload.user_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid user_id: {}", e)})),
        )
    })?;

    // Validate role
    if !["owner", "admin", "member"].contains(&payload.role.as_str()) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Invalid role. Must be 'owner', 'admin', or 'member'"})),
        ));
    }

    // Check if wallet exists
    let wallet_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)"
    )
    .bind(wallet_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if !wallet_exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Wallet not found"})),
        ));
    }

    // Check if user exists
    let user_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users_projection WHERE id = $1)"
    )
    .bind(user_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if !user_exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "User not found"})),
        ));
    }

    // Add user to wallet
    sqlx::query(
        r#"
        INSERT INTO wallet_users (wallet_id, user_id, role, subscribed_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (wallet_id, user_id) 
        DO UPDATE SET role = $3, subscribed_at = $4
        "#
    )
    .bind(wallet_uuid)
    .bind(user_uuid)
    .bind(&payload.role)
    .bind(Utc::now())
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error adding user to wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to add user to wallet"})),
        )
    })?;

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_uuid,
        "wallet_user_added",
        &serde_json::json!({
            "wallet_id": wallet_id,
            "user_id": payload.user_id,
            "role": payload.role
        }).to_string(),
    );

    Ok((
        StatusCode::CREATED,
        Json(serde_json::json!({"message": "User added to wallet successfully"})),
    ))
}

/// List users in a wallet
pub async fn list_wallet_users(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<WalletUsersResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;

    let users = sqlx::query(
        r#"
        SELECT wu.id, wu.wallet_id, wu.user_id, wu.role, wu.subscribed_at
        FROM wallet_users wu
        WHERE wu.wallet_id = $1
        ORDER BY wu.subscribed_at DESC
        "#
    )
    .bind(wallet_uuid)
    .map(|row: sqlx::postgres::PgRow| WalletUser {
        id: row.get::<Uuid, _>("id").to_string(),
        wallet_id: row.get::<Uuid, _>("wallet_id").to_string(),
        user_id: row.get::<Uuid, _>("user_id").to_string(),
        role: row.get("role"),
        subscribed_at: row.get::<chrono::NaiveDateTime, _>("subscribed_at").to_string(),
    })
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching wallet users: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch wallet users"})),
        )
    })?;

    Ok(Json(WalletUsersResponse { users }))
}

/// Update user role in wallet
pub async fn update_wallet_user(
    Path((wallet_id, user_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<UpdateWalletUserRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;

    // Enforce permissions: only wallet admins/owners may manage members.
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;

    let user_uuid = Uuid::parse_str(&user_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid user_id: {}", e)})),
        )
    })?;

    // Validate role
    if !["owner", "admin", "member"].contains(&payload.role.as_str()) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Invalid role. Must be 'owner', 'admin', or 'member'"})),
        ));
    }

    // Update user role
    let result = sqlx::query(
        "UPDATE wallet_users SET role = $1 WHERE wallet_id = $2 AND user_id = $3"
    )
    .bind(&payload.role)
    .bind(wallet_uuid)
    .bind(user_uuid)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error updating wallet user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update wallet user"})),
        )
    })?;

    if result.rows_affected() == 0 {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Wallet user not found"})),
        ));
    }

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_uuid,
        "wallet_user_updated",
        &serde_json::json!({
            "wallet_id": wallet_id,
            "user_id": user_id,
            "role": payload.role
        }).to_string(),
    );

    Ok((
        StatusCode::OK,
        Json(serde_json::json!({"message": "Wallet user updated successfully"})),
    ))
}

/// Remove user from wallet
pub async fn remove_user_from_wallet(
    Path((wallet_id, user_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;

    // Enforce permissions: only wallet admins/owners may manage members.
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;

    let user_uuid = Uuid::parse_str(&user_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid user_id: {}", e)})),
        )
    })?;

    // Remove user from wallet
    let result = sqlx::query(
        "DELETE FROM wallet_users WHERE wallet_id = $1 AND user_id = $2"
    )
    .bind(wallet_uuid)
    .bind(user_uuid)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error removing user from wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to remove user from wallet"})),
        )
    })?;

    if result.rows_affected() == 0 {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Wallet user not found"})),
        ));
    }

    // Broadcast change via WebSocket
    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_uuid,
        "wallet_user_removed",
        &serde_json::json!({
            "wallet_id": wallet_id,
            "user_id": user_id
        }).to_string(),
    );

    Ok((
        StatusCode::OK,
        Json(serde_json::json!({"message": "User removed from wallet successfully"})),
    ))
}

/// List wallets for current user (user's subscribed wallets)
pub async fn list_user_wallets(
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<WalletListResponse>, (StatusCode, Json<serde_json::Value>)> {
    let user_id = auth_user.user_id;

    let wallets = sqlx::query(
        r#"
        SELECT w.id, w.name, w.description, w.created_at, w.updated_at, w.created_by, w.is_active
        FROM wallets w
        INNER JOIN wallet_users wu ON wu.wallet_id = w.id
        WHERE wu.user_id = $1 AND w.is_active = true
        ORDER BY wu.subscribed_at DESC
        "#
    )
    .bind(user_id)
    .map(|row: sqlx::postgres::PgRow| Wallet {
        id: row.get::<Uuid, _>("id").to_string(),
        name: row.get("name"),
        description: row.get("description"),
        created_at: row.get::<chrono::NaiveDateTime, _>("created_at").to_string(),
        updated_at: row.get::<chrono::NaiveDateTime, _>("updated_at").to_string(),
        created_by: row.get::<Option<Uuid>, _>("created_by").map(|u| u.to_string()),
        is_active: row.get("is_active"),
    })
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching user wallets: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch wallets"})),
        )
    })?;

    Ok(Json(WalletListResponse { wallets }))
}
