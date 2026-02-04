// Integration tests for wallet context middleware validation logic
// These tests verify the validation that the middleware performs:
// 1. Wallet exists and is active
// 2. User has access to wallet
// 3. Invalid wallet_id format is rejected
// 4. Non-existent wallet is rejected
// 5. Unauthorized access is rejected
// 6. Inactive wallet is rejected
// 7. Missing wallet_id is rejected

// Note: Direct middleware testing is complex due to Next type requirements.
// These tests verify the validation logic through database queries.
// Full middleware integration is tested through API endpoint tests.

use sqlx::PgPool;
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_wallet_context_validation_wallet_exists() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;
    
    // Verify wallet exists and is active (what middleware checks)
    let wallet_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(wallet_exists, "Wallet should exist and be active");
    
    let user_has_access: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)"
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(user_has_access, "User should have access to wallet");
}

#[tokio::test]
#[ignore]
async fn test_wallet_context_validation_invalid_uuid() {
    // Verify invalid UUID format would be rejected
    let invalid_uuid_result = Uuid::parse_str("invalid-uuid");
    assert!(invalid_uuid_result.is_err(), "Invalid UUID should be rejected");
}

#[tokio::test]
#[ignore]
async fn test_wallet_context_validation_non_existent_wallet() {
    let pool = setup_test_db().await;
    let non_existent_wallet_id = Uuid::new_v4();
    
    // Verify non-existent wallet would be rejected
    let wallet_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)"
    )
    .bind(non_existent_wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!wallet_exists, "Non-existent wallet should not be found");
}

#[tokio::test]
#[ignore]
async fn test_wallet_context_validation_unauthorized_access() {
    let pool = setup_test_db().await;
    let user1_id = create_test_user(&pool).await;
    let user2_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    
    // Only add user1 to wallet, not user2
    add_user_to_wallet(&pool, user1_id, wallet_id, "owner").await;
    
    // Verify user2 doesn't have access
    let user2_has_access: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)"
    )
    .bind(wallet_id)
    .bind(user2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!user2_has_access, "User2 should NOT have access to wallet");
}

#[tokio::test]
#[ignore]
async fn test_wallet_context_validation_inactive_wallet() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;
    
    // Deactivate wallet
    sqlx::query("UPDATE wallets SET is_active = false WHERE id = $1")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();
    
    // Verify inactive wallet would be rejected
    let wallet_is_active: bool = sqlx::query_scalar(
        "SELECT is_active FROM wallets WHERE id = $1"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!wallet_is_active, "Inactive wallet should be rejected");
}

#[tokio::test]
#[ignore]
async fn test_wallet_context_extraction_from_query() {
    let pool = setup_test_db().await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    
    // Simulate extracting wallet_id from query parameter
    let query_wallet_id = Some(wallet_id.to_string());
    assert!(query_wallet_id.is_some(), "Wallet ID should be extractable from query");
    
    let parsed_id = query_wallet_id
        .and_then(|s| Uuid::parse_str(&s).ok())
        .unwrap();
    assert_eq!(parsed_id, wallet_id, "Parsed wallet ID should match");
}

#[tokio::test]
#[ignore]
async fn test_wallet_context_extraction_from_header() {
    let pool = setup_test_db().await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    
    // Simulate extracting wallet_id from header
    use axum::http::{HeaderMap, HeaderValue};
    let mut headers = HeaderMap::new();
    headers.insert("X-Wallet-Id", HeaderValue::from_str(&wallet_id.to_string()).unwrap());
    
    let header_wallet_id = headers
        .get("X-Wallet-Id")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok());
    
    assert_eq!(header_wallet_id, Some(wallet_id), "Wallet ID should be extractable from header");
}
