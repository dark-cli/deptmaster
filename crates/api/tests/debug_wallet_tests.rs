// Debug tests to investigate wallet handler failures
// Each test is completely isolated with fresh data

use chrono::Utc;
use api::config::Config;
use api::handlers::wallets;
use api::middleware::auth::AuthUser;
use api::websocket;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

mod test_helpers;
use test_helpers::*;

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

fn create_app_state(pool: PgPool) -> api::AppState {
    let config = Arc::new(Config::from_env().unwrap());
    let broadcast_tx = websocket::create_broadcast_channel();
    test_helpers::create_test_app_state(pool, config, broadcast_tx)
}

#[tokio::test]

async fn test_get_wallet_isolated() {
    println!("\n=== TEST: get_wallet with fresh data ===");
    let pool = setup().await;

    // Create fresh wallet
    let wallet_id = Uuid::new_v4();
    let now = Utc::now();

    let insert_result = sqlx::query(
        "INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(wallet_id)
    .bind("Debug Test Wallet")
    .bind(Some("Test description".to_string()))
    .bind::<Option<Uuid>>(None)
    .bind(now)
    .bind(now)
    .bind(true)
    .execute(&pool)
    .await;

    println!("Insert result: OK");
    assert!(insert_result.is_ok(), "Failed to insert wallet");

    // Verify wallet exists in DB
    let db_wallet: Option<(String, bool)> =
        sqlx::query_as("SELECT name, is_active FROM wallets WHERE id = $1")
            .bind(wallet_id)
            .fetch_optional(&pool)
            .await
            .expect("Failed to query")
            .map(|(name, is_active)| (name, is_active));

    println!("DB wallet: {:?}", db_wallet);
    assert!(db_wallet.is_some(), "Wallet not found in DB");
    let (name, is_active) = db_wallet.unwrap();
    assert_eq!(name, "Debug Test Wallet");
    assert!(is_active);

    // Now call handler
    let app_state = create_app_state(pool);

    println!("Calling get_wallet handler with ID: {}", wallet_id);
    let result = wallets::get_wallet(
        axum::extract::Path(wallet_id.to_string()),
        axum::extract::State(app_state),
    )
    .await;

    match result {
        Ok(json) => {
            println!("Success! Wallet: id={}, name={}", json.id, json.name);
            assert_eq!(json.id, wallet_id.to_string());
        }
        Err((status, _json)) => {
            println!("Error! Status: {:?}", status);
            panic!("Handler returned error with status {:?}", status);
        }
    }
}

#[tokio::test]
async fn test_list_wallets_isolated() {
    println!("\n=== TEST: list_wallets with fresh data ===");
    let pool = setup().await;

    // Create fresh wallet
    let wallet_id = Uuid::new_v4();
    let now = Utc::now();

    let insert_result = sqlx::query(
        "INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(wallet_id)
    .bind("Debug List Test Wallet")
    .bind::<Option<String>>(None)
    .bind::<Option<Uuid>>(None)
    .bind(now)
    .bind(now)
    .bind(true)
    .execute(&pool)
    .await;

    println!("Insert result: {:?}", insert_result);
    assert!(insert_result.is_ok());

    // Query to see active wallets
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM wallets WHERE is_active = true")
        .fetch_one(&pool)
        .await
        .expect("Failed to count");

    println!("Total active wallets in DB: {}", count);

    // Call handler
    let app_state = create_app_state(pool);

    println!("Calling list_wallets handler");
    let result = wallets::list_wallets(axum::extract::State(app_state)).await;

    match result {
        Ok(response) => {
            println!("Success! Returned {} wallets", response.wallets.len());
            for wallet in &response.wallets {
                println!("  - {}: {}", wallet.id, wallet.name);
            }
            assert!(
                response.wallets.len() > 0,
                "Should return at least one wallet"
            );
        }
        Err((status, _json)) => {
            println!("Error! Status: {:?}", status);
            panic!("Handler returned error with status {:?}", status);
        }
    }
}

#[tokio::test]
async fn test_add_user_to_wallet_isolated() {
    println!("\n=== TEST: add_user_to_wallet with fresh data ===");
    let pool = setup().await;

    // Create fresh user
    let acting_user_id = create_test_user(&pool).await;
    println!("Created acting user: {}", acting_user_id);

    // Create target user
    let target_email = format!("debug-target-{}@example.com", Uuid::new_v4());
    let target_user_id = test_helpers::create_test_user_with_email(&pool, &target_email).await;
    let target_username = target_email.split('@').next().unwrap().to_string();
    println!(
        "Created target user: {} ({})",
        target_user_id, target_username
    );

    // Verify target user exists
    let user_exists: Option<String> =
        sqlx::query_scalar("SELECT username FROM users_projection WHERE id = $1")
            .bind(target_user_id)
            .fetch_optional(&pool)
            .await
            .expect("Failed to query")
            .flatten();

    println!("Target user in DB: {:?}", user_exists);
    assert!(user_exists.is_some(), "Target user not in DB");

    // Create fresh wallet
    let wallet_id = create_test_wallet(&pool, "Debug Add User Test Wallet").await;
    println!("Created wallet: {}", wallet_id);

    // Add acting user as owner
    add_user_to_wallet(&pool, acting_user_id, wallet_id, "owner").await;
    println!("Added acting user as owner");

    // Verify wallet-user relationship
    let user_role: Option<String> =
        sqlx::query_scalar("SELECT role FROM wallet_users WHERE wallet_id = $1 AND user_id = $2")
            .bind(wallet_id)
            .bind(acting_user_id)
            .fetch_optional(&pool)
            .await
            .expect("Failed to query")
            .flatten();

    println!("Acting user role in wallet: {:?}", user_role);
    assert_eq!(user_role, Some("owner".to_string()));

    // Call handler
    let app_state = create_app_state(pool);

    let add_request = wallets::AddUserToWalletRequest {
        username: target_username.clone(),
    };

    println!("Calling add_user_to_wallet handler");
    let result = wallets::add_user_to_wallet(
        axum::extract::Path(wallet_id.to_string()),
        axum::extract::State(app_state),
        axum::extract::Extension(AuthUser {
            user_id: acting_user_id,
            username: "acting".to_string(),
            is_admin: false,
        }),
        axum::Json(add_request),
    )
    .await;

    println!("Handler result: {:?}", result);
    match result {
        Ok((status, json)) => {
            println!("Success! Status: {:?}, Body: {:?}", status, json);
            assert_eq!(status, axum::http::StatusCode::CREATED);
        }
        Err((status, json)) => {
            println!("Error! Status: {:?}, Body: {:?}", status, json);
            panic!("Handler returned error");
        }
    }
}

#[tokio::test]
async fn test_repository_get_wallet() {
    println!("\n=== TEST: Repository get_wallet method directly ===");
    let pool = setup().await;

    // Create fresh wallet
    let wallet_id = Uuid::new_v4();
    let now = Utc::now();

    let insert_result = sqlx::query(
        "INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(wallet_id)
    .bind("Debug Repo Test Wallet")
    .bind(Some("Repo test".to_string()))
    .bind::<Option<Uuid>>(None)
    .bind(now)
    .bind(now)
    .bind(true)
    .execute(&pool)
    .await;

    println!("Insert result: OK");
    assert!(insert_result.is_ok());

    // Use repository directly
    use api::database::repository::{Database, DatabaseRepository};

    let db = Database::new(pool.clone());

    println!("Calling repository get_wallet");
    let repo_result = db.get_wallet(wallet_id).await;

    println!("Repository result: {:?}", repo_result);
    match repo_result {
        Ok(wallet_opt) => match wallet_opt {
            Some(wallet) => {
                println!(
                    "Success! Wallet: id={}, name={}, is_active={}",
                    wallet.id, wallet.name, wallet.is_active
                );
                assert_eq!(wallet.id, wallet_id);
                assert_eq!(wallet.name, "Debug Repo Test Wallet");
                assert!(wallet.is_active);
            }
            None => panic!("Repository returned None"),
        },
        Err(e) => {
            println!("Repository error: {:?}", e);
            panic!("Repository failed");
        }
    }
}

#[tokio::test]
async fn test_repository_list_wallets() {
    println!("\n=== TEST: Repository get_all_active_wallets method ===");
    let pool = setup().await;

    // Create fresh wallet
    let wallet_id = Uuid::new_v4();
    let now = Utc::now();

    let insert_result = sqlx::query(
        "INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(wallet_id)
    .bind("Debug List Repo Test")
    .bind::<Option<String>>(None)
    .bind::<Option<Uuid>>(None)
    .bind(now)
    .bind(now)
    .bind(true)
    .execute(&pool)
    .await;

    println!("Insert result: {:?}", insert_result);
    assert!(insert_result.is_ok());

    use api::database::repository::{Database, DatabaseRepository};

    let db = Database::new(pool.clone());

    println!("Calling repository get_all_active_wallets");
    let repo_result = db.get_all_active_wallets().await;

    println!("Repository result: {:?}", repo_result);
    match repo_result {
        Ok(wallets) => {
            println!("Success! Found {} wallets", wallets.len());
            for w in &wallets {
                println!("  - {}: {} (active={})", w.id, w.name, w.is_active);
            }
            assert!(wallets.len() > 0);
        }
        Err(e) => {
            println!("Repository error: {:?}", e);
            panic!("Repository failed");
        }
    }
}

#[tokio::test]
async fn test_add_user_detailed() {
    println!("\n=== TEST: add_user_to_wallet detailed debug ===");
    let pool = setup().await;

    // Step 1: Create users
    let acting_user_id = create_test_user(&pool).await;
    println!("Step 1: Created acting user: {}", acting_user_id);

    let target_email = format!("debug-add-user-{}@example.com", Uuid::new_v4());
    let target_user_id = test_helpers::create_test_user_with_email(&pool, &target_email).await;
    let target_username = target_email.split('@').next().unwrap().to_string();
    println!(
        "Step 2: Created target user: {} (username: {})",
        target_user_id, target_username
    );

    // Step 2: Create wallet
    let wallet_id = create_test_wallet(&pool, "Test Wallet for Add User").await;
    println!("Step 3: Created wallet: {}", wallet_id);

    // Step 3: Add acting user as owner
    add_user_to_wallet(&pool, acting_user_id, wallet_id, "owner").await;
    println!("Step 4: Added acting user as owner");

    // Step 4: Test get_user_by_username directly
    use api::database::repository::{Database, DatabaseRepository};
    let db = Database::new(pool.clone());

    println!("\nStep 5: Testing get_user_by_username...");
    match db.get_user_by_username(&target_username).await {
        Ok(Some(user)) => {
            println!(
                "  ✓ Found user: id={}, username={:?}",
                user.id, user.username
            );
        }
        Ok(None) => {
            println!("  ✗ User not found!");
            panic!("get_user_by_username returned None");
        }
        Err(e) => {
            println!("  ✗ Database error: {:?}", e);
            panic!("get_user_by_username failed: {:?}", e);
        }
    }

    // Step 5: Test wallet_exists directly
    println!("\nStep 6: Testing wallet_exists...");
    match db.wallet_exists(wallet_id).await {
        Ok(true) => {
            println!("  ✓ Wallet exists");
        }
        Ok(false) => {
            println!("  ✗ Wallet not found!");
            panic!("wallet_exists returned false");
        }
        Err(e) => {
            println!("  ✗ Database error: {:?}", e);
            panic!("wallet_exists failed: {:?}", e);
        }
    }

    // Step 6: Test wallet_user_exists
    println!("\nStep 7: Testing wallet_user_exists for acting user...");
    match db.wallet_user_exists(wallet_id, acting_user_id).await {
        Ok(exists) => {
            println!("  ✓ Acting user in wallet: {}", exists);
        }
        Err(e) => {
            println!("  ✗ Database error: {:?}", e);
            panic!("wallet_user_exists failed: {:?}", e);
        }
    }

    // Step 7: Test add_wallet_user directly (the underlying operation)
    println!("\nStep 8: Testing add_wallet_user directly...");
    match db
        .add_wallet_user(wallet_id, target_user_id, "member".to_string())
        .await
    {
        Ok(_) => {
            println!("  ✓ Successfully added user to wallet");
        }
        Err(e) => {
            println!("  ✗ Database error: {:?}", e);
            panic!("add_wallet_user failed: {:?}", e);
        }
    }

    // Step 8: Verify the user was added
    println!("\nStep 9: Verifying user was added...");
    let user_role: Option<String> =
        sqlx::query_scalar("SELECT role FROM wallet_users WHERE wallet_id = $1 AND user_id = $2")
            .bind(wallet_id)
            .bind(target_user_id)
            .fetch_optional(&pool)
            .await
            .expect("Failed to query")
            .flatten();

    match user_role {
        Some(role) => {
            println!("  ✓ User role in wallet: {}", role);
        }
        None => {
            println!("  ✗ User not in wallet!");
            panic!("User was not added to wallet");
        }
    }

    println!("\n✓ All steps passed!");
}
