// Integration tests for wallet management
// These tests verify:
// 1. Wallet creation
// 2. Listing wallets
// 3. Getting wallet details
// 4. Updating wallets
// 5. Deleting wallets
// 6. Adding users to wallets
// 7. Removing users from wallets
// 8. Updating user roles in wallets

use debt_tracker_api::handlers::wallets;
use debt_tracker_api::AppState;
use debt_tracker_api::config::Config;
use debt_tracker_api::middleware::auth::AuthUser;
use debt_tracker_api::websocket;
use sqlx::PgPool;
use uuid::Uuid;
use std::sync::Arc;

mod test_helpers;
use test_helpers::*;

#[tokio::test]
#[ignore] // Ignore by default - requires test database
async fn test_create_wallet() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config.clone(), broadcast_tx.clone());

    let create_request = wallets::CreateWalletRequest {
        name: "Test Wallet".to_string(),
        description: Some("Test description".to_string()),
    };

    let result = wallets::create_wallet(
        axum::extract::State(app_state),
        axum::Json(create_request),
    ).await;

    assert!(result.is_ok());
    let (status, response) = result.unwrap();
    assert_eq!(status, axum::http::StatusCode::CREATED);
    assert!(!response.id.is_empty());
    assert_eq!(response.name, "Test Wallet");

    // Verify wallet exists in database
    let wallet_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)"
    )
    .bind(Uuid::parse_str(&response.id).unwrap())
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(wallet_exists, "Wallet should exist in database");

    // Verify user was added as owner
    let user_role: String = sqlx::query_scalar(
        "SELECT role FROM wallet_users WHERE wallet_id = $1 AND user_id = $2"
    )
    .bind(Uuid::parse_str(&response.id).unwrap())
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(user_role, "owner");
}

#[tokio::test]
#[ignore]
async fn test_list_wallets() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet1_id = create_test_wallet(&pool, "Wallet 1").await;
    let wallet2_id = create_test_wallet(&pool, "Wallet 2").await;
    add_user_to_wallet(&pool, user_id, wallet1_id, "owner").await;
    add_user_to_wallet(&pool, user_id, wallet2_id, "admin").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config.clone(), broadcast_tx.clone());

    let result = wallets::list_wallets(
        axum::extract::State(app_state),
    ).await;

    assert!(result.is_ok());
    let response = result.unwrap();
    assert!(response.wallets.len() >= 2);
    
    let wallet_names: Vec<String> = response.wallets.iter().map(|w| w.name.clone()).collect();
    assert!(wallet_names.contains(&"Wallet 1".to_string()));
    assert!(wallet_names.contains(&"Wallet 2".to_string()));
}

#[tokio::test]
#[ignore]
async fn test_get_wallet() {
    let pool = setup_test_db().await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config.clone(), broadcast_tx.clone());

    let result = wallets::get_wallet(
        axum::extract::Path(wallet_id.to_string()),
        axum::extract::State(app_state),
    ).await;

    assert!(result.is_ok());
    let wallet = result.unwrap();
    assert_eq!(wallet.id, wallet_id.to_string());
    assert_eq!(wallet.name, "Test Wallet");
    assert!(wallet.is_active);
}

#[tokio::test]
#[ignore]
async fn test_update_wallet() {
    let pool = setup_test_db().await;
    let acting_user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Original Name").await;
    add_user_to_wallet(&pool, acting_user_id, wallet_id, "admin").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config.clone(), broadcast_tx.clone());

    let update_request = wallets::UpdateWalletRequest {
        name: Some("Updated Name".to_string()),
        description: Some("Updated description".to_string()),
        is_active: None,
    };

    let result = wallets::update_wallet(
        axum::extract::Path(wallet_id.to_string()),
        axum::extract::State(app_state),
        axum::extract::Extension(AuthUser { user_id: acting_user_id, email: "test@example.com".to_string(), is_admin: false }),
        axum::Json(update_request),
    ).await;

    assert!(result.is_ok());
    let (status, _) = result.unwrap();
    assert_eq!(status, axum::http::StatusCode::OK);

    // Verify wallet was updated
    let wallet_name: String = sqlx::query_scalar(
        "SELECT name FROM wallets WHERE id = $1"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(wallet_name, "Updated Name");
}

