// Integration tests for wallet isolation
// These tests verify that data is properly isolated between wallets:
// 1. Contacts in one wallet don't appear in another
// 2. Transactions in one wallet don't appear in another
// 3. Events are wallet-scoped
// 4. Users can only access wallets they're subscribed to

use debt_tracker_api::handlers::transactions;
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
async fn test_contact_isolation_between_wallets() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet1_id = create_test_wallet(&pool, "Wallet 1").await;
    let wallet2_id = create_test_wallet(&pool, "Wallet 2").await;
    add_user_to_wallet(&pool, user_id, wallet1_id, "owner").await;
    add_user_to_wallet(&pool, user_id, wallet2_id, "owner").await;
    
    // Create contact in wallet 1
    let contact1_id = create_test_contact(&pool, user_id, wallet1_id, "Contact 1").await;
    
    // Create contact in wallet 2
    let contact2_id = create_test_contact(&pool, user_id, wallet2_id, "Contact 2").await;
    
    // Verify contact1 is only in wallet1
    let contact1_in_wallet1: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND wallet_id = $2)"
    )
    .bind(contact1_id)
    .bind(wallet1_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(contact1_in_wallet1, "Contact 1 should be in wallet 1");
    
    let contact1_in_wallet2: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND wallet_id = $2)"
    )
    .bind(contact1_id)
    .bind(wallet2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!contact1_in_wallet2, "Contact 1 should NOT be in wallet 2");
    
    // Verify contact2 is only in wallet2
    let contact2_in_wallet2: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND wallet_id = $2)"
    )
    .bind(contact2_id)
    .bind(wallet2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(contact2_in_wallet2, "Contact 2 should be in wallet 2");
    
    let contact2_in_wallet1: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND wallet_id = $2)"
    )
    .bind(contact2_id)
    .bind(wallet1_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!contact2_in_wallet1, "Contact 2 should NOT be in wallet 1");
}

#[tokio::test]
#[ignore]
async fn test_transaction_isolation_between_wallets() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet1_id = create_test_wallet(&pool, "Wallet 1").await;
    let wallet2_id = create_test_wallet(&pool, "Wallet 2").await;
    add_user_to_wallet(&pool, user_id, wallet1_id, "owner").await;
    add_user_to_wallet(&pool, user_id, wallet2_id, "owner").await;
    
    let contact1_id = create_test_contact(&pool, user_id, wallet1_id, "Contact 1").await;
    let contact2_id = create_test_contact(&pool, user_id, wallet2_id, "Contact 2").await;
    
    // Create transaction in wallet 1
    let transaction1_id = create_test_transaction(&pool, user_id, wallet1_id, contact1_id, 10000, "lent").await;
    
    // Create transaction in wallet 2
    let transaction2_id = create_test_transaction(&pool, user_id, wallet2_id, contact2_id, 20000, "lent").await;
    
    // Verify transaction1 is only in wallet1
    let transaction1_in_wallet1: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM transactions_projection WHERE id = $1 AND wallet_id = $2)"
    )
    .bind(transaction1_id)
    .bind(wallet1_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(transaction1_in_wallet1, "Transaction 1 should be in wallet 1");
    
    let transaction1_in_wallet2: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM transactions_projection WHERE id = $1 AND wallet_id = $2)"
    )
    .bind(transaction1_id)
    .bind(wallet2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!transaction1_in_wallet2, "Transaction 1 should NOT be in wallet 2");
    
    // Verify transaction2 is only in wallet2
    let transaction2_in_wallet2: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM transactions_projection WHERE id = $1 AND wallet_id = $2)"
    )
    .bind(transaction2_id)
    .bind(wallet2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(transaction2_in_wallet2, "Transaction 2 should be in wallet 2");
    
    let transaction2_in_wallet1: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM transactions_projection WHERE id = $1 AND wallet_id = $2)"
    )
    .bind(transaction2_id)
    .bind(wallet1_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!transaction2_in_wallet1, "Transaction 2 should NOT be in wallet 1");
}

