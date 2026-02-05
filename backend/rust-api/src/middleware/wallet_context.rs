use axum::{
    extract::{Query, Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
    async_trait,
};
use axum::extract::FromRequestParts;
use serde::Deserialize;
use sqlx::Row;
use uuid::Uuid;
use crate::AppState;
use crate::middleware::auth::AuthUser;

#[derive(Clone, Debug)]
pub struct WalletContext {
    pub wallet_id: Uuid,
    #[allow(dead_code)]
    pub user_role: String, // 'owner', 'admin', 'member' (for future require_wallet_role)
}

impl WalletContext {
    #[allow(dead_code)]
    pub fn new(wallet_id: Uuid, user_role: String) -> Self {
        Self { wallet_id, user_role }
    }
}

#[derive(Deserialize)]
pub struct WalletQuery {
    pub wallet_id: Option<String>,
}

/// Middleware to extract and validate wallet context
/// Extracts wallet_id from:
/// 1. Query parameter: ?wallet_id=...
/// 2. Header: X-Wallet-Id
/// 3. Request extensions (if set by previous middleware)
pub async fn wallet_context_middleware(
    State(state): State<AppState>,
    Query(query): Query<WalletQuery>,
    mut req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Get authenticated user from request extensions
    let auth_user = req
        .extensions()
        .get::<AuthUser>()
        .cloned()
        .ok_or(StatusCode::UNAUTHORIZED)?;

    // Extract wallet_id from various sources
    let wallet_id_str = query.wallet_id
        .or_else(|| {
            // Try to get from header
            req.headers()
                .get("X-Wallet-Id")
                .and_then(|h| h.to_str().ok())
                .map(|s| s.to_string())
        })
        .or_else(|| {
            // Try to get from path (if route has :wallet_id)
            req.uri().path()
                .split('/')
                .find(|s| s.starts_with("wallets"))
                .and_then(|_| {
                    // Extract wallet_id from path segments
                    let segments: Vec<&str> = req.uri().path().split('/').collect();
                    segments.iter()
                        .position(|&s| s == "wallets")
                        .and_then(|pos| segments.get(pos + 1))
                        .map(|s| s.to_string())
                })
        });

    let wallet_id_str = wallet_id_str.ok_or_else(|| {
        tracing::warn!("No wallet_id provided in request");
        StatusCode::BAD_REQUEST
    })?;

    let wallet_id = Uuid::parse_str(&wallet_id_str)
        .map_err(|_| {
            tracing::warn!("Invalid wallet_id format: {}", wallet_id_str);
            StatusCode::BAD_REQUEST
        })?;

    // Verify wallet exists and is active
    let wallet_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)"
    )
    .bind(wallet_id)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    if !wallet_exists {
        tracing::warn!("Wallet not found or inactive: {}", wallet_id);
        return Err(StatusCode::NOT_FOUND);
    }

    // Verify user has access to this wallet
    let wallet_user = sqlx::query(
        r#"
        SELECT role
        FROM wallet_users
        WHERE wallet_id = $1 AND user_id = $2
        "#
    )
    .bind(wallet_id)
    .bind(auth_user.user_id)
    .map(|row: sqlx::postgres::PgRow| row.get::<String, _>("role"))
    .fetch_optional(&*state.db_pool)
    .await
    .map_err(|e| {
        tracing::error!("Error checking wallet access: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let user_role = wallet_user.ok_or_else(|| {
        tracing::warn!("User {} does not have access to wallet {}", auth_user.user_id, wallet_id);
        StatusCode::FORBIDDEN
    })?;

    // Attach wallet context to request
    let wallet_context = WalletContext {
        wallet_id,
        user_role,
    };
    req.extensions_mut().insert(wallet_context);

    Ok(next.run(req).await)
}

/// Axum extractor for WalletContext
#[async_trait]
impl<S> FromRequestParts<S> for WalletContext
where
    S: Send + Sync,
{
    type Rejection = StatusCode;

    async fn from_request_parts(parts: &mut axum::http::request::Parts, _state: &S) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<WalletContext>()
            .cloned()
            .ok_or(StatusCode::BAD_REQUEST)
    }
}

/// Extractor to get wallet context from request (legacy helper)
#[allow(dead_code)]
pub fn get_wallet_context(req: &Request) -> Option<WalletContext> {
    req.extensions().get::<WalletContext>().cloned()
}

/// Helper to require specific role
#[allow(dead_code)]
pub fn require_wallet_role(context: &WalletContext, required_role: &str) -> Result<(), StatusCode> {
    let role_hierarchy = ["member", "admin", "owner"];
    let user_role_level = role_hierarchy.iter()
        .position(|&r| r == context.user_role.as_str())
        .unwrap_or(0);
    let required_role_level = role_hierarchy.iter()
        .position(|&r| r == required_role)
        .unwrap_or(0);

    if user_role_level >= required_role_level {
        Ok(())
    } else {
        Err(StatusCode::FORBIDDEN)
    }
}