#[tokio::test]
#[ignore]
async fn test_delete_wallet() {
    let pool = setup_test_db().await;
    let acting_user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, acting_user_id, wallet_id, "owner").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config.clone(), broadcast_tx.clone());

    let result = wallets::delete_wallet(
        axum::extract::Path(wallet_id.to_string()),
        axum::extract::State(app_state),
        axum::extract::Extension(AuthUser { user_id: acting_user_id, email: "test@example.com".to_string(), is_admin: false }),
    ).await;

    assert!(result.is_ok());
    let (status, _) = result.unwrap();
    assert_eq!(status, axum::http::StatusCode::OK);

    // Verify wallet is soft deleted
    let is_active: bool = sqlx::query_scalar(
        "SELECT is_active FROM wallets WHERE id = $1"
    )
    .bind(wallet_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!is_active, "Wallet should be soft deleted");
}

#[tokio::test]
#[ignore]
async fn test_add_user_to_wallet() {
    let pool = setup_test_db().await;
    let acting_user_id = create_test_user(&pool).await;
    let target_user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, acting_user_id, wallet_id, "owner").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config.clone(), broadcast_tx.clone());

    let add_request = wallets::AddUserToWalletRequest {
        user_id: target_user_id.to_string(),
        role: "member".to_string(),
    };

    let result = wallets::add_user_to_wallet(
        axum::extract::Path(wallet_id.to_string()),
        axum::extract::State(app_state),
        axum::extract::Extension(AuthUser { user_id: acting_user_id, email: "test@example.com".to_string(), is_admin: false }),
        axum::Json(add_request),
    ).await;

    assert!(result.is_ok());
    let (status, _) = result.unwrap();
    assert_eq!(status, axum::http::StatusCode::CREATED);

    // Verify user was added to wallet
    let user_role: String = sqlx::query_scalar(
        "SELECT role FROM wallet_users WHERE wallet_id = $1 AND user_id = $2"
    )
    .bind(wallet_id)
    .bind(target_user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(user_role, "member");
}

#[tokio::test]
#[ignore]
async fn test_update_wallet_user_role() {
    let pool = setup_test_db().await;
    let acting_user_id = create_test_user(&pool).await;
    let target_user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, acting_user_id, wallet_id, "admin").await;
    add_user_to_wallet(&pool, target_user_id, wallet_id, "member").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config.clone(), broadcast_tx.clone());

    let update_request = wallets::UpdateWalletUserRequest {
        role: "admin".to_string(),
    };

    let result = wallets::update_wallet_user(
        axum::extract::Path((wallet_id.to_string(), target_user_id.to_string())),
        axum::extract::State(app_state),
        axum::extract::Extension(AuthUser { user_id: acting_user_id, email: "test@example.com".to_string(), is_admin: false }),
        axum::Json(update_request),
    ).await;

    assert!(result.is_ok());
    let (status, _) = result.unwrap();
    assert_eq!(status, axum::http::StatusCode::OK);

    // Verify role was updated
    let user_role: String = sqlx::query_scalar(
        "SELECT role FROM wallet_users WHERE wallet_id = $1 AND user_id = $2"
    )
    .bind(wallet_id)
    .bind(target_user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(user_role, "admin");
}

#[tokio::test]
#[ignore]
async fn test_remove_user_from_wallet() {
    let pool = setup_test_db().await;
    let acting_user_id = create_test_user(&pool).await;
    let target_user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Test Wallet").await;
    add_user_to_wallet(&pool, acting_user_id, wallet_id, "admin").await;
    add_user_to_wallet(&pool, target_user_id, wallet_id, "member").await;
    
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    let app_state = test_helpers::create_test_app_state(pool.clone(), config.clone(), broadcast_tx.clone());

    let result = wallets::remove_user_from_wallet(
        axum::extract::Path((wallet_id.to_string(), target_user_id.to_string())),
        axum::extract::State(app_state),
        axum::extract::Extension(AuthUser { user_id: acting_user_id, email: "test@example.com".to_string(), is_admin: false }),
    ).await;

    assert!(result.is_ok());
    let (status, _) = result.unwrap();
    assert_eq!(status, axum::http::StatusCode::OK);

    // Verify user was removed from wallet
    let user_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)"
    )
    .bind(wallet_id)
    .bind(target_user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(!user_exists, "User should be removed from wallet");
}
