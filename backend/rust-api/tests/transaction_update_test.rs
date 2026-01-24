// Integration test for transaction update functionality
// Note: These tests require a test database to be set up
// Run with: TEST_DATABASE_URL=postgresql://... cargo test -- --ignored

use debt_tracker_api::handlers::transactions::UpdateTransactionRequest;
use debt_tracker_api::AppState;
use debt_tracker_api::config::Config;
use debt_tracker_api::websocket;
use sqlx::PgPool;
use uuid::Uuid;
use std::sync::Arc;

mod test_helpers;
use test_helpers::*;

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_update_transaction_updates_projection() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let contact_id = create_test_contact(&pool, user_id, "Test Contact").await;
    let transaction_id = create_test_transaction(&pool, user_id, contact_id, 10000, "lent").await;

    // Create app state
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    // Update transaction
    let update_request = UpdateTransactionRequest {
        amount: Some(20000),
        direction: None,
        description: None,
        transaction_date: None,
        contact_id: None,
        r#type: None,
        currency: None,
        comment: "Test update".to_string(),
        due_date: None,
    };

    let result = debt_tracker_api::handlers::transactions::update_transaction(
        axum::extract::Path(transaction_id.to_string()),
        axum::extract::State(app_state),
        axum::Json(update_request),
    )
    .await;

    // Verify update succeeded
    assert!(result.is_ok());
    let (status, _) = result.unwrap();
    assert_eq!(status, axum::http::StatusCode::OK);

    // Verify transaction was updated in database
    let updated_amount: i64 = sqlx::query_scalar(
        "SELECT amount FROM transactions_projection WHERE id = $1"
    )
    .bind(transaction_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert_eq!(updated_amount, 20000);
}

#[tokio::test]
#[ignore]
async fn test_update_transaction_recalculates_contact_balance() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let contact_id = create_test_contact(&pool, user_id, "Test Contact").await;
    
    // Create initial transaction: lent 10000
    let transaction_id = create_test_transaction(&pool, user_id, contact_id, 10000, "lent").await;
    
    // Verify initial balance
    let initial_balance = get_contact_balance(&pool, contact_id).await;
    assert_eq!(initial_balance, 10000);

    // Create app state
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    // Update transaction amount to 20000
    let update_request = UpdateTransactionRequest {
        amount: Some(20000),
        direction: None,
        description: None,
        transaction_date: None,
        contact_id: None,
        r#type: None,
        currency: None,
        comment: "Test update".to_string(),
        due_date: None,
    };

    let result = debt_tracker_api::handlers::transactions::update_transaction(
        axum::extract::Path(transaction_id.to_string()),
        axum::extract::State(app_state),
        axum::Json(update_request),
    )
    .await;

    assert!(result.is_ok());

    // Verify balance was recalculated
    let new_balance = get_contact_balance(&pool, contact_id).await;
    assert_eq!(new_balance, 20000);
}

#[tokio::test]
#[ignore]
async fn test_delete_transaction_soft_deletes() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let contact_id = create_test_contact(&pool, user_id, "Test Contact").await;
    let transaction_id = create_test_transaction(&pool, user_id, contact_id, 10000, "lent").await;

    // Create app state
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    // Delete transaction
    let delete_request = debt_tracker_api::handlers::transactions::DeleteTransactionRequest {
        comment: "Test deletion".to_string(),
    };
    let result = debt_tracker_api::handlers::transactions::delete_transaction(
        axum::extract::Path(transaction_id.to_string()),
        axum::extract::State(app_state),
        axum::Json(delete_request),
    )
    .await;

    // Verify delete succeeded
    assert!(result.is_ok());
    let (status, _) = result.unwrap();
    assert_eq!(status, axum::http::StatusCode::OK);

    // Verify transaction is soft deleted
    let is_deleted: bool = sqlx::query_scalar(
        "SELECT is_deleted FROM transactions_projection WHERE id = $1"
    )
    .bind(transaction_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert!(is_deleted);
}

#[tokio::test]
#[ignore]
async fn test_delete_transaction_recalculates_contact_balance() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let contact_id = create_test_contact(&pool, user_id, "Test Contact").await;
    
    // Create transaction: lent 10000
    let transaction_id = create_test_transaction(&pool, user_id, contact_id, 10000, "lent").await;
    
    // Verify initial balance
    let initial_balance = get_contact_balance(&pool, contact_id).await;
    assert_eq!(initial_balance, 10000);

    // Create app state
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    // Delete transaction
    let delete_request = debt_tracker_api::handlers::transactions::DeleteTransactionRequest {
        comment: "Test deletion".to_string(),
    };
    let result = debt_tracker_api::handlers::transactions::delete_transaction(
        axum::extract::Path(transaction_id.to_string()),
        axum::extract::State(app_state),
        axum::Json(delete_request),
    )
    .await;

    assert!(result.is_ok());

    // Verify balance was recalculated (should be 0 after deletion)
    let new_balance = get_contact_balance(&pool, contact_id).await;
    assert_eq!(new_balance, 0);
}
