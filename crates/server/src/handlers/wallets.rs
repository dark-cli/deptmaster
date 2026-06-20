use crate::database::error::DbError;
use crate::database::repository::{Database, DatabaseRepository};
use crate::handlers::responses::insufficient_permission_response;
use crate::handlers::sync;
use crate::middleware::auth::AuthUser;
use crate::middleware::wallet_context::WalletContext;
use crate::permissions::PermissionModel;
use crate::websocket;
use crate::AppState;
use axum::{
    extract::{Extension, Path, Query, State},
    http::StatusCode,
    response::Json,
};
use domain::DomainEvent;
use domain::{PermissionContext, Resource, WalletRole};
use serde::{Deserialize, Deserializer, Serialize};
use uuid::Uuid;

// Custom deserializer for WalletRole from string
fn deserialize_wallet_role<'de, D>(deserializer: D) -> Result<WalletRole, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    WalletRole::from_str(&s).ok_or_else(|| {
        serde::de::Error::custom("Invalid wallet role. Must be 'owner', 'admin', or 'member'")
    })
}

/// Check if user is a wallet owner (hardcoded bypass)
/// Owners have unrestricted access; this is checked via wallet_owners table
async fn is_wallet_owner(
    state: &AppState,
    wallet_id: Uuid,
    user_id: Uuid,
) -> Result<bool, (StatusCode, Json<serde_json::Value>)> {
    sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM wallet_owners WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet owner: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })
}

/// Check user is wallet owner (old role-based check, deprecated)
/// Kept for backward compatibility during transition period
#[deprecated(since = "0.2.0", note = "Use is_wallet_owner() and permission matrix instead")]
async fn check_wallet_role(
    state: &AppState,
    wallet_id: Uuid,
    auth_user: &AuthUser,
    required_role: WalletRole,
) -> Result<WalletRole, (StatusCode, Json<serde_json::Value>)> {
    // System admins bypass all checks
    if auth_user.is_admin {
        return Ok(WalletRole::Owner);
    }

    let db = Database::new((*state.db_pool).clone());
    let role_str = db
        .get_wallet_user_role(wallet_id, auth_user.user_id)
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

    let user_role = WalletRole::from_str(&role_str).unwrap_or(WalletRole::Member);

    // Use type-safe comparison: user_role must meet or exceed required_role
    if user_role.can_perform(required_role) {
        Ok(user_role)
    } else {
        Err((
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "Insufficient wallet permissions"
            })),
        ))
    }
}

/// Check if user can perform an operation by checking a synthetic event permission
/// Uses the permission event system for consistent permission checking
async fn check_event_permissions(
    state: &AppState,
    wallet_id: Uuid,
    auth_user: &AuthUser,
    user_role: WalletRole,
    event: &DomainEvent,
) -> Result<bool, (StatusCode, Json<serde_json::Value>)> {
    // Owner/Admin bypass all checks
    if user_role.is_admin_or_higher() {
        return Ok(true);
    }

    let perm_ctx = PermissionContext::new(wallet_id, auth_user.user_id, user_role);
    let perm_model = PermissionModel::new((*state.db_pool).clone());

    let denied = perm_model
        .get_denied_event_ids(&perm_ctx, std::slice::from_ref(&event))
        .await
        .map_err(|e| {
            tracing::error!("Permission check error: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to check permissions"})),
            )
        })?;

    Ok(denied.is_empty())
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
    #[serde(deserialize_with = "deserialize_wallet_role")]
    pub role: WalletRole,
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
    create_wallet_impl(&state, auth_user.user_id, payload).await
}

/// Helper to initialize default permissions for a new wallet
/// - Creates all_users group for members (default: contact:read, transaction:read)
/// - Creates __owners__ system group for owners (all permissions)
/// - Adds creator as owner to both wallet_owners table and __owners__ group
async fn initialize_wallet_permissions(
    db: &Database,
    wallet_id: Uuid,
    owner_user_id: Uuid,
) -> Result<(), DbError> {
    use crate::database::repository::DatabaseRepository;

    // 1. Create all_users system user group (for members)
    let all_users_group = db.create_user_group(wallet_id, "all_users", true).await?;

    // 2. Create __owners__ system user group (cannot be modified by admins)
    let owners_group = db.create_user_group(wallet_id, "__owners__", true).await?;

    // 3. Add owner to owners group
    db.add_user_group_member(owners_group, owner_user_id)
        .await?;

    // 4. Create all_contacts system contact group
    let all_contacts = db
        .create_contact_group(wallet_id, "all_contacts", "static", true)
        .await?;

    // 5. Grant default permissions: all_users (members) get READ only
    let member_actions = ["contact:read", "transaction:read"];
    for action in member_actions {
        if let Some(aid) = db.get_permission_action_id(action).await? {
            db.grant_permission(all_users_group, all_contacts, aid)
                .await?;
        }
    }

    // 6. Grant full permissions to owners group (all actions on all_contacts)
    let owner_actions = [
        "contact:create",
        "contact:read",
        "contact:update",
        "contact:delete",
        "contact:edit",
        "transaction:create",
        "transaction:read",
        "transaction:update",
        "transaction:delete",
        "user_group:create",
        "user_group:read",
        "user_group:update",
        "user_group:delete",
        "contact_group:create",
        "contact_group:read",
        "contact_group:update",
        "contact_group:delete",
    ];

    for action in owner_actions {
        if let Some(aid) = db.get_permission_action_id(action).await? {
            db.grant_permission(owners_group, all_contacts, aid).await?;
        }
    }

    Ok(())
}

