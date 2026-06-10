/// Common HTTP response builders for handlers
use axum::http::StatusCode;
use axum::Json;

/// Return 403 body with DEBITUM_INSUFFICIENT_WALLET_PERMISSION error
pub fn insufficient_permission_response() -> (StatusCode, Json<serde_json::Value>) {
    (
        StatusCode::FORBIDDEN,
        Json(serde_json::json!({
            "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
            "message": "Insufficient permissions for this action"
        })),
    )
}
