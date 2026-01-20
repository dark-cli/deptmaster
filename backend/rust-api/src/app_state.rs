use std::sync::Arc;
use crate::config::Config;
use crate::database::DatabasePool;
use crate::websocket::BroadcastChannel;

// Import EventStoreClient
// Note: This will work when building the binary (main.rs)
// For library builds, we need to ensure services::eventstore is available
pub use crate::services::eventstore::EventStoreClient;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DatabasePool,
    pub config: Arc<Config>,
    pub broadcast_tx: BroadcastChannel,
    pub eventstore: Arc<EventStoreClient>,
}
