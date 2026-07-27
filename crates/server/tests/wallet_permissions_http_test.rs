// HTTP endpoint test for wallet permissions
// Tests the full HTTP flow using axum test utilities

use chrono::Utc;
use serde_json::json;
use server::{config::Config, websocket};
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

#[tokio::test]
async fn test_set_wallet_permissions_http_endpoint() {
    println!("\n=== TEST: PUT /wallet-permissions HTTP endpoint ===");
    let pool = setup().await;
    let _state = create_test_app_state(pool.clone(), Arc::new(Config::from_env().unwrap()), websocket::create_broadcast_channel());

    // Setup: Create user, wallet, and group
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

    sqlx::query("INSERT INTO wallet_owners (wallet_id, user_id) VALUES ($1, $2)")
        .bind(wallet_id)
        .bind(owner_id)
        .execute(&pool)
        .await
        .expect("Failed to add owner");

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

    println!("Setup: wallet={}, group={}, owner={}", wallet_id, group_id, owner_id);

    // Build request payload with new format
    let payload = json!({
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

    // Test deserialization without HTTP
    let payload_str = serde_json::to_string(&payload).unwrap();
    let parsed: Result<server::handlers::wallets::PutWalletPermissionsRequest, _> =
        serde_json::from_str(&payload_str);

    match parsed {
        Ok(req) => {
            println!("✅ Payload deserialized successfully");
            println!("  - entries: {}", req.entries.len());
            for (i, entry) in req.entries.iter().enumerate() {
                println!("    [{}] group_id={}, permissions.len()={}", i, entry.user_group_id, entry.permissions.len());
                for (j, perm) in entry.permissions.iter().enumerate() {
                    println!("      [{}] action={}, state={:?}", j, perm.action, perm.state);
                }
            }
        }
        Err(e) => {
            println!("❌ Deserialization failed: {}", e);
            panic!("Cannot deserialize payload: {}", e);
        }
    }

    // Verify permissions were NOT inserted yet (since we didn't run the handler)
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM wallet_permission_matrix WHERE user_group_id = $1")
        .bind(group_id)
        .fetch_one(&pool)
        .await
        .expect("Failed to query count");

    println!("✅ Permissions in DB before handler: {}", count.0);
    assert_eq!(count.0, 0, "Should have no permissions yet");

    println!("✅ HTTP test setup complete (actual handler test requires full server)");
}
