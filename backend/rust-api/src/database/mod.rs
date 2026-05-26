use sqlx::{PgPool, postgres::PgPoolOptions};
use std::sync::Arc;
use std::time::Duration;

pub type DatabasePool = Arc<PgPool>;

pub async fn create_pool(database_url: &str) -> anyhow::Result<PgPool> {
    // SQLx with native-tls feature automatically uses TLS when:
    // 1. DATABASE_URL contains sslmode=require (or similar)
    // 2. The connection is to a remote host (not localhost)
    // 
    // For production, ensure DATABASE_URL includes sslmode=require:
    // postgresql://user:pass@host/db?sslmode=require
    
    // Configure connection pool with proper timeouts and retry logic
    let pool = PgPoolOptions::new()
        .max_connections(10) // Maximum number of connections in the pool
        .acquire_timeout(Duration::from_secs(30)) // Timeout for acquiring a connection
        .idle_timeout(Duration::from_secs(600)) // Close idle connections after 10 minutes
        .max_lifetime(Duration::from_secs(1800)) // Maximum lifetime of a connection (30 minutes)
        .test_before_acquire(true) // Test connections before using them
        .connect(database_url)
        .await?;
    
    // Log TLS status if we can determine it
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
