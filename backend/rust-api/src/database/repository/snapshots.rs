use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde_json::Value;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn create_projection_snapshot_impl(
        &self,
        wallet_id: Uuid,
        contacts_data: Value,
        transactions_data: Value,
    ) -> Result<(), DbError> {
        todo!("Extract from sync.rs create_snapshot_json")
    }

    pub async fn get_latest_snapshot_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Option<(Value, Value, DateTime<Utc>)>, DbError> {
        todo!("Extract from sync.rs restore_projections_from_snapshot")
    }

    pub async fn delete_old_snapshots_impl(&self, wallet_id: Uuid, keep_count: i64) -> Result<(), DbError> {
        todo!("Extract from sync.rs or handlers")
    }
}

