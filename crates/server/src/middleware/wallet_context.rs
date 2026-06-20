use crate::middleware::auth::AuthUser;
use crate::AppState;
use axum::extract::FromRequestParts;
use axum::{
    async_trait,
    extract::Request,
    extract::State,
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use domain::WalletRole;
use sqlx::Row;
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct WalletContext {
    pub wallet_id: Uuid,
    pub user_role: WalletRole,
}

impl WalletContext {
    #[allow(dead_code)]
    pub fn new(wallet_id: Uuid, user_role: WalletRole) -> Self {
        Self {
            wallet_id,
            user_role,
        }
    }
}

/// Middleware to extract and validate wallet context.
/// Extracts wallet_id from path parameter (/:wallet_id or /:id) — path is the
/// only source by design; do not add header/query fallbacks.
pub async fn wallet_context_middleware(
    State(state): State<AppState>,
    mut req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Get authenticated user from request extensions
    let auth_user = req
        .extensions()
        .get::<AuthUser>()
        .cloned()
        .ok_or(StatusCode::UNAUTHORIZED)?;

    // Extract wallet_id from path parameter
    let wallet_id_str = {
        let segments: Vec<&str> = req.uri().path().split('/').collect();
        segments
            .iter()
            .position(|&s| s == "wallets")
            .and_then(|pos| segments.get(pos + 1).map(|s| s.to_string()))
    };

    let wallet_id_str = wallet_id_str.ok_or_else(|| {
        tracing::warn!("No wallet_id provided in request");
        StatusCode::BAD_REQUEST
    })?;

    let wallet_id = Uuid::parse_str(&wallet_id_str).map_err(|_| {
        tracing::warn!("Invalid wallet_id format: {}", wallet_id_str);
        StatusCode::BAD_REQUEST
    })?;

    // Verify wallet exists and is active
    let wallet_exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)",
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
        "#,
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

    let user_role = match wallet_user {
        Some(role_str) => WalletRole::from_str(&role_str).unwrap_or(WalletRole::Member),
        None => {
            tracing::warn!(
                "User {} does not have access to wallet {}",
                auth_user.user_id,
                wallet_id
            );
            // Unique code so clients only drop local events when server explicitly says permission denied (not network errors).
            let body = serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "You do not have access to this wallet"
            });
            return Ok((StatusCode::FORBIDDEN, Json(body)).into_response());
        }
    };

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

    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        _state: &S,
    ) -> Result<Self, Self::Rejection> {
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
