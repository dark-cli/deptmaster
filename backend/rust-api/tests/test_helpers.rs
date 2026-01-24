// Test helpers for setting up test database and data

use sqlx::PgPool;
use uuid::Uuid;
use chrono::Utc;

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
    sqlx::query("DELETE FROM users_projection").execute(&pool).await.ok();
    
    pool
}

pub async fn create_test_user(pool: &PgPool) -> Uuid {
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id) 
         VALUES ($1, $2, $3, NOW(), 0)"
    )
    .bind(user_id)
    .bind("test@example.com")
    .bind("hashed_password")
    .execute(pool)
    .await
    .expect("Failed to create test user");
    
    user_id
}

pub async fn create_test_contact(pool: &PgPool, user_id: Uuid, name: &str) -> Uuid {
    let contact_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO contacts_projection (id, user_id, name, is_deleted, created_at, updated_at, last_event_id) 
         VALUES ($1, $2, $3, false, NOW(), NOW(), 0)"
    )
    .bind(contact_id)
    .bind(user_id)
    .bind(name)
    .execute(pool)
    .await
    .expect("Failed to create test contact");
    
    contact_id
}

pub async fn create_test_transaction(
    pool: &PgPool,
    user_id: Uuid,
    contact_id: Uuid,
    amount: i64,
    direction: &str,
) -> Uuid {
    let transaction_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO transactions_projection 
         (id, user_id, contact_id, type, direction, amount, currency, transaction_date, is_deleted, created_at, updated_at, last_event_id) 
         VALUES ($1, $2, $3, 'money', $4, $5, 'USD', CURRENT_DATE, false, NOW(), NOW(), 0)"
    )
    .bind(transaction_id)
    .bind(user_id)
    .bind(contact_id)
    .bind(direction)
    .bind(amount)
    .execute(pool)
    .await
    .expect("Failed to create test transaction");
    
    transaction_id
}

pub async fn get_contact_balance(pool: &PgPool, contact_id: Uuid) -> i64 {
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
        WHERE contact_id = $1 AND is_deleted = false
        "#
    )
    .bind(contact_id)
    .fetch_one(pool)
    .await
    .expect("Failed to get contact balance")
}
