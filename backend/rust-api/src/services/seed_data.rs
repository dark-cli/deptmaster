use sqlx::PgPool;
use uuid::Uuid;
use chrono::Utc;

pub async fn seed_dummy_data(pool: &PgPool) -> anyhow::Result<()> {
    // Check if data already exists
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users_projection")
        .fetch_one(pool)
        .await?;

    if count > 0 {
        tracing::info!("Database already has data, skipping seed");
        return Ok(());
    }

    tracing::info!("Creating default user 'max'...");

    // Create default user "max" with password "1234"
    let user_id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id)
        VALUES ($1, $2, $3, $4, 0)
        "#
    )
    .bind(&user_id)
    .bind("max")  // Email/username is "max"
    .bind("$2b$12$MzvHQ6CeZgenzzwkEV2WeeDQscVKQed1kTh8NxB7w2bXCXe2qFjxK") // bcrypt hash for "1234"
    .bind(Utc::now())
    .execute(pool)
    .await?;

    tracing::info!("Default user 'max' created successfully");
    
    // Don't seed dummy data - user will import their own data
    Ok(())
}
