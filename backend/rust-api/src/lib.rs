// Library root - exports for testing

pub mod config;
pub mod handlers;
pub mod database;
pub mod websocket;
pub mod models;
pub mod services;
pub mod background;
pub mod utils;
pub mod middleware;
use database::DatabasePool;
use std::sync::Arc;
use websocket::BroadcastChannel;

pub use config::Config;
pub use handlers::*;

// AppState for library (must match main.rs)
#[derive(Clone)]
pub struct AppState {
    pub db_pool: DatabasePool,
    pub config: Arc<Config>,
    pub broadcast_tx: BroadcastChannel,
}
