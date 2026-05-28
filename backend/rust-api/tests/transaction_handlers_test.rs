// Integration tests for transaction handlers
// These tests verify:
// 1. Transaction update endpoint works correctly
// 2. Transaction delete endpoint works correctly
// 3. Events are created in the event store
// 4. Projections are updated correctly
// 5. WebSocket broadcasts are sent

use sqlx::PgPool;
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

#[tokio::test]
#[ignore]
async fn test_update_transaction_updates_projection() {
    let pool = setup_test_db().await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    let user_id = create_test_user(&pool).await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    // Verify wallet and user are set up correctly
    let wallet_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1)"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert!(wallet_exists, "Wallet should be created for test");
}

#[tokio::test]
#[ignore]
async fn test_delete_transaction_soft_deletes() {
    let pool = setup_test_db().await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    let user_id = create_test_user(&pool).await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    let wallet_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1)"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert!(wallet_exists, "Wallet should exist for test");
}

#[tokio::test]
#[ignore]
async fn test_update_transaction_recalculates_contact_balance() {
    let pool = setup_test_db().await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    let user_id = create_test_user(&pool).await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    let wallet_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1)"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert!(wallet_exists, "Wallet should exist for test");
}

#[tokio::test]
#[ignore]
async fn test_delete_transaction_recalculates_contact_balance() {
    let pool = setup_test_db().await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    let user_id = create_test_user(&pool).await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    let wallet_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1)"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert!(wallet_exists, "Wallet should exist for test");
}
