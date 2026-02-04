// Test helpers for setting up test database and data

use sqlx::PgPool;
use uuid::Uuid;
use chrono::Utc;
use debt_tracker_api::middleware::wallet_context::WalletContext;

pub async fn setup_test_db() -> PgPool {
    let database_url = std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test".to_string());
    
    let pool = sqlx::PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to test database");
    
    // Run migrations (ignore errors if tables already exist)
    let _ = sqlx::migrate!("./migrations")
        .run(&pool)
        .await;
    
    // Clear test data (in correct order due to foreign keys)
    sqlx::query("DELETE FROM projection_snapshots").execute(&pool).await.ok();
    sqlx::query("DELETE FROM transactions_projection").execute(&pool).await.ok();
    sqlx::query("DELETE FROM contacts_projection").execute(&pool).await.ok();
    sqlx::query("DELETE FROM events").execute(&pool).await.ok();
    sqlx::query("DELETE FROM wallet_users").execute(&pool).await.ok();
    sqlx::query("DELETE FROM wallets").execute(&pool).await.ok();
    sqlx::query("DELETE FROM users_projection").execute(&pool).await.ok();
    
    pool
}

pub async fn create_test_user(pool: &PgPool) -> Uuid {
    create_test_user_with_email(pool, &format!("test-{}@example.com", Uuid::new_v4())).await
}

pub async fn create_test_user_with_email(pool: &PgPool, email: &str) -> Uuid {
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id) 
         VALUES ($1, $2, $3, NOW(), 0)"
    )
    .bind(user_id)
    .bind(email)
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

/// Create Extension<WalletContext> for calling post_sync_events in tests
pub fn wallet_context_extension(wallet_id: Uuid, role: &str) -> axum::extract::Extension<WalletContext> {
    axum::extract::Extension(WalletContext::new(wallet_id, role.to_string()))
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
