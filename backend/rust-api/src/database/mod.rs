use sqlx::PgPool;
use std::sync::Arc;

pub type DatabasePool = Arc<PgPool>;

pub async fn create_pool(database_url: &str) -> anyhow::Result<PgPool> {
    let pool = PgPool::connect(database_url).await?;
    Ok(pool)
}

pub async fn new_pool(database_url: &str) -> anyhow::Result<DatabasePool> {
    let pool = create_pool(database_url).await?;
    Ok(Arc::new(pool))
}
