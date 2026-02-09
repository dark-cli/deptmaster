use axum::{
    extract::{Extension, Path, Query, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;
use chrono::Utc;
use crate::AppState;
use crate::handlers::sync;
use crate::middleware::auth::AuthUser;
use crate::middleware::wallet_context::WalletContext;
use crate::services::permission_service::{self, ResourceType};
use crate::websocket;

/// Validate permission dependencies (e.g., Write implies Read)
fn validate_permission_dependencies(actions: &[String]) -> Result<(), String> {
    let has_action = |name: &str| actions.iter().any(|a| a == name);

    // Rule 1: Write implies Read for same resource
    for action in actions {
        if let Some((resource, verb)) = action.split_once(':') {
             // For wallet resource, 'manage_members' is a special verb
             if resource == "wallet" {
                 if verb == "update" || verb == "delete" || verb == "manage_members" {
                     if !has_action("wallet:read") {
                         return Err(format!("Permission '{}' requires 'wallet:read'", action));
                     }
                 }
             } else {
                 if ["create", "update", "delete", "close"].contains(&verb) {
                     let read_action = format!("{}:read", resource);
                     if !has_action(&read_action) {
                         return Err(format!("Permission '{}' requires '{}'", action, read_action));
                     }
                 }
             }
        }
    }

    // Rule 2: Transaction permissions imply Contact Read
    // (Because you need to see the contact to see its transactions)
    if actions.iter().any(|a| a.starts_with("transaction:")) {
        if !has_action("contact:read") {
             return Err("Transaction permissions require 'contact:read'".to_string());
        }
    }

    Ok(())
}

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
            Json(serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "You do not have access to this wallet"
            })),
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
            Json(serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "Insufficient wallet permissions"
            })),
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
    pub username: Option<String>,
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

/// Add user to wallet by username (lookup by email until we have invites).
/// New members get role 'member' by default; change role later on the member.
#[derive(Deserialize)]
pub struct AddUserToWalletRequest {
    /// Username of the user to add.
    pub username: String,
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

    // Initialize default permissions (system groups and matrix)
    if let Err(e) = initialize_wallet_permissions(&state.db_pool, wallet_id).await {
        tracing::error!("Failed to initialize wallet permissions for {}: {:?}", wallet_id, e);
    }

    Ok((
        StatusCode::CREATED,
        Json(response),
    ))
}

/// Helper to initialize default permissions for a new wallet (all_users, all_contacts, matrix)
async fn initialize_wallet_permissions(
    db_pool: &sqlx::PgPool,
    wallet_id: Uuid,
) -> Result<(), sqlx::Error> {
    // 1. Create all_users system user group
    let ug_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO user_groups (id, wallet_id, name, is_system) VALUES ($1, $2, 'all_users', true) ON CONFLICT (wallet_id, name) DO NOTHING"
    )
    .bind(ug_id)
    .bind(wallet_id)
    .execute(db_pool)
    .await?;

    // Get the actual ID (in case of conflict)
    let ug_id: Uuid = sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
        .bind(wallet_id)
        .fetch_one(db_pool)
        .await?;

    // 2. Create all_contacts system contact group
    let cg_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO contact_groups (id, wallet_id, name, type, is_system) VALUES ($1, $2, 'all_contacts', 'static', true) ON CONFLICT (wallet_id, name) DO NOTHING"
    )
    .bind(cg_id)
    .bind(wallet_id)
    .execute(db_pool)
    .await?;

    // Get the actual ID
    let cg_id: Uuid = sqlx::query_scalar("SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'")
        .bind(wallet_id)
        .fetch_one(db_pool)
        .await?;

    // 3. Grant default permissions: all_users can only READ contacts/transactions/events by default.
    // Explicitly exclude create/update/delete/close to force admins to grant them.
    let actions = [
        "contact:read",
        "transaction:read",
        "events:read"
    ];

    for action in actions {
        // Look up action ID
        let action_id: Option<i16> = sqlx::query_scalar("SELECT id FROM permission_actions WHERE name = $1")
            .bind(action)
            .fetch_optional(db_pool)
            .await?;
        
        if let Some(aid) = action_id {
            sqlx::query(
                "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
            )
            .bind(ug_id)
            .bind(cg_id)
            .bind(aid)
            .execute(db_pool)
            .await?;
        }
    }

    Ok(())
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

    // Initialize default permissions (system groups and matrix)
    if let Err(e) = initialize_wallet_permissions(&state.db_pool, wallet_id).await {
        tracing::error!("Failed to initialize wallet permissions for {}: {:?}", wallet_id, e);
    }

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

    // Enforce permissions: only wallet owners/admins may add members.
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;

    let username = payload.username.trim();
    if username.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Username is required"})),
        ));
    }

    // Look up user by username
    let user_uuid: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM users_projection WHERE username = $1 LIMIT 1",
    )
    .bind(username)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error looking up user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let user_uuid = user_uuid.ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "User not found."})),
        )
    })?;

    // New members get role 'member' (read-only by default). Change role later on the member.
    // POLICY: New invited users MUST start as 'member', never 'owner' or 'admin'.
    let role = "member";

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

    // Emit event and apply to projection (user_uuid already resolved from username)
    let event_data = serde_json::json!({ "user_id": user_uuid.to_string(), "role": role });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        user_uuid,
        "WALLET_USER_ADDED",
        event_data,
    )
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
            "user_id": user_uuid.to_string(),
            "role": role
        }).to_string(),
    );

    Ok((
        StatusCode::CREATED,
        Json(serde_json::json!({"message": "User added to wallet successfully"})),
    ))
}

