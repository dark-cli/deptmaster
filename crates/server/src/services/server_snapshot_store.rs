//! Server-side adapter for [`snapshots::SnapshotStore`].
//!
//! Wraps `&PgPool`; each trait method is one sqlx query against
//! `projection_snapshots`. The rules around these primitives —
//! when to snapshot, how many to keep — live in the shared `snapshots`
//! crate; this impl only answers the low-level CRUD questions.

use async_trait::async_trait;
use snapshots::{ProjectionSnapshot, SnapshotStore};
use sqlx::PgPool;
use uuid::Uuid;

pub struct ServerSnapshotStore<'a> {
    pub pool: &'a PgPool,
}

impl<'a> ServerSnapshotStore<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl<'a> SnapshotStore for ServerSnapshotStore<'a> {
    type Error = sqlx::Error;
    type EventId = i64;

    async fn next_snapshot_index(&self, wallet_id: Uuid) -> Result<i64, Self::Error> {
        let next_index = sqlx::query_scalar::<_, Option<i64>>(
            "SELECT COALESCE(MAX(snapshot_index), -1) + 1 FROM projection_snapshots WHERE wallet_id = $1",
        )
        .bind(wallet_id)
        .fetch_one(self.pool)
        .await?;
        Ok(next_index.unwrap_or(0))
    }

    async fn save(
        &self,
        wallet_id: Uuid,
        snapshot_index: i64,
        last_event_id: i64,
        event_count: i64,
        contacts_snapshot: serde_json::Value,
        transactions_snapshot: serde_json::Value,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            r#"
            INSERT INTO projection_snapshots
            (snapshot_index, last_event_id, event_count, contacts_snapshot, transactions_snapshot, wallet_id)
            VALUES ($1, $2, $3, $4, $5, $6)
            "#,
        )
        .bind(snapshot_index)
        .bind(last_event_id)
        .bind(event_count)
        .bind(contacts_snapshot)
        .bind(transactions_snapshot)
        .bind(wallet_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn count(&self, wallet_id: Uuid) -> Result<i64, Self::Error> {
        let count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
                .bind(wallet_id)
                .fetch_one(self.pool)
                .await?;
        Ok(count)
    }

    async fn delete_oldest_n(&self, wallet_id: Uuid, n: i64) -> Result<(), Self::Error> {
        sqlx::query(
            r#"
            DELETE FROM projection_snapshots
            WHERE wallet_id = $1 AND snapshot_index IN (
                SELECT snapshot_index
                FROM projection_snapshots
                WHERE wallet_id = $1
                ORDER BY snapshot_index ASC
                LIMIT $2
            )
            "#,
        )
        .bind(wallet_id)
        .bind(n)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn get_latest(
        &self,
        wallet_id: Uuid,
    ) -> Result<Option<ProjectionSnapshot<i64>>, Self::Error> {
        let row = sqlx::query_as::<_, (i64, i64, i64, serde_json::Value, serde_json::Value)>(
            r#"
            SELECT snapshot_index, last_event_id, event_count,
                   contacts_snapshot, transactions_snapshot
              FROM projection_snapshots
             WHERE wallet_id = $1
             ORDER BY snapshot_index DESC
             LIMIT 1
            "#,
        )
        .bind(wallet_id)
        .fetch_optional(self.pool)
        .await?;
        Ok(row.map(|(i, eid, c, cs, ts)| ProjectionSnapshot {
            snapshot_index: i,
            last_event_id: eid,
            event_count: c,
            contacts_snapshot: cs,
            transactions_snapshot: ts,
        }))
    }

    async fn get_before_event_count(
        &self,
        wallet_id: Uuid,
        target_count: i64,
    ) -> Result<Option<ProjectionSnapshot<i64>>, Self::Error> {
        let row = sqlx::query_as::<_, (i64, i64, i64, serde_json::Value, serde_json::Value)>(
            r#"
            SELECT snapshot_index, last_event_id, event_count,
                   contacts_snapshot, transactions_snapshot
              FROM projection_snapshots
             WHERE event_count < $1 AND wallet_id = $2
             ORDER BY snapshot_index DESC
             LIMIT 1
            "#,
        )
        .bind(target_count)
        .bind(wallet_id)
        .fetch_optional(self.pool)
        .await?;
        Ok(row.map(|(i, eid, c, cs, ts)| ProjectionSnapshot {
            snapshot_index: i,
            last_event_id: eid,
            event_count: c,
            contacts_snapshot: cs,
            transactions_snapshot: ts,
        }))
    }
}
