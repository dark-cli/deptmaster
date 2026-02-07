use axum::{
    extract::{Request, State},
    http::{header::AUTHORIZATION, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    Json,
};
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::AppState;

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub user_id: String,
    pub email: String,
    pub exp: usize,
}

#[derive(Clone)]
pub struct AuthUser {
    pub user_id: Uuid,
    #[allow(dead_code)] // Reserved for future use (e.g., logging, user info display)
    pub email: String,
    /// True if this token belongs to an active admin user.
    pub is_admin: bool,
}

pub async fn auth_middleware(
    State(state): State<AppState>,
    mut req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Allow health check and login endpoints without auth
    let path = req.uri().path();
    if path == "/health" || path == "/api/auth/login" || path == "/api/auth/admin/login" {
        return Ok(next.run(req).await);
    }

    /// 401 with clear code so client only logs out when server explicitly says auth declined (not on network errors).
    fn auth_declined_response() -> Response {
        let body = serde_json::json!({
            "code": "DEBITUM_AUTH_DECLINED",
            "message": "Authentication required or session invalid"
        });
        (StatusCode::UNAUTHORIZED, Json(body)).into_response()
    }

    // Extract token from Authorization header
    let auth_header = match req.headers().get(AUTHORIZATION).and_then(|h| h.to_str().ok()) {
        Some(h) => h,
        None => return Ok(auth_declined_response()),
    };

    if !auth_header.starts_with("Bearer ") {
        return Ok(auth_declined_response());
    }

    let token = &auth_header[7..]; // Skip "Bearer "

    // Decode and validate JWT
    let decoding_key = DecodingKey::from_secret(state.config.jwt_secret.as_ref());
    let validation = Validation::new(Algorithm::HS256);

    let token_data = match decode::<Claims>(token, &decoding_key, &validation) {
        Ok(d) => d,
        Err(_) => return Ok(auth_declined_response()),
    };

    let claims = token_data.claims;

    // Parse user_id
    let user_id = match Uuid::parse_str(&claims.user_id) {
        Ok(u) => u,
        Err(_) => return Ok(auth_declined_response()),
    };

    // Determine if this token belongs to an active admin.
    let is_admin = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM admin_users WHERE id = $1 AND is_active = true)"
    )
    .bind(user_id)
    .fetch_one(&*state.db_pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Verify user exists (regular user or active admin).
    if !is_admin {
        let user_exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM users_projection WHERE id = $1)"
        )
        .bind(user_id)
        .fetch_one(&*state.db_pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        if !user_exists {
            return Ok(auth_declined_response());
        }
    }

    // Admin access rules:
    // - /api/admin/** requires an admin token
    // - admin tokens must NOT be used to create events / sync / realtime
    if path.starts_with("/api/admin/") {
        if !is_admin {
            let body = serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "Insufficient permissions"
            });
            return Ok((StatusCode::FORBIDDEN, Json(body)).into_response());
        }
    } else if is_admin {
        // Disallow admin tokens from using user-facing event/sync/realtime endpoints.
        if path == "/ws"
            || path.starts_with("/api/contacts")
            || path.starts_with("/api/transactions")
            || path.starts_with("/api/sync/")
        {
            let body = serde_json::json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "Insufficient permissions"
            });
            return Ok((StatusCode::FORBIDDEN, Json(body)).into_response());
        }
    }

    // Attach user info to request
    let auth_user = AuthUser {
        user_id,
        email: claims.email,
        is_admin,
    };
    req.extensions_mut().insert(auth_user);

    Ok(next.run(req).await)
}

// Extractor to get authenticated user from request
// Reserved for future use when additional auth checks are needed
#[allow(dead_code)]
pub async fn require_auth(
    req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let _auth_user = req
        .extensions()
        .get::<AuthUser>()
        .cloned()
        .ok_or(StatusCode::UNAUTHORIZED)?;

    Ok(next.run(req).await)
}