/// Search users by username (for add-member typeahead). Returns id and username.
/// GET /api/wallets/:wallet_id/users/search?q=...
pub async fn search_wallet_users(
    Path(wallet_id): Path<String>,
    Query(params): Query<std::collections::HashMap<String, String>>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<UserSearchResult>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;

    let q = params.get("q").map(|s| s.trim()).unwrap_or("").to_string();
    if q.is_empty() {
        return Ok(Json(vec![]));
    }

    let pattern = format!("%{}%", q);
    let rows = sqlx::query(
        "SELECT id, username FROM users_projection WHERE LOWER(username) LIKE LOWER($1) ORDER BY username LIMIT 20",
    )
    .bind(&pattern)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("search_wallet_users: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Search failed"})),
        )
    })?;

    let list: Vec<UserSearchResult> = rows
        .into_iter()
        .map(|row: sqlx::postgres::PgRow| UserSearchResult {
            id: row.get::<Uuid, _>("id").to_string(),
            username: row.get::<String, _>("username"),
        })
        .collect();
    Ok(Json(list))
}

#[derive(Serialize)]
pub struct UserSearchResult {
    pub id: String,
    pub username: String,
}

/// Create or replace invite code for a wallet (4-digit for now). Admin only.
/// POST /api/wallets/:wallet_id/invite
#[derive(Serialize)]
pub struct CreateInviteResponse {
    pub code: String,
}

pub async fn create_wallet_invite(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<(StatusCode, Json<CreateInviteResponse>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;

    // 4-digit numeric code (0000–9999)
    let code = format!("{:04}", (Uuid::new_v4().as_u128() % 10000) as u32);

    // Create invite code with 5 minute expiration
    sqlx::query(
        r#"
        INSERT INTO wallet_invite_codes (wallet_id, code, created_by, created_at)
        VALUES ($1, $2, $3, NOW())
        ON CONFLICT (wallet_id) DO UPDATE 
        SET code = EXCLUDED.code, 
            created_at = NOW(), 
            created_by = EXCLUDED.created_by
        "#
    )
    .bind(wallet_uuid)
    .bind(&code)
    .bind(auth_user.user_id)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("create_wallet_invite: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create invite code"})),
        )
    })?;

    Ok((
        StatusCode::CREATED,
        Json(CreateInviteResponse { code }),
    ))
}

/// Join a wallet using an invite code. Current user is added as member.
/// POST /api/wallets/join (no wallet context; auth only)
#[derive(Deserialize)]
pub struct JoinWalletRequest {
    pub code: String,
}

