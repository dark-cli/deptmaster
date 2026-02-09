use axum::http::StatusCode;
use debt_tracker_api::handlers::contacts::create_contact;
use debt_tracker_api::handlers::contacts::CreateContactRequest;
use debt_tracker_api::handlers::wallets::{create_user_group, CreateUserGroupRequest};
use debt_tracker_api::middleware::wallet_context::WalletContext;
use debt_tracker_api::middleware::auth::AuthUser;
use debt_tracker_api::AppState;
use axum::extract::{State, Extension, Path};
use axum::Json;
use uuid::Uuid;
use std::sync::Arc;
use tokio::sync::broadcast;

mod test_helpers;

#[tokio::test]
async fn test_default_permissions_deny_create_contact() {
    let pool = test_helpers::setup_test_db().await;
    let wallet_id = test_helpers::create_test_wallet(&pool, "Restricted Wallet").await;
    let user_id = test_helpers::create_test_user(&pool).await;
    
    // Add user as 'member' (not owner/admin)
    test_helpers::add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    // Initialize default permissions (READ ONLY)
    // 1. Create all_users, all_contacts
    sqlx::query("INSERT INTO user_groups (wallet_id, name, is_system) VALUES ($1, 'all_users', true)")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO contact_groups (wallet_id, name, type, is_system) VALUES ($1, 'all_contacts', 'static', true)")
        .bind(wallet_id)
        .execute(&pool)
        .await
        .unwrap();
        
    let ug_id: Uuid = sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
        .bind(wallet_id).fetch_one(&pool).await.unwrap();
    let cg_id: Uuid = sqlx::query_scalar("SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'")
        .bind(wallet_id).fetch_one(&pool).await.unwrap();

    // Grant READ ONLY permissions
    let read_actions = vec!["contact:read", "transaction:read", "events:read"];
    for action in read_actions {
        let action_id: i16 = sqlx::query_scalar("SELECT id FROM permission_actions WHERE name = $1")
            .bind(action).fetch_one(&pool).await.unwrap();
        sqlx::query("INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id) VALUES ($1, $2, $3)")
            .bind(ug_id).bind(cg_id).bind(action_id).execute(&pool).await.unwrap();
    }

    // Prepare AppState
    let config = Arc::new(debt_tracker_api::config::Config::from_env().unwrap());
    let (tx, _rx) = broadcast::channel(100);
    let state = AppState {
        db_pool: Arc::new(pool.clone()),
        config,
        broadcast_tx: tx,
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    // Attempt to create contact
    let payload = CreateContactRequest {
        name: "Forbidden Contact".to_string(),
        username: None,
        phone: None,
        email: None,
        notes: None,
        comment: "Trying to bypass".to_string(),
        group_ids: None,
    };

    let result = create_contact(
        State(state.clone()),
        Extension(WalletContext::new(wallet_id, "member".to_string())),
        Extension(AuthUser { user_id, username: "test_user".to_string(), is_admin: false }),
        axum::http::HeaderMap::new(),
        Json(payload),
    ).await;

    // Should fail with 403
    match result {
        Err((code, body)) => {
            assert_eq!(code, StatusCode::FORBIDDEN);
            let body_json = body.0;
            assert_eq!(body_json["code"], "DEBITUM_INSUFFICIENT_WALLET_PERMISSION");
        },
        Ok(_) => panic!("Should have been forbidden"),
    }
}

#[tokio::test]
async fn test_granting_permission_allows_create_contact() {
    let pool = test_helpers::setup_test_db().await;
    let wallet_id = test_helpers::create_test_wallet(&pool, "Open Wallet").await;
    let user_id = test_helpers::create_test_user(&pool).await;
    test_helpers::add_user_to_wallet(&pool, user_id, wallet_id, "member").await;

    // Setup basic read-only defaults first
    sqlx::query("INSERT INTO user_groups (wallet_id, name, is_system) VALUES ($1, 'all_users', true)").bind(wallet_id).execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO contact_groups (wallet_id, name, type, is_system) VALUES ($1, 'all_contacts', 'static', true)").bind(wallet_id).execute(&pool).await.unwrap();
    
    // Prepare AppState
    let config = Arc::new(debt_tracker_api::config::Config::from_env().unwrap());
    let (tx, _rx) = broadcast::channel(100);
    let state = AppState {
        db_pool: Arc::new(pool.clone()), 
        config,
        broadcast_tx: tx,
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    };

    // 1. Create a new User Group "Editors"
    // We need to act as admin to create groups
    let admin_user = test_helpers::create_test_user(&pool).await;
    test_helpers::add_user_to_wallet(&pool, admin_user, wallet_id, "admin").await;

    let create_group_payload = CreateUserGroupRequest { name: "Editors".to_string() };
    let group_res = create_user_group(
        Path(wallet_id.to_string()),
        State(state.clone()),
        Extension(AuthUser { user_id: admin_user, username: "admin_user".to_string(), is_admin: false }),
        Json(create_group_payload),
    ).await.expect("create group");
    
    // group_res is (StatusCode, Json<UserGroupResponse>)
    let editors_group_id = Uuid::parse_str(&group_res.1.0.id).unwrap();

    // 2. Add our 'member' user to 'Editors'
    // Using direct SQL for speed
    sqlx::query("INSERT INTO user_group_members (user_id, user_group_id) VALUES ($1, $2)")
        .bind(user_id)
        .bind(editors_group_id)
        .execute(&pool)
        .await
        .unwrap();

    // 3. Grant 'contact:create' to 'Editors' -> 'all_contacts'
    let cg_id: Uuid = sqlx::query_scalar("SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'")
        .bind(wallet_id).fetch_one(&pool).await.unwrap();

    let action_id: i16 = sqlx::query_scalar("SELECT id FROM permission_actions WHERE name = 'contact:create'")
        .fetch_one(&pool).await.unwrap();
    
    sqlx::query("INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id) VALUES ($1, $2, $3)")
        .bind(editors_group_id)
        .bind(cg_id)
        .bind(action_id)
        .execute(&pool)
        .await
        .unwrap();

    // 4. Now attempt create contact as the 'member' user
    let payload = CreateContactRequest {
        name: "Allowed Contact".to_string(),
        username: None,
        phone: None,
        email: None,
        notes: None,
        comment: "I have power now".to_string(),
        group_ids: None,
    };

    let result = create_contact(
        State(state.clone()),
        Extension(WalletContext::new(wallet_id, "member".to_string())),
        Extension(AuthUser { user_id, username: "member_user".to_string(), is_admin: false }),
        axum::http::HeaderMap::new(),
        Json(payload),
    ).await;

    match result {
        Ok((status, _)) => assert!(status.is_success()),
        Err((code, body)) => panic!("Should have succeeded, got {}: {:?}", code, body),
    }
}
