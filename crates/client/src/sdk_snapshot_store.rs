//! SDK-side adapter for [`snapshots::SnapshotStore`].
//!
//! Wraps the SDK's process-wide rusqlite connection. The shared
//! `snapshots` crate holds the rotation rules + the
//! when-to-snapshot predicate; this impl only answers the
//! "talk to the SQLite table" questions.
//!
//! One legitimate diff from the server adapter:
//! `Self::EventId = String`. The SDK stores UUID event ids as
//! TEXT, not a BIGINT sequence — `last_event_id` therefore travels
//! as a string through the trait. Equality is exact-match; ordering
//! comes from `snapshot_index` + `event_count`, both i64, never
//! from the event id itself.

use async_trait::async_trait;
use rusqlite::params;
use snapshots::{ProjectionSnapshot, SnapshotStore};
use uuid::Uuid;

use crate::storage::with_db;

pub struct SdkSnapshotStore;

impl SdkSnapshotStore {
    pub fn new() -> Self {
        Self
    }
}

impl Default for SdkSnapshotStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl SnapshotStore for SdkSnapshotStore {
    type Error = String;
    type EventId = String;

    async fn next_snapshot_index(&self, wallet_id: Uuid) -> Result<i64, Self::Error> {
        let wid = wallet_id.to_string();
        with_db(|conn| {
            let n: i64 = conn.query_row(
                "SELECT COALESCE(MAX(snapshot_index), -1) + 1 FROM projection_snapshots WHERE wallet_id = ?1",
                params![wid],
                |r| r.get(0),
            )?;
            Ok(n)
        })
    }

    async fn save(
        &self,
        wallet_id: Uuid,
        snapshot_index: i64,
        last_event_id: String,
        event_count: i64,
        contacts_snapshot: serde_json::Value,
        transactions_snapshot: serde_json::Value,
    ) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        let now = chrono::Utc::now().to_rfc3339();
        let contacts = contacts_snapshot.to_string();
        let transactions = transactions_snapshot.to_string();
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT INTO projection_snapshots
                (wallet_id, snapshot_index, last_event_id, event_count,
                 contacts_snapshot, transactions_snapshot, created_at)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                "#,
                params![
                    wid,
                    snapshot_index,
                    last_event_id,
                    event_count,
                    contacts,
                    transactions,
                    now
                ],
            )?;
            Ok(())
        })
    }

    async fn count(&self, wallet_id: Uuid) -> Result<i64, Self::Error> {
        let wid = wallet_id.to_string();
        with_db(|conn| {
            let n: i64 = conn.query_row(
                "SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = ?1",
                params![wid],
                |r| r.get(0),
            )?;
            Ok(n)
        })
    }

    async fn delete_oldest_n(&self, wallet_id: Uuid, n: i64) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        with_db(|conn| {
            conn.execute(
                r#"
                DELETE FROM projection_snapshots
                 WHERE wallet_id = ?1
                   AND snapshot_index IN (
                     SELECT snapshot_index FROM projection_snapshots
                      WHERE wallet_id = ?1
                      ORDER BY snapshot_index ASC
                      LIMIT ?2
                   )
                "#,
                params![wid, n],
            )?;
            Ok(())
        })
    }

    async fn get_latest(
        &self,
        wallet_id: Uuid,
    ) -> Result<Option<ProjectionSnapshot<String>>, Self::Error> {
        let wid = wallet_id.to_string();
        with_db(|conn| {
            let mut stmt = conn.prepare(
                r#"
                SELECT snapshot_index, last_event_id, event_count,
                       contacts_snapshot, transactions_snapshot
                  FROM projection_snapshots
                 WHERE wallet_id = ?1
                 ORDER BY snapshot_index DESC
                 LIMIT 1
                "#,
            )?;
            let mut rows = stmt.query(params![wid])?;
            if let Some(row) = rows.next()? {
                let contacts_str: String = row.get(3)?;
                let transactions_str: String = row.get(4)?;
                Ok(Some(ProjectionSnapshot {
                    snapshot_index: row.get(0)?,
                    last_event_id: row.get(1)?,
                    event_count: row.get(2)?,
                    contacts_snapshot: serde_json::from_str(&contacts_str)
                        .unwrap_or(serde_json::Value::Null),
                    transactions_snapshot: serde_json::from_str(&transactions_str)
                        .unwrap_or(serde_json::Value::Null),
                }))
            } else {
                Ok(None)
            }
        })
    }

    async fn get_before_event_count(
        &self,
        wallet_id: Uuid,
        target_count: i64,
    ) -> Result<Option<ProjectionSnapshot<String>>, Self::Error> {
        let wid = wallet_id.to_string();
        with_db(|conn| {
            let mut stmt = conn.prepare(
                r#"
                SELECT snapshot_index, last_event_id, event_count,
                       contacts_snapshot, transactions_snapshot
                  FROM projection_snapshots
                 WHERE wallet_id = ?1 AND event_count < ?2
                 ORDER BY snapshot_index DESC
                 LIMIT 1
                "#,
            )?;
            let mut rows = stmt.query(params![wid, target_count])?;
            if let Some(row) = rows.next()? {
                let contacts_str: String = row.get(3)?;
                let transactions_str: String = row.get(4)?;
                Ok(Some(ProjectionSnapshot {
                    snapshot_index: row.get(0)?,
                    last_event_id: row.get(1)?,
                    event_count: row.get(2)?,
                    contacts_snapshot: serde_json::from_str(&contacts_str)
                        .unwrap_or(serde_json::Value::Null),
                    transactions_snapshot: serde_json::from_str(&transactions_str)
                        .unwrap_or(serde_json::Value::Null),
                }))
            } else {
                Ok(None)
            }
        })
    }
}
