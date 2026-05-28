pub mod error;
pub mod models;
pub mod repository;

mod pool;

pub use pool::{create_pool, new_pool, DatabasePool};
pub use repository::DatabaseRepository;

// Re-export common types
pub use sqlx::PgPool;
