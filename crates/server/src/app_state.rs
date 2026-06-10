use std::sync::Arc;
use crate::config::Config;
use crate::database::DatabasePool;
use crate::websocket::BroadcastChannel;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DatabasePool,
    pub config: Arc<Config>,
    pub broadcast_tx: BroadcastChannel,
}