pub async fn join_wallet_by_code(
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<JoinWalletRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let code = payload.code.trim();
    if code.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Code is required"})),
        ));
    }

    let wallet_id_row: Option<(Uuid,)> = sqlx::query_as(
        r#"
        SELECT wallet_id 
        FROM wallet_invite_codes 
        WHERE code = $1 
          AND created_at > NOW() - INTERVAL '5 minutes'
        "#
    )
    .bind(code)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("join_wallet_by_code lookup: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let (wallet_uuid,) = wallet_id_row.ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST, // Changed from NOT_FOUND to BAD_REQUEST to ensure frontend shows it as an input error
            Json(serde_json::json!({"error": "Invalid or expired invite code"})),
        )
    })?;

    // One-time use: Delete code after successful lookup (but before joining to prevent race conditions slightly)
    // Actually, safer to delete AFTER joining? Or before?
    // If we delete before and join fails, code is lost.
    // If we delete after and race happens, two people might join.
    // Given "one time use", let's try to delete it atomically.
    // We can't easily do "select and delete" returning data in one generic query step with the existing structure easily without a transaction.
    // Let's rely on the previous SELECT for validation and issue a DELETE now.
    // A race condition is acceptable for now (two people joining within milliseconds).
    sqlx::query("DELETE FROM wallet_invite_codes WHERE wallet_id = $1 AND code = $2")
        .bind(wallet_uuid)
        .bind(code)
        .execute(&*state.db_pool)
        .await
        .ok(); // Ignore delete errors (e.g. already deleted)

    // Check if already a member
    let already: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)"
    )
    .bind(wallet_uuid)
    .bind(auth_user.user_id)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("join_wallet_by_code check: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    if already {
        return Ok((
            StatusCode::OK,
            Json(serde_json::json!({"message": "Already a member of this wallet", "wallet_id": wallet_uuid.to_string()})),
        ));
    }

    // POLICY: New invited users MUST start as 'member', never 'owner' or 'admin'.
    let role = "member";
    let event_data = serde_json::json!({ "user_id": auth_user.user_id.to_string(), "role": role });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        auth_user.user_id,
        "WALLET_USER_ADDED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("join_wallet_by_code apply: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to join wallet"})),
        )
    })?;

    websocket::broadcast_wallet_change(
        &state.broadcast_tx,
        wallet_uuid,
        "wallet_user_added",
        &serde_json::json!({
            "wallet_id": wallet_uuid.to_string(),
            "user_id": auth_user.user_id.to_string(),
            "role": role
        }).to_string(),
    );

    Ok((
        StatusCode::CREATED,
        Json(serde_json::json!({"message": "Joined wallet successfully", "wallet_id": wallet_uuid.to_string()})),
    ))
}

/// List users in a wallet (requires wallet admin when called from user API)
pub async fn list_wallet_users(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<WalletUsersResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;

    // When called from user-facing API, require admin. Admin panel callers have is_admin and bypass.
    let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;

    let users = sqlx::query(
        r#"
        SELECT wu.id, wu.wallet_id, wu.user_id, u.username, wu.role, wu.subscribed_at
        FROM wallet_users wu
        LEFT JOIN users_projection u ON u.id = wu.user_id
        WHERE wu.wallet_id = $1
        ORDER BY wu.subscribed_at DESC
        "#
    )
    .bind(wallet_uuid)
    .map(|row: sqlx::postgres::PgRow| WalletUser {
        id: row.get::<Uuid, _>("id").to_string(),
        wallet_id: row.get::<Uuid, _>("wallet_id").to_string(),
        user_id: row.get::<Uuid, _>("user_id").to_string(),
        username: row.try_get::<String, _>("username").ok(),
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

    // Emit event and apply to projection
    let event_data = serde_json::json!({ "user_id": user_id, "role": payload.role });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        user_uuid,
        "WALLET_USER_ROLE_CHANGED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("Error updating wallet user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update wallet user"})),
        )
    })?;

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

    // Emit event and apply to projection
    let event_data = serde_json::json!({ "user_id": user_id });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        user_uuid,
        "WALLET_USER_REMOVED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("Error removing user from wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to remove user from wallet"})),
        )
    })?;

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

// --- Me: permissions and settings (wallet-scoped, require wallet context) ---

#[derive(Serialize)]
pub struct MyPermissionsResponse {
    pub actions: Vec<String>,
}

/// GET /api/wallets/:wallet_id/me/permissions?resource_type=contact&resource_id=xxx (optional)
pub async fn get_my_permissions(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
    Query(params): Query<std::collections::HashMap<String, String>>,
) -> Result<Json<MyPermissionsResponse>, (StatusCode, Json<serde_json::Value>)> {
    if wallet_context.user_role == "owner" || wallet_context.user_role == "admin" {
        let all: Vec<String> = vec![
            "contact:create".into(), "contact:read".into(), "contact:update".into(), "contact:delete".into(),
            "transaction:create".into(), "transaction:read".into(), "transaction:update".into(), "transaction:delete".into(), "transaction:close".into(),
            "events:read".into(),
            "wallet:read".into(), "wallet:update".into(), "wallet:delete".into(), "wallet:manage_members".into(),
        ];
        return Ok(Json(MyPermissionsResponse { actions: all }));
    }
    let wallet_id = wallet_context.wallet_id;
    let resource_type = match params.get("resource_type").map(|s| s.as_str()) {
        Some("contact") => ResourceType::Contact,
        Some("transaction") => ResourceType::Transaction,
        Some("events") => ResourceType::Events,
        Some("wallet") => ResourceType::Wallet,
        _ => ResourceType::Contact,
    };
    let resource_id = params
        .get("resource_id")
        .and_then(|s| Uuid::parse_str(s).ok());
    let actions = permission_service::resolve_allowed_actions(
        &*state.db_pool,
        wallet_id,
        auth_user.user_id,
        resource_type,
        resource_id,
    )
    .await
    .map_err(|e| {
        tracing::error!("resolve_allowed_actions error: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to resolve permissions"})),
        )
    })?;
    Ok(Json(MyPermissionsResponse {
        actions: actions.into_iter().collect(),
    }))
}

