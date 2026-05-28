use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde_json::Value;
use sqlx::Row;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn create_projection_snapshot_impl(
        &self,
        wallet_id: Uuid,
        contacts_data: Value,
        transactions_data: Value,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO projection_snapshots (wallet_id, contacts_data, transactions_data, created_at)
            VALUES ($1, $2, $3, NOW())
            "#
        )
        .bind(wallet_id)
        .bind(&contacts_data)
        .bind(&transactions_data)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_latest_snapshot_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Option<(Value, Value, DateTime<Utc>)>, DbError> {
        let row = sqlx::query(
            r#"
            SELECT contacts_data, transactions_data, created_at
            FROM projection_snapshots
            WHERE wallet_id = $1
            ORDER BY created_at DESC
            LIMIT 1
            "#
        )
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|r| {
            let contacts: Value = r.get("contacts_data");
            let transactions: Value = r.get("transactions_data");
            let created_at: chrono::NaiveDateTime = r.get("created_at");
            let dt = DateTime::<Utc>::from_naive_utc_and_offset(created_at, Utc);
            (contacts, transactions, dt)
        }))
    }

    pub async fn delete_old_snapshots_impl(&self, wallet_id: Uuid, keep_count: i64) -> Result<(), DbError> {
        sqlx::query(
            r#"
            DELETE FROM projection_snapshots
            WHERE wallet_id = $1
              AND created_at < (
                SELECT created_at
                FROM projection_snapshots
                WHERE wallet_id = $1
                ORDER BY created_at DESC
                LIMIT 1 OFFSET $2
              )
            "#
        )
        .bind(wallet_id)
        .bind(keep_count)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}

