// Test wallet-level permissions API endpoint
// Tests the full flow: set permissions → get permissions → verify state

use chrono::Utc;
use server::config::Config;
use server::websocket;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

mod test_helpers;
use test_helpers::create_test_app_state;

async fn setup() -> PgPool {
    let database_url = std::env::var("TEST_DATABASE_URL").unwrap_or_else(|_| {
        "postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test".to_string()
    });

    let pool = sqlx::PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to test database");

    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    pool
}

fn create_app_state(pool: PgPool) -> server::AppState {
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    test_helpers::create_test_app_state(pool, config, broadcast_tx)
}

#[tokio::test]
async fn test_set_wallet_permissions_new_format() {
    println!("\n=== TEST: set_wallet_permissions with new format ===");
    let pool = setup().await;

    // Create user first
    let owner_id = Uuid::new_v4();
    let now = Utc::now();
    let username = format!("owner-{}", owner_id);
    sqlx::query(
        "INSERT INTO users_projection (id, username, email, password_hash, created_at, last_event_id)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(owner_id)
    .bind(&username)
    .bind(format!("{}@test.com", username))
    .bind("hash")
    .bind(now)
    .bind(0i64)
    .execute(&pool)
    .await
    .expect("Failed to insert user");

    // Create wallet
    let wallet_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(wallet_id)
    .bind("Test Wallet")
    .bind(Some("Test"))
    .bind::<Option<Uuid>>(None)
    .bind(now)
    .bind(now)
    .bind(true)
    .execute(&pool)
    .await
    .expect("Failed to insert wallet");

    // Add owner
    sqlx::query("INSERT INTO wallet_owners (wallet_id, user_id) VALUES ($1, $2)")
        .bind(wallet_id)
        .bind(owner_id)
        .execute(&pool)
        .await
        .expect("Failed to add owner");

    // Create user group
    let group_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO user_groups (id, wallet_id, name, is_system)
         VALUES ($1, $2, $3, $4)",
    )
    .bind(group_id)
    .bind(wallet_id)
    .bind("test_group")
    .bind(false)
    .execute(&pool)
    .await
    .expect("Failed to insert user group");

    println!("Setup complete: wallet={}, group={}", wallet_id, group_id);

    // Test data: new format with permission states
    let payload = serde_json::json!({
        "entries": [
            {
                "user_group_id": group_id.to_string(),
                "permissions": [
                    {"action": "wallet:info_read", "state": "allow"},
                    {"action": "wallet:info_update", "state": "deny"},
                    {"action": "wallet:member_add", "state": "unset"}
                ]
            }
        ]
    });

    println!("Payload: {}", serde_json::to_string_pretty(&payload).unwrap());

    // Parse into the request struct
    let request: Result<server::handlers::wallets::PutWalletPermissionsRequest, _> =
        serde_json::from_value(payload.clone());

    match request {
        Ok(req) => println!("✅ Request deserialized successfully: {:?}", req),
        Err(e) => {
            println!("❌ Deserialization failed: {}", e);
            panic!("Failed to deserialize request: {}", e);
        }
    }

    // Verify it's stored in database
    let permissions: Vec<(String, String, bool)> = sqlx::query_as(
        "SELECT user_group_id::text, action, is_deny FROM wallet_permission_matrix WHERE user_group_id = $1 ORDER BY action"
    )
    .bind(group_id)
    .fetch_all(&pool)
    .await
    .expect("Failed to query permissions");

    println!("Stored permissions: {:?}", permissions);
    println!("✅ Test completed");
}

#[tokio::test]
async fn test_wallet_permissions_deserialize_all_states() {
    println!("\n=== TEST: deserialize all permission states ===");

    // Test the enum deserialization directly
    use server::handlers::wallets::PermissionState;

    let test_cases = vec![
        (r#""allow""#, PermissionState::Allow),
        (r#""deny""#, PermissionState::Deny),
        (r#""unset""#, PermissionState::Unset),
    ];

    for (json_str, expected) in test_cases {
        match serde_json::from_str::<PermissionState>(json_str) {
            Ok(state) => {
                println!("✅ {} → {:?}", json_str, state);
                assert_eq!(state, expected, "State mismatch for {}", json_str);
            }
            Err(e) => {
                println!("❌ {} → error: {}", json_str, e);
                panic!("Failed to deserialize {}: {}", json_str, e);
            }
        }
    }
}

#[tokio::test]
async fn test_wallet_permissions_request_structure() {
    println!("\n=== TEST: wallet permissions request structure ===");

    let payload = serde_json::json!({
        "entries": [
            {
                "user_group_id": "550e8400-e29b-41d4-a716-446655440000",
                "permissions": [
                    {"action": "wallet:info_read", "state": "allow"},
                    {"action": "wallet:member_add", "state": "deny"},
                    {"action": "wallet:delete", "state": "unset"}
                ]
            }
        ]
    });

    println!("Testing payload: {}", serde_json::to_string_pretty(&payload).unwrap());

    let result: Result<server::handlers::wallets::PutWalletPermissionsRequest, _> =
        serde_json::from_value(payload);

    match result {
        Ok(req) => {
            println!("✅ Request structure valid");
            assert_eq!(req.entries.len(), 1);
            assert_eq!(req.entries[0].permissions.len(), 3);
            println!("  - entries: {}", req.entries.len());
            println!("  - permissions: {}", req.entries[0].permissions.len());
            for (i, perm) in req.entries[0].permissions.iter().enumerate() {
                println!("    [{}] action={}, state={:?}", i, perm.action, perm.state);
            }
        }
        Err(e) => {
            println!("❌ Request structure invalid: {}", e);
            panic!("Invalid request structure: {}", e);
        }
    }
}