#[derive(Serialize, Deserialize)]
pub struct MyWalletSettingsResponse {
    pub default_contact_group_ids: Vec<String>,
    pub default_transaction_group_ids: Vec<String>,
}

/// GET /api/wallets/:wallet_id/me/settings
pub async fn get_my_wallet_settings(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<MyWalletSettingsResponse>, (StatusCode, Json<serde_json::Value>)> {
    let row = sqlx::query(
        "SELECT default_contact_group_ids, default_transaction_group_ids FROM user_wallet_settings WHERE wallet_id = $1 AND user_id = $2",
    )
    .bind(wallet_context.wallet_id)
    .bind(auth_user.user_id)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error fetching wallet settings: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;
    let (contact_ids, transaction_ids) = if let Some(r) = row {
        let c: Vec<Uuid> = r.get("default_contact_group_ids");
        let t: Vec<Uuid> = r.get("default_transaction_group_ids");
        (c.into_iter().map(|u| u.to_string()).collect(), t.into_iter().map(|u| u.to_string()).collect())
    } else {
        (Vec::new(), Vec::new())
    };
    Ok(Json(MyWalletSettingsResponse {
        default_contact_group_ids: contact_ids,
        default_transaction_group_ids: transaction_ids,
    }))
}

#[derive(Deserialize)]
pub struct PutMyWalletSettingsRequest {
    pub default_contact_group_ids: Option<Vec<String>>,
    pub default_transaction_group_ids: Option<Vec<String>>,
}

/// PUT /api/wallets/:wallet_id/me/settings
pub async fn put_my_wallet_settings(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<PutMyWalletSettingsRequest>,
) -> Result<Json<MyWalletSettingsResponse>, (StatusCode, Json<serde_json::Value>)> {
    let contact_ids: Vec<Uuid> = payload
        .default_contact_group_ids
        .unwrap_or_default()
        .into_iter()
        .filter_map(|s| Uuid::parse_str(&s).ok())
        .collect();
    let transaction_ids: Vec<Uuid> = payload
        .default_transaction_group_ids
        .unwrap_or_default()
        .into_iter()
        .filter_map(|s| Uuid::parse_str(&s).ok())
        .collect();
    sqlx::query(
        r#"
        INSERT INTO user_wallet_settings (wallet_id, user_id, default_contact_group_ids, default_transaction_group_ids)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (wallet_id, user_id) DO UPDATE SET
            default_contact_group_ids = $3,
            default_transaction_group_ids = $4
        "#,
    )
    .bind(wallet_context.wallet_id)
    .bind(auth_user.user_id)
    .bind(&contact_ids)
    .bind(&transaction_ids)
    .execute(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error upserting wallet settings: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;
    Ok(Json(MyWalletSettingsResponse {
        default_contact_group_ids: contact_ids.into_iter().map(|u| u.to_string()).collect(),
        default_transaction_group_ids: transaction_ids.into_iter().map(|u| u.to_string()).collect(),
    }))
}

// --- User groups, contact groups, permission matrix (wallet admin only) ---

#[derive(Serialize)]
pub struct UserGroupResponse {
    pub id: String,
    pub wallet_id: String,
    pub name: String,
    pub is_system: bool,
}

#[derive(Serialize)]
pub struct ContactGroupResponse {
    pub id: String,
    pub wallet_id: String,
    pub name: String,
    #[serde(rename = "type")]
    pub type_: String,
    pub is_system: bool,
}

#[derive(Deserialize)]
pub struct CreateUserGroupRequest {
    pub name: String,
}

#[derive(Deserialize)]
pub struct UpdateUserGroupRequest {
    pub name: String,
}

#[derive(Deserialize)]
pub struct CreateContactGroupRequest {
    pub name: String,
}

#[derive(Deserialize)]
pub struct UpdateContactGroupRequest {
    pub name: String,
}

#[derive(Deserialize)]
pub struct AddUserGroupMemberRequest {
    pub username: String,
}

#[derive(Deserialize)]
pub struct AddContactGroupMemberRequest {
    pub contact_id: String,
}

#[derive(Serialize)]
pub struct PermissionActionResponse {
    pub id: i16,
    pub name: String,
    pub resource: String,
}

#[derive(Serialize)]
pub struct MatrixEntry {
    pub user_group_id: String,
    pub contact_group_id: String,
    pub action_names: Vec<String>,
}

#[derive(Deserialize)]
pub struct PutPermissionMatrixRequest {
    pub user_group_id: String,
    pub contact_group_id: String,
    pub action_names: Vec<String>,
}

async fn require_wallet_admin(
    state: &AppState,
    wallet_id: Uuid,
    auth_user: &AuthUser,
) -> Result<(), (StatusCode, Json<serde_json::Value>)> {
    let _ = require_wallet_role_at_least(state, wallet_id, auth_user, "admin").await?;
    Ok(())
}

/// Returns error if the user group is system (all_users). System groups cannot be edited or have members changed.
async fn reject_system_user_group(
    state: &AppState,
    wallet_id: Uuid,
    group_id: Uuid,
) -> Result<(), (StatusCode, Json<serde_json::Value>)> {
    let is_system: Option<bool> = sqlx::query_scalar(
        "SELECT is_system FROM user_groups WHERE id = $1 AND wallet_id = $2",
    )
    .bind(group_id)
    .bind(wallet_id)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("reject_system_user_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check group"})),
        )
    })?;
    if is_system == Some(true) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "System group all_users cannot be modified"})),
        ));
    }
    Ok(())
}

