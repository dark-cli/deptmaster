//! Shared projection-snapshot logic.
//!
//! Both server and SDK keep a per-wallet stack of projection snapshots
//! (the wallet's contacts + transactions as JSON at a given point in
//! the event log). Snapshots speed up UNDO rollback: instead of
//! replaying every event from the start, find the snapshot at-or-before
//! the undone event, restore it, then replay events forward.
//!
//! The two sides differ ONLY in storage engine (sqlx/Postgres vs
//! rusqlite/SQLite) and event-id representation (server uses BIGINT,
//! SDK uses UUID strings). Everything else — when to snapshot, how
//! many to keep, what data goes in — is identical and lives here.

use async_trait::async_trait;
use std::collections::HashSet;
use std::fmt::Debug;
use uuid::Uuid;

/// `true` if any event in the iterator is an UNDO. Lets each side keep
/// its own row/struct representation and pass just the typed event-type
/// iterator in.
pub fn batch_has_undo<I>(event_types: I) -> bool
where
    I: IntoIterator<Item = domain::EventType>,
{
    event_types.into_iter().any(|t| t.is_undo())
}

/// Collect `undone_event_id` values referenced by UNDO events in the
/// iterator. The caller passes `(event_type, event_data)` pairs (the
/// type is typed; the payload stays as raw JSON because the field name
/// is shared but the surrounding payload shape is wire-format).
pub fn collect_undone_event_ids<'a, I>(events: I) -> HashSet<String>
where
    I: IntoIterator<Item = (domain::EventType, &'a serde_json::Value)>,
{
    events
        .into_iter()
        .filter(|(t, _)| t.is_undo())
        .filter_map(|(_, data)| {
            data.get("undone_event_id")
                .and_then(|v| v.as_str())
                .map(String::from)
        })
        .collect()
}

/// Default ceiling on snapshots-per-wallet. Older snapshots are pruned
/// once this count is exceeded. Tuned for "long enough to roll back a
/// recent UNDO" without unbounded growth.
pub const DEFAULT_MAX_SNAPSHOTS: i64 = 5;

/// Default snapshot cadence: take a snapshot every N events. Higher
/// values trade replay cost (per UNDO) for storage cost.
pub const DEFAULT_SNAPSHOT_INTERVAL: i64 = 10;

/// One snapshot row, generic over the event-id type each side uses.
///
/// The contacts/transactions blobs are deliberately untyped JSON: each
/// side serializes its own projection rows into them; the shared crate
/// does not need to understand their shape.
#[derive(Debug, Clone)]
pub struct ProjectionSnapshot<EventId> {
    pub snapshot_index: i64,
    pub last_event_id: EventId,
    pub event_count: i64,
    pub contacts_snapshot: serde_json::Value,
    pub transactions_snapshot: serde_json::Value,
}

/// Per-side storage adapter for projection snapshots. Each method maps
/// to a single SQL statement on the implementing side; the rules around
/// these primitives ([`save_snapshot_with_limit`],
/// [`should_create_snapshot`]) are shared.
#[async_trait]
pub trait SnapshotStore {
    /// Engine-side error (e.g. `sqlx::Error`, `rusqlite::Error`).
    type Error: Debug;

    /// Type used to reference an event. Server uses `i64` (BIGSERIAL);
    /// SDK uses `String` (UUID). Equality + ordering live in each side's
    /// queries — this type is just transported through.
    type EventId: Clone + Debug + Send + Sync;

    /// `COALESCE(MAX(snapshot_index), -1) + 1 WHERE wallet_id = ?`.
    /// Returns the next available index for this wallet.
    async fn next_snapshot_index(&self, wallet_id: Uuid) -> Result<i64, Self::Error>;

    /// Insert one snapshot row.
    async fn save(
        &self,
        wallet_id: Uuid,
        snapshot_index: i64,
        last_event_id: Self::EventId,
        event_count: i64,
        contacts_snapshot: serde_json::Value,
        transactions_snapshot: serde_json::Value,
    ) -> Result<(), Self::Error>;

    /// `SELECT COUNT(*) WHERE wallet_id = ?`.
    async fn count(&self, wallet_id: Uuid) -> Result<i64, Self::Error>;

    /// Drop the `n` oldest snapshots (lowest snapshot_index) for a
    /// wallet. Caller has already verified n > 0.
    async fn delete_oldest_n(&self, wallet_id: Uuid, n: i64) -> Result<(), Self::Error>;

    /// Most recent snapshot in the wallet (highest snapshot_index).
    /// `None` if no snapshots exist yet.
    async fn get_latest(
        &self,
        wallet_id: Uuid,
    ) -> Result<Option<ProjectionSnapshot<Self::EventId>>, Self::Error>;

    /// Snapshot just before a given target event_count, i.e. the
    /// rollback target. Returns the highest snapshot whose
    /// `event_count < target_count`.
    async fn get_before_event_count(
        &self,
        wallet_id: Uuid,
        target_count: i64,
    ) -> Result<Option<ProjectionSnapshot<Self::EventId>>, Self::Error>;
}

/// Save a snapshot and prune older ones to stay under
/// [`DEFAULT_MAX_SNAPSHOTS`].
pub async fn save_snapshot<S: SnapshotStore + Sync>(
    store: &S,
    wallet_id: Uuid,
    last_event_id: S::EventId,
    event_count: i64,
    contacts_snapshot: serde_json::Value,
    transactions_snapshot: serde_json::Value,
) -> Result<(), S::Error> {
    save_snapshot_with_limit(
        store,
        wallet_id,
        last_event_id,
        event_count,
        contacts_snapshot,
        transactions_snapshot,
        DEFAULT_MAX_SNAPSHOTS,
    )
    .await
}

/// Same as [`save_snapshot`] but with a caller-chosen max-snapshots
/// limit. Used by tests and by the server when env-vars override the
/// default.
pub async fn save_snapshot_with_limit<S: SnapshotStore + Sync>(
    store: &S,
    wallet_id: Uuid,
    last_event_id: S::EventId,
    event_count: i64,
    contacts_snapshot: serde_json::Value,
    transactions_snapshot: serde_json::Value,
    max_snapshots: i64,
) -> Result<(), S::Error> {
    let next_index = store.next_snapshot_index(wallet_id).await?;
    store
        .save(
            wallet_id,
            next_index,
            last_event_id,
            event_count,
            contacts_snapshot,
            transactions_snapshot,
        )
        .await?;
    cleanup_old_snapshots_with_limit(store, wallet_id, max_snapshots).await?;
    Ok(())
}

/// Keep at most `max_snapshots` rows per wallet; drop the oldest.
pub async fn cleanup_old_snapshots_with_limit<S: SnapshotStore + Sync>(
    store: &S,
    wallet_id: Uuid,
    max_snapshots: i64,
) -> Result<(), S::Error> {
    let count = store.count(wallet_id).await?;
    if count <= max_snapshots {
        return Ok(());
    }
    let to_delete = count - max_snapshots;
    store.delete_oldest_n(wallet_id, to_delete).await
}

/// True every `DEFAULT_SNAPSHOT_INTERVAL` events. Cheap predicate
/// callers fire after each event apply.
pub fn should_create_snapshot(event_count: i64) -> bool {
    should_create_snapshot_with_interval(event_count, DEFAULT_SNAPSHOT_INTERVAL)
}

/// [`should_create_snapshot`] with a caller-chosen interval.
pub fn should_create_snapshot_with_interval(event_count: i64, snapshot_interval: i64) -> bool {
    snapshot_interval > 0 && event_count > 0 && event_count % snapshot_interval == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn should_create_snapshot_fires_at_interval_boundaries() {
        assert!(!should_create_snapshot_with_interval(0, 10));
        assert!(!should_create_snapshot_with_interval(1, 10));
        assert!(!should_create_snapshot_with_interval(9, 10));
        assert!(should_create_snapshot_with_interval(10, 10));
        assert!(should_create_snapshot_with_interval(20, 10));
        assert!(should_create_snapshot_with_interval(100, 10));
    }

    #[test]
    fn should_create_snapshot_zero_or_negative_interval_disables() {
        assert!(!should_create_snapshot_with_interval(10, 0));
        assert!(!should_create_snapshot_with_interval(10, -1));
    }

    use domain::EventType;

    #[test]
    fn batch_has_undo_detects_an_undo_anywhere_in_the_batch() {
        assert!(!batch_has_undo([EventType::Created, EventType::Updated]));
        assert!(batch_has_undo(
            [EventType::Created, EventType::Undo, EventType::Updated]
        ));
        assert!(batch_has_undo([EventType::Undo]));
        let empty: [EventType; 0] = [];
        assert!(!batch_has_undo(empty));
    }

    #[test]
    fn collect_undone_event_ids_only_picks_up_undo_rows() {
        let created = serde_json::json!({});
        let undo_a = serde_json::json!({ "undone_event_id": "abc" });
        let undo_b = serde_json::json!({ "undone_event_id": "def" });
        let undo_no_field = serde_json::json!({});
        let pairs = [
            (EventType::Created, &created),
            (EventType::Undo, &undo_a),
            (EventType::Updated, &created),
            (EventType::Undo, &undo_b),
            (EventType::Undo, &undo_no_field),
        ];
        let ids = collect_undone_event_ids(pairs.iter().map(|(t, d)| (*t, *d)));
        assert_eq!(ids.len(), 2);
        assert!(ids.contains("abc"));
        assert!(ids.contains("def"));
    }
}
