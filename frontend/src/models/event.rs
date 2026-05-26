use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Event {
    pub id: String,
    pub aggregate_type: String,
    pub aggregate_id: String,
    pub event_type: String,
    pub event_data: HashMap<String, serde_json::Value>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub version: i32,
    pub synced: bool,
}