/// Returns error if the contact group is system (all_contacts). System groups cannot be edited or have members changed.
async fn reject_system_contact_group(
    state: &AppState,
    wallet_id: Uuid,
    group_id: Uuid,
) -> Result<(), (StatusCode, Json<serde_json::Value>)> {
    let is_system: Option<bool> = sqlx::query_scalar(
        "SELECT is_system FROM contact_groups WHERE id = $1 AND wallet_id = $2",
    )
    .bind(group_id)
    .bind(wallet_id)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("reject_system_contact_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check group"})),
        )
    })?;
    if is_system == Some(true) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "System group all_contacts cannot be modified"})),
        ));
    }
    Ok(())
}

/// GET /api/wallets/:wallet_id/user-groups
pub async fn list_user_groups(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<UserGroupResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    let rows = sqlx::query(
        "SELECT id, wallet_id, name, is_system FROM user_groups WHERE wallet_id = $1 ORDER BY is_system DESC, name",
    )
    .bind(wallet_uuid)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("list_user_groups: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to list user groups"})),
        )
    })?;

    let list: Vec<UserGroupResponse> = rows
        .into_iter()
        .map(|row: sqlx::postgres::PgRow| UserGroupResponse {
            id: row.get::<Uuid, _>("id").to_string(),
            wallet_id: row.get::<Uuid, _>("wallet_id").to_string(),
            name: row.get("name"),
            is_system: row.get("is_system"),
        })
        .collect();
    Ok(Json(list))
}

/// POST /api/wallets/:wallet_id/user-groups
pub async fn create_user_group(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<CreateUserGroupRequest>,
) -> Result<(StatusCode, Json<UserGroupResponse>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    let name = payload.name.trim();
    if name.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Name is required"})),
        ));
    }
    if name.eq_ignore_ascii_case("all_users") {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Cannot create group named all_users"})),
        ));
    }

    let id = Uuid::new_v4();
    let event_data = serde_json::json!({ "name": name });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        id,
        "USER_GROUP_CREATED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("create_user_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create user group"})),
        )
    })?;

    Ok((
        StatusCode::CREATED,
        Json(UserGroupResponse {
            id: id.to_string(),
            wallet_id: wallet_id.clone(),
            name: name.to_string(),
            is_system: false,
        }),
    ))
}

/// PUT /api/wallets/:wallet_id/user-groups/:group_id
pub async fn update_user_group(
    Path((wallet_id, group_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<UpdateUserGroupRequest>,
) -> Result<Json<UserGroupResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;
    reject_system_user_group(&state, wallet_uuid, group_uuid).await?;

    let name = payload.name.trim();
    if name.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Name is required"})),
        ));
    }

    let event_data = serde_json::json!({ "name": name });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        "USER_GROUP_RENAMED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("update_user_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update user group"})),
        )
    })?;

    Ok(Json(UserGroupResponse {
        id: group_id,
        wallet_id: wallet_id.clone(),
        name: name.to_string(),
        is_system: false,
    }))
}

