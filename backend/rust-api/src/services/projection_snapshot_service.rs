use sqlx::{PgPool, Row, postgres::PgRow, FromRow};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectionSnapshot {
    pub id: i64,
    pub snapshot_index: i64,
    pub last_event_id: i64,
    pub event_count: i64,
    pub contacts_snapshot: serde_json::Value,
    pub transactions_snapshot: serde_json::Value,
    pub created_at: chrono::NaiveDateTime,
}

impl<'r> FromRow<'r, PgRow> for ProjectionSnapshot {
    fn from_row(row: &'r PgRow) -> Result<Self, sqlx::Error> {
        Ok(ProjectionSnapshot {
            id: row.try_get("id")?,
            snapshot_index: row.try_get("snapshot_index")?,
            last_event_id: row.try_get("last_event_id")?,
            event_count: row.try_get("event_count")?,
            contacts_snapshot: row.try_get("contacts_snapshot")?,
            transactions_snapshot: row.try_get("transactions_snapshot")?,
            created_at: row.try_get("created_at")?,
        })
    }
}

const MAX_SNAPSHOTS: i64 = 5;
const SNAPSHOT_INTERVAL: i64 = 10;

/// Save a projection snapshot
pub async fn save_snapshot(
    pool: &PgPool,
    last_event_id: i64,
    event_count: i64,
    contacts_snapshot: serde_json::Value,
    transactions_snapshot: serde_json::Value,
    wallet_id: uuid::Uuid,
) -> Result<(), sqlx::Error> {
    // Get next snapshot index for this wallet
    let next_index = sqlx::query_scalar::<_, Option<i64>>(
        "SELECT COALESCE(MAX(snapshot_index), -1) + 1 FROM projection_snapshots WHERE wallet_id = $1"
    )
    .bind(wallet_id)
    .fetch_one(pool)
    .await?;

    let next_index = next_index.unwrap_or(0);

    // Insert snapshot
    sqlx::query(
        r#"
        INSERT INTO projection_snapshots 
        (snapshot_index, last_event_id, event_count, contacts_snapshot, transactions_snapshot, wallet_id)
        VALUES ($1, $2, $3, $4, $5, $6)
        "#
    )
    .bind(next_index)
    .bind(last_event_id)
    .bind(event_count)
    .bind(contacts_snapshot)
    .bind(transactions_snapshot)
    .bind(wallet_id)
    .execute(pool)
    .await?;

    tracing::info!("Saved projection snapshot #{} (event count: {})", next_index, event_count);

    // Cleanup old snapshots for this wallet
    cleanup_old_snapshots(pool, wallet_id).await?;

    Ok(())
}

/// Get snapshot before a specific event ID
/// Returns the most recent snapshot where last_event_id < event_id
pub async fn get_snapshot_before_event(
    pool: &PgPool,
    event_id: i64,
    wallet_id: uuid::Uuid,
) -> Result<Option<ProjectionSnapshot>, sqlx::Error> {
    let snapshot = sqlx::query_as::<_, ProjectionSnapshot>(
        r#"
        SELECT id, snapshot_index, last_event_id, event_count, 
               contacts_snapshot, transactions_snapshot, created_at
        FROM projection_snapshots
        WHERE last_event_id < $1 AND wallet_id = $2
        ORDER BY snapshot_index DESC
        LIMIT 1
        "#
    )
    .bind(event_id)
    .bind(wallet_id)
    .fetch_optional(pool)
    .await?;

    Ok(snapshot)
}

/// Get the latest snapshot for a wallet
#[allow(dead_code)] // Reserved for future snapshot functionality
pub async fn get_latest_snapshot(
    pool: &PgPool,
    wallet_id: uuid::Uuid,
) -> Result<Option<ProjectionSnapshot>, sqlx::Error> {
    let snapshot = sqlx::query_as::<_, ProjectionSnapshot>(
        r#"
        SELECT id, snapshot_index, last_event_id, event_count,
               contacts_snapshot, transactions_snapshot, created_at
        FROM projection_snapshots
        WHERE wallet_id = $1
        ORDER BY snapshot_index DESC
        LIMIT 1
        "#
    )
    .bind(wallet_id)
    .fetch_optional(pool)
    .await?;

    Ok(snapshot)
}

/// Cleanup old snapshots, keeping only the last MAX_SNAPSHOTS for a wallet
pub async fn cleanup_old_snapshots(pool: &PgPool, wallet_id: uuid::Uuid) -> Result<(), sqlx::Error> {
    // Get count of snapshots for this wallet
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(pool)
        .await?;

    if count <= MAX_SNAPSHOTS {
        return Ok(());
    }

    // Delete oldest snapshots, keeping only the last MAX_SNAPSHOTS for this wallet
    let to_delete = count - MAX_SNAPSHOTS;
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
        "#
    )
    .bind(wallet_id)
    .bind(to_delete)
    .execute(pool)
    .await?;

    tracing::info!("Cleaned up {} old snapshots, kept {}", to_delete, MAX_SNAPSHOTS);

    Ok(())
}

/// Check if we should create a snapshot based on event count
pub fn should_create_snapshot(event_count: i64) -> bool {
    event_count % SNAPSHOT_INTERVAL == 0
}

/// Get event ID from events table by event_id UUID
#[allow(dead_code)] // Reserved for future event lookup functionality
pub async fn get_event_db_id(
    pool: &PgPool,
    event_id: Uuid,
) -> Result<Option<i64>, sqlx::Error> {
    let id = sqlx::query_scalar::<_, Option<i64>>(
        "SELECT id FROM events WHERE event_id = $1"
    )
    .bind(event_id)
    .fetch_optional(pool)
    .await?;

    Ok(id.flatten())
}

/// Get snapshot with event_count less than target_count
/// Returns the most recent snapshot where event_count < target_count
pub async fn get_snapshot_before_event_count(
    pool: &PgPool,
    target_count: i64,
    wallet_id: uuid::Uuid,
) -> Result<Option<ProjectionSnapshot>, sqlx::Error> {
    let snapshot = sqlx::query_as::<_, ProjectionSnapshot>(
        r#"
        SELECT id, snapshot_index, last_event_id, event_count, 
               contacts_snapshot, transactions_snapshot, created_at
        FROM projection_snapshots
        WHERE event_count < $1 AND wallet_id = $2
        ORDER BY snapshot_index DESC
        LIMIT 1
        "#
    )
    .bind(target_count)
    .bind(wallet_id)
    .fetch_optional(pool)
    .await?;

    Ok(snapshot)
}