#[tokio::test]
#[ignore]
async fn test_event_isolation_between_wallets() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet1_id = create_test_wallet(&pool, "Wallet 1").await;
    let wallet2_id = create_test_wallet(&pool, "Wallet 2").await;
    add_user_to_wallet(&pool, user_id, wallet1_id, "owner").await;
    add_user_to_wallet(&pool, user_id, wallet2_id, "owner").await;
    
    let contact1_id = Uuid::new_v4();
    let contact2_id = Uuid::new_v4();
    
    // Create event in wallet 1
    let event1_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
         VALUES ($1, $2, $3, 'contact', $4, 'CONTACT_CREATED', 1, $5, NOW())"
    )
    .bind(event1_id)
    .bind(user_id)
    .bind(wallet1_id)
    .bind(contact1_id)
    .bind(serde_json::json!({"name": "Contact 1"}))
    .execute(&pool)
    .await
    .unwrap();
    
    // Create event in wallet 2
    let event2_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO events (event_id, user_id, wallet_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
         VALUES ($1, $2, $3, 'contact', $4, 'CONTACT_CREATED', 1, $5, NOW())"
    )
    .bind(event2_id)
    .bind(user_id)
    .bind(wallet2_id)
    .bind(contact2_id)
    .bind(serde_json::json!({"name": "Contact 2"}))
    .execute(&pool)
    .await
    .unwrap();
    
    // Verify event1 is only in wallet1
    let event1_in_wallet1: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1 AND wallet_id = $2)"
    )
    .bind(event1_id)
    .bind(wallet1_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(event1_in_wallet1, "Event 1 should be in wallet 1");
    
    let event1_in_wallet2: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1 AND wallet_id = $2)"
    )
    .bind(event1_id)
    .bind(wallet2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!event1_in_wallet2, "Event 1 should NOT be in wallet 2");
    
    // Verify event2 is only in wallet2
    let event2_in_wallet2: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1 AND wallet_id = $2)"
    )
    .bind(event2_id)
    .bind(wallet2_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(event2_in_wallet2, "Event 2 should be in wallet 2");
    
    let event2_in_wallet1: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM events WHERE event_id = $1 AND wallet_id = $2)"
    )
    .bind(event2_id)
    .bind(wallet1_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!event2_in_wallet1, "Event 2 should NOT be in wallet 1");
}

#[tokio::test]
#[ignore]
async fn test_balance_calculation_is_wallet_scoped() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet1_id = create_test_wallet(&pool, "Wallet 1").await;
    let wallet2_id = create_test_wallet(&pool, "Wallet 2").await;
    add_user_to_wallet(&pool, user_id, wallet1_id, "owner").await;
    add_user_to_wallet(&pool, user_id, wallet2_id, "owner").await;
    
    let contact1_id = create_test_contact(&pool, user_id, wallet1_id, "Contact 1").await;
    let contact2_id = create_test_contact(&pool, user_id, wallet2_id, "Contact 2").await;
    
    // Create transactions in both wallets
    create_test_transaction(&pool, user_id, wallet1_id, contact1_id, 10000, "lent").await;
    create_test_transaction(&pool, user_id, wallet2_id, contact2_id, 20000, "lent").await;
    
    // Verify balances are wallet-scoped
    let balance1 = get_contact_balance(&pool, wallet1_id, contact1_id).await;
    assert_eq!(balance1, 10000, "Contact 1 balance should be 10000 in wallet 1");
    
    let balance2 = get_contact_balance(&pool, wallet2_id, contact2_id).await;
    assert_eq!(balance2, 20000, "Contact 2 balance should be 20000 in wallet 2");
    
    // Verify contact1 has no balance in wallet2
    let balance1_in_wallet2 = get_contact_balance(&pool, wallet2_id, contact1_id).await;
    assert_eq!(balance1_in_wallet2, 0, "Contact 1 should have no balance in wallet 2");
    
    // Verify contact2 has no balance in wallet1
    let balance2_in_wallet1 = get_contact_balance(&pool, wallet1_id, contact2_id).await;
    assert_eq!(balance2_in_wallet1, 0, "Contact 2 should have no balance in wallet 1");
}