/// DELETE /api/wallets/:wallet_id/user-groups/:group_id
pub async fn delete_user_group(
    Path((wallet_id, group_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;
    reject_system_user_group(&state, wallet_uuid, group_uuid).await?;

    let event_data = serde_json::json!({});
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        "USER_GROUP_DELETED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("delete_user_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to delete user group"})),
        )
    })?;

    Ok((
        StatusCode::OK,
        Json(serde_json::json!({"message": "User group deleted"})),
    ))
}

#[derive(Serialize)]
pub struct UserGroupMemberResponse {
    pub user_id: String,
    pub username: Option<String>,
}

/// GET /api/wallets/:wallet_id/user-groups/:group_id/members
pub async fn list_user_group_members(
    Path((wallet_id, group_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<UserGroupMemberResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    let rows = sqlx::query(
        r#"
        SELECT ugm.user_id, u.username
        FROM user_group_members ugm
        INNER JOIN user_groups ug ON ug.id = ugm.user_group_id
        LEFT JOIN users_projection u ON u.id = ugm.user_id
        WHERE ug.id = $1 AND ug.wallet_id = $2
        "#,
    )
    .bind(group_uuid)
    .bind(wallet_uuid)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("list_user_group_members: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to list members"})),
        )
    })?;

    let list: Vec<UserGroupMemberResponse> = rows
        .into_iter()
        .map(|row: sqlx::postgres::PgRow| UserGroupMemberResponse {
            user_id: row.get::<Uuid, _>("user_id").to_string(),
            username: row.try_get::<String, _>("username").ok(),
        })
        .collect();
    Ok(Json(list))
}

/// POST /api/wallets/:wallet_id/user-groups/:group_id/members
pub async fn add_user_group_member(
    Path((wallet_id, group_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<AddUserGroupMemberRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    
    let username = payload.username.trim();
    if username.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Username is required"})),
        ));
    }

    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;
    reject_system_user_group(&state, wallet_uuid, group_uuid).await?;

    // Look up user by username
    let user_uuid: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM users_projection WHERE username = $1 LIMIT 1",
    )
    .bind(username)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("add_user_group_member lookup: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let user_uuid = user_uuid.ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "User not found"})),
        )
    })?;

    let group_row = sqlx::query(
        "SELECT id FROM user_groups WHERE id = $1 AND wallet_id = $2",
    )
    .bind(group_uuid)
    .bind(wallet_uuid)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("add_user_group_member: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to add member"})),
        )
    })?;

    if group_row.is_none() {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "User group not found"})),
        ));
    }

    // User must be a member of the wallet
    let in_wallet = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet_uuid)
    .bind(user_uuid)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("add_user_group_member: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to add member"})),
        )
    })?;

    if !in_wallet {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "User is not a member of this wallet"})),
        ));
    }

    let event_data = serde_json::json!({ "user_id": user_uuid.to_string() });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        "USER_GROUP_MEMBER_ADDED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("add_user_group_member: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to add member"})),
        )
    })?;

    Ok((
        StatusCode::CREATED,
        Json(serde_json::json!({"message": "Member added"})),
    ))
}

/// DELETE /api/wallets/:wallet_id/user-groups/:group_id/members/:user_id
pub async fn remove_user_group_member(
    Path((wallet_id, group_id, user_id)): Path<(String, String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    let _user_uuid = Uuid::parse_str(&user_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid user_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;
    reject_system_user_group(&state, wallet_uuid, group_uuid).await?;

    let event_data = serde_json::json!({ "user_id": user_id });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        "USER_GROUP_MEMBER_REMOVED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("remove_user_group_member: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to remove member"})),
        )
    })?;

    Ok((
        StatusCode::OK,
        Json(serde_json::json!({"message": "Member removed"})),
    ))
}

/// GET /api/wallets/:wallet_id/contact-groups
pub async fn list_contact_groups(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<ContactGroupResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    let rows = sqlx::query(
        "SELECT id, wallet_id, name, type, is_system FROM contact_groups WHERE wallet_id = $1 ORDER BY is_system DESC, name",
    )
    .bind(wallet_uuid)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("list_contact_groups: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to list contact groups"})),
        )
    })?;

    let list: Vec<ContactGroupResponse> = rows
        .into_iter()
        .map(|row: sqlx::postgres::PgRow| ContactGroupResponse {
            id: row.get::<Uuid, _>("id").to_string(),
            wallet_id: row.get::<Uuid, _>("wallet_id").to_string(),
            name: row.get("name"),
            type_: row.get::<String, _>("type"),
            is_system: row.get("is_system"),
        })
        .collect();
    Ok(Json(list))
}

