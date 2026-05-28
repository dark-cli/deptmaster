use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde_json::Value;
use sqlx::Row;
use sha2::{Sha256, Digest};
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_events_since_impl(
        &self,
        wallet_id: Uuid,
        since_timestamp: DateTime<Utc>,
    ) -> Result<Vec<EventRow>, DbError> {
        let rows = sqlx::query_as::<_, EventRow>(
            r#"
            SELECT id, event_id, aggregate_type, aggregate_id, event_type, data,
                   wallet_id, user_id, created_at, version, idempotency_key
            FROM events
            WHERE wallet_id = $1 AND created_at > $2
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .bind(since_timestamp)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows)
    }

    pub async fn get_event_by_id_impl(&self, event_id: Uuid) -> Result<Option<EventRow>, DbError> {
        let row = sqlx::query_as::<_, EventRow>(
            r#"
            SELECT id, event_id, aggregate_type, aggregate_id, event_type, data,
                   wallet_id, user_id, created_at, version, idempotency_key
            FROM events
            WHERE event_id = $1
            "#
        )
        .bind(event_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row)
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
        let result = sqlx::query_scalar::<_, i64>(
            r#"
            INSERT INTO events (event_id, aggregate_id, aggregate_type, event_type, data, wallet_id, user_id, version, idempotency_key, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
            ON CONFLICT (event_id) DO NOTHING
            RETURNING id
            "#
        )
        .bind(event_id)
        .bind(aggregate_id)
        .bind(&aggregate_type)
        .bind(&event_type)
        .bind(&data)
        .bind(wallet_id)
        .bind(user_id)
        .bind(version)
        .bind(&idempotency_key)
        .fetch_optional(&self.pool)
        .await?;

        Ok(result.unwrap_or(0))
    }

    pub async fn delete_event_impl(&self, event_id: Uuid) -> Result<bool, DbError> {
        let result = sqlx::query("DELETE FROM events WHERE event_id = $1")
            .bind(event_id)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn get_hash_for_sync_impl(&self, wallet_id: Uuid) -> Result<(String, i64), DbError> {
        let rows = sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, data, created_at
            FROM events
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        let mut hasher = Sha256::new();
        for row in &rows {
            let event_id: Uuid = row.get("event_id");
            let aggregate_type: String = row.get("aggregate_type");
            let aggregate_id: Uuid = row.get("aggregate_id");
            let event_type: String = row.get("event_type");
            let data: Value = row.get("data");

            hasher.update(event_id.to_string().as_bytes());
            hasher.update(aggregate_type.as_bytes());
            hasher.update(aggregate_id.to_string().as_bytes());
            hasher.update(event_type.as_bytes());
            hasher.update(data.to_string().as_bytes());
        }

        let hash = format!("{:x}", hasher.finalize());
        Ok((hash, rows.len() as i64))
    }
}