/// Create a new wallet (Admin only)
pub async fn create_wallet(
    State(state): State<AppState>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<CreateWalletRequest>,
) -> Result<(StatusCode, Json<CreateWalletResponse>), (StatusCode, Json<serde_json::Value>)> {
    create_wallet_impl(&state, auth_user.user_id, payload).await
}

async fn create_wallet_impl(
    state: &AppState,
    user_id: Uuid,
    payload: CreateWalletRequest,
) -> Result<(StatusCode, Json<CreateWalletResponse>), (StatusCode, Json<serde_json::Value>)> {
    let wallet_id = Uuid::new_v4();
    let db = Database::new((*state.db_pool).clone());

    db.create_wallet(
        wallet_id,
        payload.name.clone(),
        payload.description.clone(),
        Some(user_id),
    )
    .await
    .map_err(|e| {
        tracing::error!("Error creating wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to create wallet"})),
        )
    })?;

    db.add_wallet_user(wallet_id, user_id, WalletRole::Owner.as_str().to_string())
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

    db.add_wallet_owner(wallet_id, user_id).await.map_err(|e| {
        tracing::error!("Failed to add wallet owner: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to initialize wallet ownership"})),
        )
    })?;

    initialize_wallet_permissions(&db, wallet_id, user_id)
        .await
        .map_err(|e| {
            tracing::error!(
                "Failed to initialize wallet permissions for {}: {:?}",
                wallet_id,
                e
            );
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to initialize wallet permissions"})),
            )
        })?;

    Ok((StatusCode::CREATED, Json(response)))
}