/// POST /api/wallets/:wallet_id/contact-groups
pub async fn create_contact_group(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<CreateContactGroupRequest>,
) -> Result<(StatusCode, Json<ContactGroupResponse>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    let name = payload.name.trim();
    if name.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Name is required"})),
        ));
    }
    if name.eq_ignore_ascii_case("all_contacts") {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Cannot create group named all_contacts"})),
        ));
    }

    let id = Uuid::new_v4();
    let event_data = serde_json::json!({ "name": name });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        id,
        "CONTACT_GROUP_CREATED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("create_contact_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create contact group"})),
        )
    })?;

    Ok((
        StatusCode::CREATED,
        Json(ContactGroupResponse {
            id: id.to_string(),
            wallet_id: wallet_id.clone(),
            name: name.to_string(),
            type_: "static".to_string(),
            is_system: false,
        }),
    ))
}

/// PUT /api/wallets/:wallet_id/contact-groups/:group_id
pub async fn update_contact_group(
    Path((wallet_id, group_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<UpdateContactGroupRequest>,
) -> Result<Json<ContactGroupResponse>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;
    reject_system_contact_group(&state, wallet_uuid, group_uuid).await?;

    let name = payload.name.trim();
    if name.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Name is required"})),
        ));
    }

    let event_data = serde_json::json!({ "name": name });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        "CONTACT_GROUP_RENAMED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("update_contact_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to update contact group"})),
        )
    })?;

    Ok(Json(ContactGroupResponse {
        id: group_id,
        wallet_id: wallet_id.clone(),
        name: name.to_string(),
        type_: "static".to_string(),
        is_system: false,
    }))
}

/// DELETE /api/wallets/:wallet_id/contact-groups/:group_id
pub async fn delete_contact_group(
    Path((wallet_id, group_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;
    reject_system_contact_group(&state, wallet_uuid, group_uuid).await?;

    let event_data = serde_json::json!({});
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        "CONTACT_GROUP_DELETED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("delete_contact_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to delete contact group"})),
        )
    })?;

    Ok((
        StatusCode::OK,
        Json(serde_json::json!({"message": "Contact group deleted"})),
    ))
}

#[derive(Serialize)]
pub struct ContactGroupMemberResponse {
    pub contact_id: String,
}

/// GET /api/wallets/:wallet_id/contact-groups/:group_id/members
pub async fn list_contact_group_members(
    Path((wallet_id, group_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<ContactGroupMemberResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    let rows = sqlx::query(
        r#"
        SELECT cgm.contact_id
        FROM contact_group_members cgm
        INNER JOIN contact_groups cg ON cg.id = cgm.contact_group_id
        WHERE cg.id = $1 AND cg.wallet_id = $2
        "#,
    )
    .bind(group_uuid)
    .bind(wallet_uuid)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("list_contact_group_members: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to list members"})),
        )
    })?;

    let list: Vec<ContactGroupMemberResponse> = rows
        .into_iter()
        .map(|row: sqlx::postgres::PgRow| ContactGroupMemberResponse {
            contact_id: row.get::<Uuid, _>("contact_id").to_string(),
        })
        .collect();
    Ok(Json(list))
}

/// POST /api/wallets/:wallet_id/contact-groups/:group_id/members
pub async fn add_contact_group_member(
    Path((wallet_id, group_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<AddContactGroupMemberRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    let _contact_uuid = Uuid::parse_str(&payload.contact_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid contact_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;
    reject_system_contact_group(&state, wallet_uuid, group_uuid).await?;

    let group_row = sqlx::query(
        "SELECT id FROM contact_groups WHERE id = $1 AND wallet_id = $2",
    )
    .bind(group_uuid)
    .bind(wallet_uuid)
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("add_contact_group_member: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to add member"})),
        )
    })?;

    if group_row.is_none() {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Contact group not found"})),
        ));
    }

    let event_data = serde_json::json!({ "contact_id": payload.contact_id });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        "CONTACT_GROUP_MEMBER_ADDED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("add_contact_group_member: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to add member"})),
        )
    })?;

    Ok((
        StatusCode::CREATED,
        Json(serde_json::json!({"message": "Member added"})),
    ))
}

/// DELETE /api/wallets/:wallet_id/contact-groups/:group_id/members/:contact_id
pub async fn remove_contact_group_member(
    Path((wallet_id, group_id, contact_id)): Path<(String, String, String)>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<(StatusCode, Json<serde_json::Value>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    let group_uuid = Uuid::parse_str(&group_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid group_id: {}", e)})),
        )
    })?;
    let _contact_uuid = Uuid::parse_str(&contact_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid contact_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;
    reject_system_contact_group(&state, wallet_uuid, group_uuid).await?;

    let event_data = serde_json::json!({ "contact_id": contact_id });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        "CONTACT_GROUP_MEMBER_REMOVED",
        event_data,
    )
    .await
    .map_err(|e| {
        tracing::error!("remove_contact_group_member: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to remove member"})),
        )
    })?;

    Ok((
        StatusCode::OK,
        Json(serde_json::json!({"message": "Member removed"})),
    ))
}

