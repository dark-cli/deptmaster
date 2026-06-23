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

/// Return 403 body with missing permissions details
///
/// Tells the client exactly which permissions are missing
///
/// # Arguments
/// * `missing_permissions` - List of permission action names that are missing (e.g., ["wallet:member_add", "wallet:info_read"])
///
/// # Example usage in a handler:
/// ```ignore
/// let perm_model = PermissionModel::new((*state.db_pool).clone());
/// let missing = perm_model.get_missing_permissions(
///     &ctx,
///     vec![Action::WalletMemberAdd],
///     &Resource::Wallet(wallet_id)
/// ).await?;
///
/// if !missing.is_empty() {
///     return Err(responses::insufficient_permission_with_details(missing));
/// }
/// ```
pub fn insufficient_permission_with_details(
    missing_permissions: Vec<String>,
) -> (StatusCode, Json<serde_json::Value>) {
    (
        StatusCode::FORBIDDEN,
        Json(serde_json::json!({
            "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
            "message": "Insufficient permissions for this action",
            "missing_permissions": missing_permissions,
        })),
    )
}
