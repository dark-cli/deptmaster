use async_trait::async_trait;
use sqlx::PgPool;

#[async_trait]
pub trait DatabaseRepository: Send + Sync {
    // TODO: Add repository methods in Phase 2
    // Events, Contacts, Transactions, Wallets, Permissions, Users queries
}

pub struct Database {
    pool: PgPool,
}

impl Database {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl DatabaseRepository for Database {
    // TODO: Implement trait methods in Phase 2
}
