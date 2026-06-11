use serde::{Deserialize, Serialize};
use sqlx::{postgres::PgRow, FromRow, PgPool, Row};
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

// Snapshot rotation rules + defaults moved to the shared `snapshots`
// crate. Callers that used to reach for `DEFAULT_MAX_SNAPSHOTS` /
// `DEFAULT_SNAPSHOT_INTERVAL` / `save_snapshot[_with_limit]` /
// `should_create_snapshot[_with_interval]` now go through that crate
// directly, paired with `ServerSnapshotStore` as the storage adapter.

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
        "#,
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
        "#,
    )
    .bind(wallet_id)
    .fetch_optional(pool)
    .await?;

    Ok(snapshot)
}

/// Get event ID from events table by event_id UUID
#[allow(dead_code)] // Reserved for future event lookup functionality
pub async fn get_event_db_id(pool: &PgPool, event_id: Uuid) -> Result<Option<i64>, sqlx::Error> {
    let id = sqlx::query_scalar::<_, Option<i64>>("SELECT id FROM events WHERE event_id = $1")
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
        "#,
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
        "#,
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
        "#,
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

    Ok((
        serde_json::json!(contacts_json),
        serde_json::json!(transactions_json),
    ))
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
        "#,
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
        "#,
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