/// GET /api/wallets/:wallet_id/permission-actions
pub async fn list_permission_actions(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<PermissionActionResponse>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    let rows = sqlx::query("SELECT id, name, resource FROM permission_actions ORDER BY resource, name")
        .fetch_all(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("list_permission_actions: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to list permission actions"})),
            )
        })?;

    let list: Vec<PermissionActionResponse> = rows
        .into_iter()
        .map(|row: sqlx::postgres::PgRow| PermissionActionResponse {
            id: row.get("id"),
            name: row.get("name"),
            resource: row.get("resource"),
        })
        .collect();
    Ok(Json(list))
}

/// GET /api/wallets/:wallet_id/permission-matrix
pub async fn get_permission_matrix(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
) -> Result<Json<Vec<MatrixEntry>>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    let rows = sqlx::query(
        r#"
        SELECT m.user_group_id, m.contact_group_id,
               array_agg(pa.name ORDER BY pa.name) as action_names
        FROM group_permission_matrix m
        JOIN permission_actions pa ON pa.id = m.permission_action_id
        JOIN user_groups ug ON ug.id = m.user_group_id AND ug.wallet_id = $1
        JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.wallet_id = $1
        GROUP BY m.user_group_id, m.contact_group_id
        "#,
    )
    .bind(wallet_uuid)
    .fetch_all(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("get_permission_matrix: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to get permission matrix"})),
        )
    })?;

    let list: Vec<MatrixEntry> = rows
        .into_iter()
        .map(|row: sqlx::postgres::PgRow| {
            let arr: Vec<String> = row.get("action_names");
            MatrixEntry {
                user_group_id: row.get::<Uuid, _>("user_group_id").to_string(),
                contact_group_id: row.get::<Uuid, _>("contact_group_id").to_string(),
                action_names: arr,
            }
        })
        .collect();
    Ok(Json(list))
}

#[derive(Deserialize)]
pub struct PutPermissionMatrixBulkRequest {
    pub entries: Vec<PutPermissionMatrixRequest>,
}

/// PUT /api/wallets/:wallet_id/permission-matrix
/// Body: { "entries": [ { "user_group_id", "contact_group_id", "action_names": [] } ] }
pub async fn put_permission_matrix(
    Path(wallet_id): Path<String>,
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<PutPermissionMatrixBulkRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    let wallet_uuid = Uuid::parse_str(&wallet_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid wallet_id: {}", e)})),
        )
    })?;
    require_wallet_admin(&state, wallet_uuid, &auth_user).await?;

    for entry in &payload.entries {
        if let Err(e) = validate_permission_dependencies(&entry.action_names) {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": e})),
            ));
        }

        let ug_id = Uuid::parse_str(&entry.user_group_id).map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid user_group_id: {}", e)})),
            )
        })?;
        let cg_id = Uuid::parse_str(&entry.contact_group_id).map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid contact_group_id: {}", e)})),
            )
        })?;

        let ug_ok = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM user_groups WHERE id = $1 AND wallet_id = $2)",
        )
        .bind(ug_id)
        .bind(wallet_uuid)
        .fetch_one(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("put_permission_matrix: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to update matrix"})),
            )
        })?;
        let cg_ok = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM contact_groups WHERE id = $1 AND wallet_id = $2)",
        )
        .bind(cg_id)
        .bind(wallet_uuid)
        .fetch_one(&*state.db_pool)
        .await
        .map_err(|e| {
            tracing::error!("put_permission_matrix: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to update matrix"})),
            )
        })?;

        if !ug_ok || !cg_ok {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "User group or contact group not in this wallet"})),
            ));
        }

        let event_data = serde_json::json!({
            "user_group_id": entry.user_group_id,
            "contact_group_id": entry.contact_group_id,
            "action_names": entry.action_names,
        });
        sync::insert_permission_event_and_apply(
            &state,
            auth_user.user_id,
            wallet_uuid,
            ug_id,
            "PERMISSION_MATRIX_SET",
            event_data,
        )
        .await
        .map_err(|e| {
            tracing::error!("put_permission_matrix: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to update matrix"})),
            )
        })?;
    }

    Ok(Json(serde_json::json!({"message": "Permission matrix updated"})))
}
