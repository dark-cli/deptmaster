use sqlx::{postgres::PgPoolOptions, PgPool};
use std::sync::Arc;
use std::time::Duration;

pub type DatabasePool = Arc<PgPool>;

pub async fn create_pool(database_url: &str) -> anyhow::Result<PgPool> {
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .acquire_timeout(Duration::from_secs(30))
        .idle_timeout(Duration::from_secs(600))
        .max_lifetime(Duration::from_secs(1800))
        .test_before_acquire(true)
        .connect(database_url)
        .await?;

    if database_url.contains("sslmode=require") || database_url.contains("sslmode=prefer") {
        tracing::info!("✅ Database connection configured to use TLS");
    } else if !database_url.contains("localhost") && !database_url.contains("127.0.0.1") {
        tracing::warn!("⚠️  Connecting to remote database without explicit sslmode. Consider adding sslmode=require");
    }

    tracing::info!("✅ Database connection pool configured: max_connections=10, idle_timeout=10min, max_lifetime=30min");

    Ok(pool)
}

pub async fn new_pool(database_url: &str) -> anyhow::Result<DatabasePool> {
    let pool = create_pool(database_url).await?;
    Ok(Arc::new(pool))
}
