// Test helpers for setting up test database and data

use sqlx::PgPool;
use uuid::Uuid;
use chrono::Utc;
use debt_tracker_api::middleware::auth::AuthUser;
use debt_tracker_api::middleware::wallet_context::WalletContext;

pub async fn setup_test_db() -> PgPool {
    let database_url = std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test".to_string());
    
    let pool = sqlx::PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to test database");
    
    // Reset database schema to ensure clean state
    sqlx::query("DROP SCHEMA public CASCADE").execute(&pool).await.expect("Failed to drop schema");
    sqlx::query("CREATE SCHEMA public").execute(&pool).await.expect("Failed to create schema");

    // Run migrations (required for tests that use wallets, permission tables, etc.)
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations - ensure TEST_DATABASE_URL points to a database that can be migrated");

    // Clear test data (redundant if we dropped schema, but harmless)
    // ...
    sqlx::query("DELETE FROM projection_snapshots").execute(&pool).await.ok();
    sqlx::query("DELETE FROM transactions_projection").execute(&pool).await.ok();
    sqlx::query("DELETE FROM contacts_projection").execute(&pool).await.ok();
    sqlx::query("DELETE FROM events").execute(&pool).await.ok();
    sqlx::query("DELETE FROM wallet_users").execute(&pool).await.ok();
    sqlx::query("DELETE FROM wallets").execute(&pool).await.ok();
    sqlx::query("DELETE FROM users_projection").execute(&pool).await.ok();
    // Permission tables: CASCADE from wallets, but clear if any orphaned
    sqlx::query("DELETE FROM user_wallet_settings").execute(&pool).await.ok();
    sqlx::query("DELETE FROM group_permission_matrix").execute(&pool).await.ok();
    sqlx::query("DELETE FROM user_group_members").execute(&pool).await.ok();
    sqlx::query("DELETE FROM contact_group_members").execute(&pool).await.ok();
    sqlx::query("DELETE FROM user_groups").execute(&pool).await.ok();
    sqlx::query("DELETE FROM contact_groups").execute(&pool).await.ok();

    pool
}

/// Ensure a wallet has system groups (all_users, all_contacts) and default permission matrix.
/// Call after create_test_wallet when tests need permission resolution for members.
pub async fn ensure_wallet_has_system_groups(pool: &PgPool, wallet_id: Uuid) {
    sqlx::query(
        "INSERT INTO user_groups (wallet_id, name, is_system) VALUES ($1, 'all_users', true)
         ON CONFLICT (wallet_id, name) DO UPDATE SET is_system = true",
    )
    .bind(wallet_id)
    .execute(pool)
    .await
    .expect("create all_users");

    sqlx::query(
        "INSERT INTO contact_groups (wallet_id, name, type, is_system) VALUES ($1, 'all_contacts', 'static', true)
         ON CONFLICT (wallet_id, name) DO NOTHING",
    )
    .bind(wallet_id)
    .execute(pool)
    .await
    .expect("create all_contacts");

    let ug_id: Uuid = sqlx::query_scalar("SELECT id FROM user_groups WHERE wallet_id = $1 AND name = 'all_users'")
        .bind(wallet_id)
        .fetch_one(pool)
        .await
        .expect("get all_users id");
    let cg_id: Uuid = sqlx::query_scalar("SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts'")
        .bind(wallet_id)
        .fetch_one(pool)
        .await
        .expect("get all_contacts id");

    for act_id in 1..=10_i16 {
        sqlx::query(
            "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id)
             VALUES ($1, $2, $3) ON CONFLICT (user_group_id, contact_group_id, permission_action_id) DO NOTHING",
        )
        .bind(ug_id)
        .bind(cg_id)
        .bind(act_id)
        .execute(pool)
        .await
        .ok();
    }
}

pub async fn create_test_user(pool: &PgPool) -> Uuid {
    create_test_user_with_email(pool, &format!("test-{}@example.com", Uuid::new_v4())).await
}

pub async fn create_test_user_with_email(pool: &PgPool, email: &str) -> Uuid {
    let user_id = Uuid::new_v4();
    let username = email.split('@').next().unwrap_or("testuser");
    sqlx::query(
        "INSERT INTO users_projection (id, email, username, password_hash, created_at, last_event_id) 
         VALUES ($1, $2, $3, $4, NOW(), 0)"
    )
    .bind(user_id)
    .bind(email)
    .bind(username)
    .bind("$2b$12$MzvHQ6CeZgenzzwkEV2WeeDQscVKQed1kTh8NxB7w2bXCXe2qFjxK") // bcrypt hash for "1234"
    .execute(pool)
    .await
    .expect("Failed to create test user");
    
    user_id
}

