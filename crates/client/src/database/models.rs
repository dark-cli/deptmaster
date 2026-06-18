//! Data models for database storage.

/// Event stored in local database.
#[derive(Clone, Debug)]
pub struct StoredEvent {
    pub id: String,
    pub wallet_id: String,
    pub aggregate_type: String,
    pub aggregate_id: String,
    pub event_type: String,
    pub event_data: String,
    pub timestamp: String,
    pub version: i32,
    pub synced: bool,
}
