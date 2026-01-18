// Library root - exports for testing

pub mod config;
pub mod handlers;
pub mod database;
pub mod websocket;
pub mod models;
pub mod services;
pub mod background;
pub mod utils;

pub use config::Config;
pub use handlers::*;

// Re-export AppState for tests (matches main.rs)
use database::DatabasePool;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DatabasePool,
    pub config: Arc<Config>,
    pub broadcast_tx: websocket::BroadcastChannel,
}