pub async fn create_test_wallet(pool: &PgPool, name: &str) -> Uuid {
    let wallet_id = Uuid::new_v4();
    let now = Utc::now();
    sqlx::query(
        "INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
         VALUES ($1, $2, $3, NULL, $4, $4, true)"
    )
    .bind(wallet_id)
    .bind(name)
    .bind::<Option<String>>(None)
    .bind(now)
    .execute(pool)
    .await
    .expect("Failed to create test wallet");
    
    wallet_id
}

pub async fn add_user_to_wallet(pool: &PgPool, user_id: Uuid, wallet_id: Uuid, role: &str) {
    let now = Utc::now();
    sqlx::query(
        "INSERT INTO wallet_users (wallet_id, user_id, role, subscribed_at)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (wallet_id, user_id) DO UPDATE SET role = $3"
    )
    .bind(wallet_id)
    .bind(user_id)
    .bind(role)
    .bind(now)
    .execute(pool)
    .await
    .expect("Failed to add user to wallet");
}

pub async fn create_test_contact(pool: &PgPool, user_id: Uuid, wallet_id: Uuid, name: &str) -> Uuid {
    let contact_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO contacts_projection (id, user_id, wallet_id, name, is_deleted, created_at, updated_at, last_event_id) 
         VALUES ($1, $2, $3, $4, false, NOW(), NOW(), 0)"
    )
    .bind(contact_id)
    .bind(user_id)
    .bind(wallet_id)
    .bind(name)
    .execute(pool)
    .await
    .expect("Failed to create test contact");
    
    contact_id
}

pub async fn create_test_transaction(
    pool: &PgPool,
    user_id: Uuid,
    wallet_id: Uuid,
    contact_id: Uuid,
    amount: i64,
    direction: &str,
) -> Uuid {
    let transaction_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO transactions_projection 
         (id, user_id, wallet_id, contact_id, type, direction, amount, currency, transaction_date, is_deleted, created_at, updated_at, last_event_id) 
         VALUES ($1, $2, $3, $4, 'money', $5, $6, 'USD', CURRENT_DATE, false, NOW(), NOW(), 0)"
    )
    .bind(transaction_id)
    .bind(user_id)
    .bind(wallet_id)
    .bind(contact_id)
    .bind(direction)
    .bind(amount)
    .execute(pool)
    .await
    .expect("Failed to create test transaction");
    
    transaction_id
}

pub async fn get_contact_balance(pool: &PgPool, wallet_id: Uuid, contact_id: Uuid) -> i64 {
    sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COALESCE(SUM(
            CASE 
                WHEN direction = 'lent' THEN amount
                WHEN direction = 'owed' THEN -amount
                ELSE 0
            END
        )::BIGINT, 0) as balance
        FROM transactions_projection
        WHERE contact_id = $1 AND wallet_id = $2 AND is_deleted = false
        "#
    )
    .bind(contact_id)
    .bind(wallet_id)
    .fetch_one(pool)
    .await
    .expect("Failed to get contact balance")
}

/// Create Extension<WalletContext> for calling handlers in tests
pub fn wallet_context_extension(wallet_id: Uuid, role: &str) -> axum::extract::Extension<WalletContext> {
    axum::extract::Extension(WalletContext::new(wallet_id, role.to_string()))
}

/// Create Extension<AuthUser> for calling handlers that require auth in tests
pub fn auth_user_extension(user_id: Uuid, username: Option<&str>) -> axum::extract::Extension<AuthUser> {
    axum::extract::Extension(AuthUser {
        user_id,
        username: username.unwrap_or("test_user").to_string(),
        is_admin: false,
    })
}

/// Create AppState for tests
pub fn create_test_app_state(
    pool: PgPool,
    config: std::sync::Arc<debt_tracker_api::config::Config>,
    broadcast_tx: debt_tracker_api::websocket::BroadcastChannel,
) -> debt_tracker_api::AppState {
    use std::sync::Arc;
    debt_tracker_api::AppState {
        db_pool: Arc::new(pool),
        config,
        broadcast_tx,
        rate_limiter: debt_tracker_api::middleware::rate_limit::RateLimiter::new(100, 60),
    }
}
