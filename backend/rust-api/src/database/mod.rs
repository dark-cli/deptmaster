use sqlx::PgPool;
use std::sync::Arc;

pub type DatabasePool = Arc<PgPool>;

pub async fn create_pool(database_url: &str) -> anyhow::Result<PgPool> {
    // SQLx with native-tls feature automatically uses TLS when:
    // 1. DATABASE_URL contains sslmode=require (or similar)
    // 2. The connection is to a remote host (not localhost)
    // 
    // For production, ensure DATABASE_URL includes sslmode=require:
    // postgresql://user:pass@host/db?sslmode=require
    
    let pool = PgPool::connect(database_url).await?;
    
    // Log TLS status if we can determine it
    if database_url.contains("sslmode=require") || database_url.contains("sslmode=prefer") {
        tracing::info!("✅ Database connection configured to use TLS");
    } else if !database_url.contains("localhost") && !database_url.contains("127.0.0.1") {
        tracing::warn!("⚠️  Connecting to remote database without explicit sslmode. Consider adding sslmode=require");
    }
    
    Ok(pool)
}

pub async fn new_pool(database_url: &str) -> anyhow::Result<DatabasePool> {
    let pool = create_pool(database_url).await?;
    Ok(Arc::new(pool))
}