/// List all wallets (Admin only)
pub async fn list_wallets(
    State(state): State<AppState>,
) -> Result<Json<WalletListResponse>, (StatusCode, Json<serde_json::Value>)> {
    let db = Database::new((*state.db_pool).clone());

    let wallets_db = db.get_all_active_wallets().await.map_err(|e| {
        tracing::error!("Error fetching wallets: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch wallets"})),
        )
    })?;

    let wallets = wallets_db
        .into_iter()
        .map(|w| Wallet {
            id: w.id.to_string(),
            name: w.name,
            description: w.description,
            created_at: w.created_at.and_utc().to_rfc3339(),
            updated_at: w.updated_at.and_utc().to_rfc3339(),
            created_by: w.created_by.map(|u| u.to_string()),
            is_active: w.is_active,
        })
        .collect();

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

    let db = Database::new((*state.db_pool).clone());

    let wallet = db.get_wallet(wallet_uuid).await.map_err(|e| {
        tracing::error!("Error fetching wallet: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    match wallet {
        Some(w) if w.is_active => Ok(Json(Wallet {
            id: w.id.to_string(),
            name: w.name,
            description: w.description,
            created_at: w.created_at.and_utc().to_rfc3339(),
            updated_at: w.updated_at.and_utc().to_rfc3339(),
            created_by: w.created_by.map(|u| u.to_string()),
            is_active: w.is_active,
        })),
        _ => Err((
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
    let _role = check_wallet_role(&state, wallet_uuid, &auth_user, WalletRole::Owner).await?;

    let db = Database::new((*state.db_pool).clone());

    // Check if wallet exists
    let wallet_exists = db.wallet_exists(wallet_uuid).await.map_err(|e| {
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

    if payload.name.is_none() && payload.description.is_none() && payload.is_active.is_none() {
        return Ok((
            StatusCode::OK,
            Json(serde_json::json!({"message": "No changes provided"})),
        ));
    }

    let updated = db
        .update_wallet(
            wallet_uuid,
            payload.name.as_deref(),
            payload.description.as_deref(),
            payload.is_active,
        )
        .await
        .map_err(|e| {
            tracing::error!("Error updating wallet: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to update wallet"})),
            )
        })?;

    if !updated {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Wallet not found"})),
        ));
    }

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

    // Check wallet:delete permission (owners bypass via hardcoded check)
    let can_delete = crate::permissions::resolver::can_perform(
        &state.db_pool,
        &PermissionContext {
            wallet_id: wallet_uuid,
            user_id: auth_user.user_id,
            user_role: WalletRole::Member,
        },
        domain::Action::WalletDelete,
        &Resource::Wallet(wallet_uuid),
    )
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet:delete permission: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    if !can_delete {
        return Err((
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "You do not have permission to delete this wallet"
            })),
        ));
    }

    let db = Database::new((*state.db_pool).clone());

    // Soft delete by setting is_active = false
    db.delete_wallet(wallet_uuid).await.map_err(|e| {
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

    // Check wallet:member_add permission (owners bypass via hardcoded check)
    let can_add = crate::permissions::resolver::can_perform(
        &state.db_pool,
        &PermissionContext {
            wallet_id: wallet_uuid,
            user_id: auth_user.user_id,
            user_role: WalletRole::Member,
        },
        domain::Action::WalletMemberAdd,
        &Resource::Wallet(wallet_uuid),
    )
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet:member_add permission: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    if !can_add {
        return Err((
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "You do not have permission to add members to this wallet"
            })),
        ));
    }

    let username = payload.username.trim();
    if username.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Username is required"})),
        ));
    }

    let db = Database::new((*state.db_pool).clone());
    let user = db.get_user_by_username(username).await.map_err(|e| {
        tracing::error!("Error looking up user: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Database error"})),
        )
    })?;

    let user_uuid = user
        .ok_or_else(|| {
            (
                StatusCode::NOT_FOUND,
                Json(serde_json::json!({"error": "User not found."})),
            )
        })?
        .id;

    // New members get role 'member' (read-only by default). Change role later on the member.
    // POLICY: New invited users MUST start as 'member', never 'owner' or 'admin'.
    let role = WalletRole::Member;

    // Check if wallet exists
    let wallet_exists = db.wallet_exists(wallet_uuid).await.map_err(|e| {
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
    let event_data = serde_json::json!({ "user_id": user_uuid.to_string(), "role": role.as_str() });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        user_uuid,
        domain::EventType::WalletUserAdded,
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
            "role": role.as_str()
        })
        .to_string(),
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
    let _role = check_wallet_role(&state, wallet_uuid, &auth_user, WalletRole::Owner).await?;

    let q = params.get("q").map(|s| s.trim()).unwrap_or("").to_string();
    if q.is_empty() {
        return Ok(Json(vec![]));
    }

    let db = Database::new((*state.db_pool).clone());
    let pattern = format!("%{}%", q);

    let users = db.search_users(&pattern, 20).await.map_err(|e| {
        tracing::error!("search_wallet_users: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Search failed"})),
        )
    })?;

    let list: Vec<UserSearchResult> = users
        .into_iter()
        .map(|(id, username)| UserSearchResult {
            id: id.to_string(),
            username,
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
    let _role = check_wallet_role(&state, wallet_uuid, &auth_user, WalletRole::Owner).await?;

    // 4-digit numeric code (0000–9999)
    let code = format!("{:04}", (Uuid::new_v4().as_u128() % 10000) as u32);

    let db = Database::new((*state.db_pool).clone());

    db.upsert_invite_code(wallet_uuid, &code, auth_user.user_id)
        .await
        .map_err(|e| {
            tracing::error!("create_wallet_invite: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to create invite code"})),
            )
        })?;

    Ok((StatusCode::CREATED, Json(CreateInviteResponse { code })))
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

    let db = Database::new((*state.db_pool).clone());

    let wallet_uuid = db
        .get_wallet_by_invite_code(code)
        .await
        .map_err(|e| {
            tracing::error!("join_wallet_by_code lookup: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?
        .ok_or_else(|| {
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "Invalid or expired invite code"})),
            )
        })?;

    // One-time use: Delete code after successful lookup
    let _ = db.delete_invite_code(wallet_uuid, code).await;

    // Check if already a member
    let already = db
        .wallet_user_exists(wallet_uuid, auth_user.user_id)
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
            Json(
                serde_json::json!({"message": "Already a member of this wallet", "wallet_id": wallet_uuid.to_string()}),
            ),
        ));
    }

    // POLICY: New invited users MUST start as 'member', never 'owner' or 'admin'.
    let role = WalletRole::Member;
    let event_data =
        serde_json::json!({ "user_id": auth_user.user_id.to_string(), "role": role.as_str() });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        auth_user.user_id,
        domain::EventType::WalletUserAdded,
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
            "role": role.as_str()
        })
        .to_string(),
    );

    Ok((
        StatusCode::CREATED,
        Json(
            serde_json::json!({"message": "Joined wallet successfully", "wallet_id": wallet_uuid.to_string()}),
        ),
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
    let _role = check_wallet_role(&state, wallet_uuid, &auth_user, WalletRole::Owner).await?;

    let db = Database::new((*state.db_pool).clone());

    let users_db = db
        .list_wallet_users_with_username(wallet_uuid)
        .await
        .map_err(|e| {
            tracing::error!("Error fetching wallet users: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to fetch wallet users"})),
            )
        })?;

    let users = users_db
        .into_iter()
        .map(|u| WalletUser {
            id: u.id.to_string(),
            wallet_id: u.wallet_id.to_string(),
            user_id: u.user_id.to_string(),
            username: u.username,
            role: u.role,
            subscribed_at: u.created_at.and_utc().to_rfc3339(),
        })
        .collect();

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
    let _role = check_wallet_role(&state, wallet_uuid, &auth_user, WalletRole::Owner).await?;

    let user_uuid = Uuid::parse_str(&user_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid user_id: {}", e)})),
        )
    })?;

    // Emit event and apply to projection (payload.role is already validated by deserializer)
    let event_data = serde_json::json!({ "user_id": user_id, "role": payload.role.as_str() });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        user_uuid,
        domain::EventType::WalletUserRoleChanged,
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
            "role": payload.role.as_str()
        })
        .to_string(),
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

    // Check wallet:member_remove permission (owners bypass via hardcoded check)
    let can_remove = crate::permissions::resolver::can_perform(
        &state.db_pool,
        &PermissionContext {
            wallet_id: wallet_uuid,
            user_id: auth_user.user_id,
            user_role: WalletRole::Member,
        },
        domain::Action::WalletMemberRemove,
        &Resource::Wallet(wallet_uuid),
    )
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet:member_remove permission: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check permissions"})),
        )
    })?;

    if !can_remove {
        return Err((
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "You do not have permission to remove members from this wallet"
            })),
        ));
    }

    let user_uuid = Uuid::parse_str(&user_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid user_id: {}", e)})),
        )
    })?;

    // Owner may remove themselves only if there is at least one other owner.
    if auth_user.user_id == user_uuid {
        let db = Database::new((*state.db_pool).clone());

        let role_str = db
            .get_wallet_user_role(wallet_uuid, user_uuid)
            .await
            .map_err(|e| {
                tracing::error!("remove_user_from_wallet role check: {:?}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Failed to remove user from wallet"})),
                )
            })?;

        if let Some(role_str) = role_str {
            if let Some(role) = WalletRole::from_str(&role_str) {
                if role.is_owner() {
                    let owner_count = db.count_wallet_owners(wallet_uuid).await.map_err(|e| {
                        tracing::error!("remove_user_from_wallet owner count: {:?}", e);
                        (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            Json(serde_json::json!({"error": "Failed to remove user from wallet"})),
                        )
                    })?;
                    if owner_count <= 1 {
                        return Err((
                            StatusCode::BAD_REQUEST,
                            Json(serde_json::json!({
                                "error": "Cannot remove the only owner from the wallet. Add another owner first."
                            })),
                        ));
                    }
                }
            }
        }
    }

    // Emit event and apply to projection
    let event_data = serde_json::json!({ "user_id": user_id });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        user_uuid,
        domain::EventType::WalletUserRemoved,
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
        })
        .to_string(),
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

    let db = Database::new((*state.db_pool).clone());

    let wallets_db = db.get_user_wallets(user_id).await.map_err(|e| {
        tracing::error!("Error fetching user wallets: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to fetch wallets"})),
        )
    })?;

    let wallets = wallets_db
        .into_iter()
        .map(|w| Wallet {
            id: w.id.to_string(),
            name: w.name,
            description: w.description,
            created_at: w.created_at.and_utc().to_rfc3339(),
            updated_at: w.updated_at.and_utc().to_rfc3339(),
            created_by: w.created_by.map(|u| u.to_string()),
            is_active: w.is_active,
        })
        .collect();

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
    let wallet_id = wallet_context.wallet_id;

    // Owner/admin have all actions
    let actions: Vec<String> = if wallet_context.user_role.is_admin_or_higher() {
        vec![
            "contact:create".into(),
            "contact:read".into(),
            "contact:update".into(),
            "contact:delete".into(),
            "transaction:create".into(),
            "transaction:read".into(),
            "transaction:update".into(),
            "transaction:delete".into(),
            "transaction:close".into(),
            "wallet:read".into(),
            "wallet:update".into(),
            "wallet:delete".into(),
            "wallet:manage_members".into(),
            "events:read".into(),
        ]
    } else {
        // Use PermissionModel to resolve allowed actions for member role
        let user_role = WalletRole::Member;
        let perm_ctx = PermissionContext::new(wallet_id, auth_user.user_id, user_role);
        let perm_model = PermissionModel::new((*state.db_pool).clone());

        // Get resource from query params
        let resource = match params.get("resource_type").map(|s| s.as_str()) {
            Some("contact") => {
                let resource_id = params
                    .get("resource_id")
                    .and_then(|s| Uuid::parse_str(s).ok());
                match resource_id {
                    Some(id) => Resource::Contact(id),
                    None => Resource::AllContacts,
                }
            }
            Some("transaction") => {
                let resource_id = params
                    .get("resource_id")
                    .and_then(|s| Uuid::parse_str(s).ok());
                match resource_id {
                    Some(id) => Resource::Transaction(id),
                    None => Resource::AllTransactions,
                }
            }
            Some("wallet") => Resource::Wallet(wallet_id),
            _ => Resource::AllContacts,
        };

        // Resolve allowed actions using PermissionModel
        let allowed_actions = perm_model
            .resolve_actions(&perm_ctx, &resource)
            .await
            .map_err(|e| {
                tracing::error!("resolve_actions error: {:?}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Failed to resolve permissions"})),
                )
            })?;

        let mut action_strs: Vec<String> = allowed_actions
            .iter()
            .map(|a| a.as_str().to_string())
            .collect();

        // Events are always viewable (no permission check).
        if !action_strs.contains(&"events:read".to_string()) {
            action_strs.push("events:read".into());
        }

        action_strs
    };

    Ok(Json(MyPermissionsResponse { actions }))
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
    let db = Database::new((*state.db_pool).clone());

    let settings = db
        .get_wallet_user_settings(wallet_context.wallet_id, auth_user.user_id)
        .await
        .map_err(|e| {
            tracing::error!("Error fetching wallet settings: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?;

    let (contact_ids, transaction_ids) = match settings {
        Some((contact, transaction)) => (
            contact.into_iter().map(|u| u.to_string()).collect(),
            transaction.into_iter().map(|u| u.to_string()).collect(),
        ),
        None => (Vec::new(), Vec::new()),
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

    let db = Database::new((*state.db_pool).clone());

    db.upsert_wallet_user_settings(
        wallet_context.wallet_id,
        auth_user.user_id,
        &contact_ids,
        &transaction_ids,
    )
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
    pub allowed_actions: Vec<String>,
    pub denied_actions: Vec<String>,
}

/// Request body for one (user_group, contact_group) entry on PUT /permission-matrix.
///
/// `allowed_actions` and `denied_actions` are independent; both may be empty (the entry
/// clears all existing permissions for that pair). Three states per action per pair:
///     unset (no row)  ·  allowed (row, is_deny=false)  ·  denied (row, is_deny=true)
/// Resolution across all the user's groups is allow_union − deny_union (deny wins).
#[derive(Deserialize)]
pub struct PutPermissionMatrixRequest {
    pub user_group_id: String,
    pub contact_group_id: String,
    #[serde(default)]
    pub allowed_actions: Vec<String>,
    #[serde(default)]
    pub denied_actions: Vec<String>,
}

impl PutPermissionMatrixRequest {
    /// Normalize the request into (allowed, denied) action-name lists.
    /// Strips the deprecated `events:read` value (no-op on backend).
    fn allowed_denied(&self) -> (Vec<String>, Vec<String>) {
        let strip = |v: &[String]| -> Vec<String> {
            v.iter()
                .filter(|a| a.as_str() != "events:read")
                .cloned()
                .collect()
        };
        (strip(&self.allowed_actions), strip(&self.denied_actions))
    }
}

async fn require_wallet_admin(
    state: &AppState,
    wallet_id: Uuid,
    auth_user: &AuthUser,
) -> Result<(), (StatusCode, Json<serde_json::Value>)> {
    let _ = check_wallet_role(state, wallet_id, auth_user, WalletRole::Owner).await?;
    Ok(())
}

/// Returns the user's role in the wallet (type-safe enum)
async fn get_wallet_role(
    state: &AppState,
    wallet_id: Uuid,
    auth_user: &AuthUser,
) -> Result<WalletRole, (StatusCode, Json<serde_json::Value>)> {
    if auth_user.is_admin {
        return Ok(WalletRole::Owner);
    }
    let db = Database::new((*state.db_pool).clone());
    let role_str = db
        .get_wallet_user_role(wallet_id, auth_user.user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_wallet_role: {:?}", e);
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
    Ok(WalletRole::from_str(&role_str).unwrap_or(WalletRole::Member))
}

/// Returns error if the user group is system (all_users). System groups cannot be edited or have members changed.
async fn reject_system_user_group(
    state: &AppState,
    wallet_id: Uuid,
    group_id: Uuid,
) -> Result<(), (StatusCode, Json<serde_json::Value>)> {
    let db = Database::new((*state.db_pool).clone());
    let group = db.get_user_group(group_id, wallet_id).await.map_err(|e| {
        tracing::error!("reject_system_user_group: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to check group"})),
        )
    })?;

    if let Some((_id, _name, is_system)) = group {
        if is_system {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "System group all_users cannot be modified"})),
            ));
        }
    }
    Ok(())
}

