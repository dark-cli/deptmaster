//! Tests for the advanced permission system (group-group model).
//! Run with: TEST_DATABASE_URL=postgresql://... cargo test --test permission_test -- --include-ignored

use axum::http::StatusCode;
use debt_tracker_api::handlers::contacts::get_contacts;
use debt_tracker_api::handlers::wallets::get_my_permissions;
use debt_tracker_api::AppState;
use debt_tracker_api::config::Config;
use debt_tracker_api::websocket;
use std::collections::HashMap;
use std::sync::Arc;

mod test_helpers;
use test_helpers::*;

#[tokio::test]
#[ignore]
async fn test_owner_can_get_contacts() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: Arc::new(Config::from_env().unwrap()),
        broadcast_tx: websocket::create_broadcast_channel(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let result = get_contacts(
        axum::extract::State(app_state),
        wallet_context_extension(wallet_id, "owner"),
        auth_user_extension(user_id, None),
    )
    .await;

    assert!(result.is_ok(), "owner should be able to get contacts");
}

#[tokio::test]
#[ignore]
async fn test_member_without_groups_gets_403_on_get_contacts() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    // Do NOT create system groups: wallet has no user_groups, so resolve_user_groups returns [].

    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: Arc::new(Config::from_env().unwrap()),
        broadcast_tx: websocket::create_broadcast_channel(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let result = get_contacts(
        axum::extract::State(app_state),
        wallet_context_extension(wallet_id, "member"),
        auth_user_extension(user_id, None),
    )
    .await;

    let err = match result {
        Ok(_) => panic!("expected 403 for member without groups"),
        Err(e) => e,
    };
    let (status, body) = err;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let code = body.get("code").and_then(|v| v.as_str()).unwrap_or("");
    assert!(code.contains("DEBITUM_INSUFFICIENT_WALLET_PERMISSION"), "expected permission code, got {:?}", body);
}

#[tokio::test]
#[ignore]
async fn test_member_with_system_groups_can_get_contacts() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "member").await;
    ensure_wallet_has_system_groups(&pool, wallet_id).await;

    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: Arc::new(Config::from_env().unwrap()),
        broadcast_tx: websocket::create_broadcast_channel(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let result = get_contacts(
        axum::extract::State(app_state),
        wallet_context_extension(wallet_id, "member"),
        auth_user_extension(user_id, None),
    )
    .await;

    assert!(result.is_ok(), "member with system groups (all_users x all_contacts) should get contacts");
}

#[tokio::test]
#[ignore]
async fn test_get_my_permissions_owner_gets_all_actions() {
    let pool = setup_test_db().await;
    let user_id = create_test_user(&pool).await;
    let wallet_id = create_test_wallet(&pool, "Wallet").await;
    add_user_to_wallet(&pool, user_id, wallet_id, "owner").await;

    let app_state = AppState {
        db_pool: Arc::new(pool.clone()),
        config: Arc::new(Config::from_env().unwrap()),
        broadcast_tx: websocket::create_broadcast_channel(),
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    let result = get_my_permissions(
        axum::extract::State(app_state),
        wallet_context_extension(wallet_id, "owner"),
        auth_user_extension(user_id, None),
        axum::extract::Query(HashMap::new()),
    )
    .await;

    assert!(result.is_ok());
    let res = result.unwrap();
    assert!(res.0.actions.contains(&"contact:create".to_string()));
    assert!(res.0.actions.contains(&"contact:read".to_string()));
    assert!(res.0.actions.contains(&"transaction:create".to_string()));
}
