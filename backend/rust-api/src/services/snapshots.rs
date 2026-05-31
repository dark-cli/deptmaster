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

/// Lightweight snapshot metadata (no JSON data)
#[derive(Debug, Clone, FromRow)]
pub struct SnapshotMetadata {
    pub id: i64,
    pub snapshot_index: i64,
    pub last_event_id: i64,
    pub event_count: i64,
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

/// Snapshot configuration - defaults, can be overridden by MAX_SNAPSHOTS_PER_WALLET and SNAPSHOT_INTERVAL env vars
pub const DEFAULT_MAX_SNAPSHOTS: i64 = 5;
pub const DEFAULT_SNAPSHOT_INTERVAL: i64 = 10;

/// Save a projection snapshot (uses default max snapshots)
pub async fn save_snapshot(
    pool: &PgPool,
    last_event_id: i64,
    event_count: i64,
    contacts_snapshot: serde_json::Value,
    transactions_snapshot: serde_json::Value,
    wallet_id: uuid::Uuid,
) -> Result<(), sqlx::Error> {
    save_snapshot_with_limit(
        pool,
        last_event_id,
        event_count,
        contacts_snapshot,
        transactions_snapshot,
        wallet_id,
        DEFAULT_MAX_SNAPSHOTS,
    )
    .await
}

/// Save a projection snapshot with custom max snapshots limit
pub async fn save_snapshot_with_limit(
    pool: &PgPool,
    last_event_id: i64,
    event_count: i64,
    contacts_snapshot: serde_json::Value,
    transactions_snapshot: serde_json::Value,
    wallet_id: uuid::Uuid,
    max_snapshots: i64,
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
    cleanup_old_snapshots_with_limit(pool, wallet_id, max_snapshots).await?;

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

/// Cleanup old snapshots, keeping only the last max_snapshots for a wallet
pub async fn cleanup_old_snapshots(pool: &PgPool, wallet_id: uuid::Uuid) -> Result<(), sqlx::Error> {
    cleanup_old_snapshots_with_limit(pool, wallet_id, DEFAULT_MAX_SNAPSHOTS).await
}

/// Cleanup old snapshots with custom max_snapshots limit
pub async fn cleanup_old_snapshots_with_limit(
    pool: &PgPool,
    wallet_id: uuid::Uuid,
    max_snapshots: i64,
) -> Result<(), sqlx::Error> {
    // Get count of snapshots for this wallet
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM projection_snapshots WHERE wallet_id = $1")
        .bind(wallet_id)
        .fetch_one(pool)
        .await?;

    if count <= max_snapshots {
        return Ok(());
    }

    // Delete oldest snapshots, keeping only the last max_snapshots for this wallet
    let to_delete = count - max_snapshots;
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

    tracing::info!("Cleaned up {} old snapshots, kept {}", to_delete, max_snapshots);

    Ok(())
}

/// Check if we should create a snapshot based on event count (uses default interval)
pub fn should_create_snapshot(event_count: i64) -> bool {
    should_create_snapshot_with_interval(event_count, DEFAULT_SNAPSHOT_INTERVAL)
}

/// Check if we should create a snapshot based on event count with custom interval
pub fn should_create_snapshot_with_interval(event_count: i64, snapshot_interval: i64) -> bool {
    event_count % snapshot_interval == 0
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

/// Create snapshot JSON from current projections for a wallet
pub async fn create_snapshot_json(
    pool: &PgPool,
    wallet_id: uuid::Uuid,
) -> Result<(serde_json::Value, serde_json::Value), sqlx::Error> {
    // Get all contacts for this wallet
    let contacts = sqlx::query(
        r#"
        SELECT id, user_id, name, username, phone, email, notes, is_deleted, created_at, updated_at
        FROM contacts_projection
        WHERE wallet_id = $1 AND is_deleted = false
        ORDER BY created_at
        "#
    )
    .bind(wallet_id)
    .fetch_all(pool)
    .await?;

    let contacts_json: Vec<serde_json::Value> = contacts
        .iter()
        .map(|row| {
            serde_json::json!({
                "id": row.get::<uuid::Uuid, _>("id").to_string(),
                "name": row.get::<String, _>("name"),
                "username": row.get::<Option<String>, _>("username"),
                "phone": row.get::<Option<String>, _>("phone"),
                "email": row.get::<Option<String>, _>("email"),
                "notes": row.get::<Option<String>, _>("notes"),
                "created_at": row.get::<chrono::NaiveDateTime, _>("created_at").to_string(),
                "updated_at": row.get::<chrono::NaiveDateTime, _>("updated_at").to_string(),
            })
        })
        .collect();

    // Get all transactions for this wallet
    let transactions = sqlx::query(
        r#"
        SELECT id, user_id, contact_id, type, direction, amount, currency, description,
               transaction_date, due_date, is_deleted, created_at, updated_at
        FROM transactions_projection
        WHERE wallet_id = $1 AND is_deleted = false
        ORDER BY created_at
        "#
    )
    .bind(wallet_id)
    .fetch_all(pool)
    .await?;

    let transactions_json: Vec<serde_json::Value> = transactions
        .iter()
        .map(|row| {
            serde_json::json!({
                "id": row.get::<uuid::Uuid, _>("id").to_string(),
                "contact_id": row.get::<uuid::Uuid, _>("contact_id").to_string(),
                "type": row.get::<String, _>("type"),
                "direction": row.get::<String, _>("direction"),
                "amount": row.get::<i64, _>("amount"),
                "currency": row.get::<Option<String>, _>("currency"),
                "description": row.get::<Option<String>, _>("description"),
                "transaction_date": row.get::<chrono::NaiveDate, _>("transaction_date").to_string(),
                "due_date": row.get::<Option<chrono::NaiveDate>, _>("due_date")
                    .map(|d| d.to_string()),
                "created_at": row.get::<chrono::NaiveDateTime, _>("created_at").to_string(),
                "updated_at": row.get::<chrono::NaiveDateTime, _>("updated_at").to_string(),
            })
        })
        .collect();

    Ok((serde_json::json!(contacts_json), serde_json::json!(transactions_json)))
}

/// Get snapshot metadata only (lightweight, no JSON data)
/// Returns snapshots ordered by snapshot_index DESC (newest first)
pub async fn get_snapshot_metadata_for_wallet(
    pool: &PgPool,
    wallet_id: uuid::Uuid,
) -> Result<Vec<SnapshotMetadata>, sqlx::Error> {
    let snapshots = sqlx::query_as::<_, SnapshotMetadata>(
        r#"
        SELECT id, snapshot_index, last_event_id, event_count, created_at
        FROM projection_snapshots
        WHERE wallet_id = $1
        ORDER BY snapshot_index DESC
        "#
    )
    .bind(wallet_id)
    .fetch_all(pool)
    .await?;

    Ok(snapshots)
}

/// Get full snapshot by ID (loads JSON data)
pub async fn get_snapshot_by_id(
    pool: &PgPool,
    snapshot_id: i64,
) -> Result<Option<ProjectionSnapshot>, sqlx::Error> {
    let snapshot = sqlx::query_as::<_, ProjectionSnapshot>(
        r#"
        SELECT id, snapshot_index, last_event_id, event_count,
               contacts_snapshot, transactions_snapshot, created_at
        FROM projection_snapshots
        WHERE id = $1
        "#
    )
    .bind(snapshot_id)
    .fetch_optional(pool)
    .await?;

    Ok(snapshot)
}

/// Create an empty initial snapshot for a wallet (event_count=0, last_event_id=0)
/// This ensures all events are guaranteed to be newer than at least one snapshot
pub async fn create_initial_empty_snapshot(
    pool: &PgPool,
    wallet_id: uuid::Uuid,
) -> Result<(), sqlx::Error> {
    let empty_contacts = serde_json::json!([]);
    let empty_transactions = serde_json::json!([]);

    sqlx::query(
        r#"
        INSERT INTO projection_snapshots
        (snapshot_index, last_event_id, event_count, contacts_snapshot, transactions_snapshot, wallet_id)
        VALUES (0, 0, 0, $1, $2, $3)
        ON CONFLICT DO NOTHING
        "#
    )
    .bind(empty_contacts)
    .bind(empty_transactions)
    .bind(wallet_id)
    .execute(pool)
    .await?;

    tracing::info!("Created initial empty snapshot for wallet {}", wallet_id);
    Ok(())
}