/// Returns error if the contact group is system (all_contacts). System groups cannot be edited or have members changed.
async fn reject_system_contact_group(
    state: &AppState,
    wallet_id: Uuid,
    group_id: Uuid,
) -> Result<(), (StatusCode, Json<serde_json::Value>)> {
    let db = Database::new((*state.db_pool).clone());
    let group = db
        .get_contact_group(group_id, wallet_id)
        .await
        .map_err(|e| {
            tracing::error!("reject_system_contact_group: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to check group"})),
            )
        })?;

    if let Some((_id, _name, _type, is_system)) = group {
        if is_system {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "System group all_contacts cannot be modified"})),
            ));
        }
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

    let db = Database::new((*state.db_pool).clone());
    let groups = db.list_user_groups(wallet_uuid).await.map_err(|e| {
        tracing::error!("list_user_groups: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to list user groups"})),
        )
    })?;

    let list: Vec<UserGroupResponse> = groups
        .into_iter()
        .map(|(id, name, is_system)| UserGroupResponse {
            id: id.to_string(),
            wallet_id: wallet_uuid.to_string(),
            name,
            is_system,
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
    if name.eq_ignore_ascii_case("all_users") || name.eq_ignore_ascii_case("__owners__") {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Cannot create group with reserved name"})),
        ));
    }

    let id = Uuid::new_v4();
    let event_data = serde_json::json!({ "name": name });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        id,
        domain::EventType::UserGroupCreated,
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
        domain::EventType::UserGroupUpdated,
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
        domain::EventType::UserGroupDeleted,
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

    let db = Database::new((*state.db_pool).clone());
    let members = db
        .list_user_group_members(group_uuid, wallet_uuid)
        .await
        .map_err(|e| {
            tracing::error!("list_user_group_members: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to list members"})),
            )
        })?;

    let list: Vec<UserGroupMemberResponse> = members
        .into_iter()
        .map(|(user_id, username)| UserGroupMemberResponse {
            user_id: user_id.to_string(),
            username,
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

    let db = Database::new((*state.db_pool).clone());

    // Look up user by username
    let user = db
        .get_user_by_username(username)
        .await
        .map_err(|e| {
            tracing::error!("add_user_group_member lookup: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Database error"})),
            )
        })?
        .ok_or_else(|| {
            (
                StatusCode::NOT_FOUND,
                Json(serde_json::json!({"error": "User not found"})),
            )
        })?;

    let user_uuid = user.id;

    // Check group exists in wallet
    let group_exists = db
        .user_group_in_wallet(group_uuid, wallet_uuid)
        .await
        .map_err(|e| {
            tracing::error!("add_user_group_member: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to add member"})),
            )
        })?;

    if !group_exists {
        return Err((
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "User group not found"})),
        ));
    }

    // User must be a member of the wallet
    let in_wallet = db
        .wallet_user_exists(wallet_uuid, user_uuid)
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
        domain::EventType::UserGroupMemberAdded,
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
        domain::EventType::UserGroupMemberRemoved,
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
    let _ = check_wallet_role(&state, wallet_uuid, &auth_user, WalletRole::Member).await?;

    let db = Database::new((*state.db_pool).clone());
    let groups = db.list_contact_groups(wallet_uuid).await.map_err(|e| {
        tracing::error!("list_contact_groups: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to list contact groups"})),
        )
    })?;

    let list: Vec<ContactGroupResponse> = groups
        .into_iter()
        .map(|(id, name, type_, is_system)| ContactGroupResponse {
            id: id.to_string(),
            wallet_id: wallet_uuid.to_string(),
            name,
            type_,
            is_system,
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
        domain::EventType::ContactGroupCreated,
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
        domain::EventType::ContactGroupUpdated,
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
        domain::EventType::ContactGroupDeleted,
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
    let _ = check_wallet_role(&state, wallet_uuid, &auth_user, WalletRole::Member).await?;

    let db = Database::new((*state.db_pool).clone());
    let members = db
        .list_contact_group_members(group_uuid, wallet_uuid)
        .await
        .map_err(|e| {
            tracing::error!("list_contact_group_members: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to list members"})),
            )
        })?;

    let list: Vec<ContactGroupMemberResponse> = members
        .into_iter()
        .map(|contact_id| ContactGroupMemberResponse {
            contact_id: contact_id.to_string(),
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
    let contact_uuid = Uuid::parse_str(&payload.contact_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid contact_id: {}", e)})),
        )
    })?;
    let role = get_wallet_role(&state, wallet_uuid, &auth_user).await?;
    if !role.is_admin_or_higher() {
        // Check permission using event-based system
        let check_event = DomainEvent {
            id: Uuid::new_v4(),
            aggregate_id: group_uuid,
            wallet_id: wallet_uuid,
            user_id: auth_user.user_id,
            created_at: chrono::Utc::now(),
            version: 1,
            event_data: domain::EventData::ContactGroupMemberAdded {
                data: serde_json::json!({
                    "contact_id": contact_uuid.to_string(),
                    "group_id": group_uuid.to_string(),
                }),
            },
        };

        let can_edit =
            check_event_permissions(&state, wallet_uuid, &auth_user, role, &check_event).await?;

        if !can_edit {
            tracing::warn!(
                contact_id = %payload.contact_id,
                group_id = %group_id,
                user_id = %auth_user.user_id,
                "add_contact_group_member: permission denied"
            );
            return Err(insufficient_permission_response());
        }
    }
    reject_system_contact_group(&state, wallet_uuid, group_uuid).await?;

    let db = Database::new((*state.db_pool).clone());
    let group_exists = db
        .contact_group_in_wallet(group_uuid, wallet_uuid)
        .await
        .map_err(|e| {
            tracing::error!("add_contact_group_member: {:?}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to add member"})),
            )
        })?;

    if !group_exists {
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
        domain::EventType::ContactGroupMemberAdded,
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

    tracing::info!(
        contact_id = %payload.contact_id,
        group_id = %group_id,
        "contact group member added: contact added to group"
    );

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
    let contact_uuid = Uuid::parse_str(&contact_id).map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": format!("Invalid contact_id: {}", e)})),
        )
    })?;
    let role = get_wallet_role(&state, wallet_uuid, &auth_user).await?;
    if !role.is_admin_or_higher() {
        // Check permission using event-based system
        let check_event = DomainEvent {
            id: Uuid::new_v4(),
            aggregate_id: group_uuid,
            wallet_id: wallet_uuid,
            user_id: auth_user.user_id,
            created_at: chrono::Utc::now(),
            version: 1,
            event_data: domain::EventData::ContactGroupMemberRemoved {
                data: serde_json::json!({
                    "contact_id": contact_uuid.to_string(),
                    "group_id": group_uuid.to_string(),
                }),
            },
        };

        let can_edit =
            check_event_permissions(&state, wallet_uuid, &auth_user, role, &check_event).await?;

        if !can_edit {
            tracing::warn!(
                contact_id = %contact_id,
                group_id = %group_id,
                user_id = %auth_user.user_id,
                "remove_contact_group_member: permission denied"
            );
            return Err(insufficient_permission_response());
        }
    }
    reject_system_contact_group(&state, wallet_uuid, group_uuid).await?;

    let event_data = serde_json::json!({ "contact_id": contact_id });
    sync::insert_permission_event_and_apply(
        &state,
        auth_user.user_id,
        wallet_uuid,
        group_uuid,
        domain::EventType::ContactGroupMemberRemoved,
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

    tracing::info!(
        contact_id = %contact_id,
        group_id = %group_id,
        "contact group member removed: contact removed from group"
    );

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

    let db = Database::new((*state.db_pool).clone());
    let actions = db.get_all_permission_actions().await.map_err(|e| {
        tracing::error!("list_permission_actions: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to list permission actions"})),
        )
    })?;

    let list: Vec<PermissionActionResponse> = actions
        .into_iter()
        .filter(|(_id, name, _resource)| !name.starts_with("wallet:") && name != "events:read" && name != "contact:edit")
        .map(|(id, name, resource)| PermissionActionResponse { id, name, resource })
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

    let db = Database::new((*state.db_pool).clone());
    let matrix = db.get_permission_matrix(wallet_uuid).await.map_err(|e| {
        tracing::error!("get_permission_matrix: {:?}", e);
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": "Failed to get permission matrix"})),
        )
    })?;

    let list: Vec<MatrixEntry> = matrix
        .into_iter()
        .map(
            |(user_group_id, contact_group_id, mut allowed, mut denied)| {
                // Filter out the deprecated `events:read` action both ways.
                allowed.retain(|a| a != "events:read");
                denied.retain(|a| a != "events:read");
                MatrixEntry {
                    user_group_id: user_group_id.to_string(),
                    contact_group_id: contact_group_id.to_string(),
                    allowed_actions: allowed,
                    denied_actions: denied,
                }
            },
        )
        .collect();
    Ok(Json(list))
}

