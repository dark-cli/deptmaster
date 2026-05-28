use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde_json::Value;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_events_since_impl(
        &self,
        wallet_id: Uuid,
        since_timestamp: DateTime<Utc>,
    ) -> Result<Vec<EventRow>, DbError> {
        todo!("Extract from sync.rs GET /api/sync/events")
    }

    pub async fn get_event_by_id_impl(&self, event_id: Uuid) -> Result<Option<EventRow>, DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn insert_event_impl(
        &self,
        event_id: Uuid,
        aggregate_id: Uuid,
        aggregate_type: String,
        event_type: String,
        data: Value,
        wallet_id: Uuid,
        user_id: Uuid,
        version: i32,
        idempotency_key: Option<String>,
    ) -> Result<i64, DbError> {
        todo!("Extract from sync.rs POST /api/sync/events")
    }

    pub async fn delete_event_impl(&self, event_id: Uuid) -> Result<bool, DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn get_hash_for_sync_impl(&self, wallet_id: Uuid) -> Result<(String, i64), DbError> {
        todo!("Extract from sync.rs GET /api/sync/hash")
    }
}