#[derive(Deserialize)]
pub struct PutPermissionMatrixBulkRequest {
    pub entries: Vec<PutPermissionMatrixRequest>,
}

/// PUT /api/wallets/:wallet_id/permission-matrix
/// Body: { "entries": [ { "user_group_id", "contact_group_id", "action_names": [] } ] }
/// Look up action ids for a list of action name strings.
/// Returns 400 if any name is unknown.
async fn action_ids_for(
    db: &Database,
    names: &[String],
) -> Result<Vec<i16>, (StatusCode, Json<serde_json::Value>)> {
    use crate::database::repository::DatabaseRepository;
    let mut ids = Vec::with_capacity(names.len());
    for name in names {
        match db.get_permission_action_id(name).await {
            Ok(Some(id)) => ids.push(id),
            Ok(None) => {
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(
                        serde_json::json!({"error": format!("Unknown permission action: {}", name)}),
                    ),
                ));
            }
            Err(e) => {
                tracing::error!("action_ids_for: {:?}", e);
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Failed to resolve action ids"})),
                ));
            }
        }
    }
    Ok(ids)
}

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

    let db = Database::new((*state.db_pool).clone());
    for entry in &payload.entries {
        let (allowed_names, denied_names) = entry.allowed_denied();

        // Parse incoming action-name strings into typed `Action`s to validate
        // they are valid names. Unknown names → 400 (caller error).
        let _allowed_actions: Vec<domain::Action> = allowed_names
            .iter()
            .map(|n| {
                domain::Action::from_str(n).ok_or_else(|| {
                    (
                        StatusCode::BAD_REQUEST,
                        Json(serde_json::json!({
                            "error": format!("Unknown permission action: {}", n)
                        })),
                    )
                })
            })
            .collect::<Result<_, _>>()?;

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

        let ug_ok = db
            .user_group_in_wallet(ug_id, wallet_uuid)
            .await
            .map_err(|e| {
                tracing::error!("put_permission_matrix: {:?}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Failed to update matrix"})),
                )
            })?;
        let cg_ok = db
            .contact_group_in_wallet(cg_id, wallet_uuid)
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
                Json(
                    serde_json::json!({"error": "User group or contact group not in this wallet"}),
                ),
            ));
        }

        // Validate owner permission protection: prevent modifications to owner permission vectors
        let validator = crate::permissions::OwnerPermissionValidator::new((*state.db_pool).clone());
        validator
            .validate_permission_matrix_modification(wallet_uuid, ug_id, cg_id)
            .await
            .map_err(|e| {
                tracing::warn!("Owner permission protection: {}", e);
                (
                    StatusCode::FORBIDDEN,
                    Json(serde_json::json!({
                        "code": "OWNER_PERMISSION_PROTECTED",
                        "message": e.to_string()
                    })),
                )
            })?;

        // Validate action names up front so a bad payload is rejected with
        // 400 before we write anything. The matrix mutation itself now flows
        // through `insert_permission_event_and_apply` → applier::apply →
        // ServerProjection::set_permission_matrix_entries, so the same
        // replay path that rebuilds groups also rebuilds their matrix rows.
        let _ = action_ids_for(&db, &allowed_names).await?;
        let _ = action_ids_for(&db, &denied_names).await?;

        let event_data = serde_json::json!({
            "user_group_id": entry.user_group_id,
            "contact_group_id": entry.contact_group_id,
            "allowed_actions": allowed_names,
            "denied_actions": denied_names,
        });
        sync::insert_permission_event_and_apply(
            &state,
            auth_user.user_id,
            wallet_uuid,
            ug_id,
            domain::EventType::PermissionMatrixSet,
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

    Ok(Json(
        serde_json::json!({"message": "Permission matrix updated"}),
    ))
}
