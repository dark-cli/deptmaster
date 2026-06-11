# Snapshot Tables Schema

**Main question this file answers:** How is snapshot data stored, and how does the same shape end up in two different databases?

---

## Where snapshots live

Both server and client keep a per-wallet stack of projection snapshots. Same logical shape, two storage engines.

| Side | Table | Engine |
|---|---|---|
| Server | `projection_snapshots` | Postgres (sqlx) |
| Client | `projection_snapshots` | SQLite (rusqlite) |

The shared `crates/core/snapshots` crate defines the rules (when to snapshot, rotation, UNDO-aware rebuild). Each side implements the `SnapshotStore` trait against its own table.

---

## Server schema (Postgres)

```sql
CREATE TABLE projection_snapshots (
    id BIGSERIAL PRIMARY KEY,
    wallet_id UUID NOT NULL,
    snapshot_index BIGINT NOT NULL,
    last_event_id BIGINT NOT NULL REFERENCES events(id),
    event_count BIGINT NOT NULL,
    contacts_snapshot JSONB NOT NULL,
    transactions_snapshot JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(wallet_id, snapshot_index)
);

CREATE INDEX idx_projection_snapshots_wallet_index
    ON projection_snapshots(wallet_id, snapshot_index DESC);
```

## Client schema (SQLite)

```sql
CREATE TABLE projection_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wallet_id TEXT NOT NULL,
    snapshot_index INTEGER NOT NULL,
    last_event_id TEXT NOT NULL,        -- ← only legitimate per-side diff
    event_count INTEGER NOT NULL,
    contacts_snapshot TEXT NOT NULL,    -- JSON as TEXT (SQLite has no JSONB)
    transactions_snapshot TEXT NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE(wallet_id, snapshot_index)
);
```

**Per-side differences and why:**
- `last_event_id` is `BIGINT` on server (refs `events.id` BIGSERIAL) vs `TEXT` on client (UUID string — client has no serial event id).
- `contacts_snapshot` / `transactions_snapshot` are `JSONB` vs `TEXT` (SQLite has no JSONB; JSON travels as a serialized string).

Everything else matches: same column names, same `UNIQUE(wallet_id, snapshot_index)` constraint, same per-wallet sequential indexing.

---

## What's in each snapshot

`contacts_snapshot` and `transactions_snapshot` are JSON arrays of the projection rows that were live (not soft-deleted) at the moment of the snapshot.

```json
// contacts_snapshot
[
  { "id": "abc-...", "name": "Alice", "username": null, "phone": null,
    "email": null, "notes": null, "created_at": "...", "updated_at": "..." },
  ...
]

// transactions_snapshot
[
  { "id": "def-...", "contact_id": "abc-...", "type": "money",
    "direction": "lent", "amount": 5000, "currency": "IQD",
    "transaction_date": "2026-06-12", "created_at": "...", "updated_at": "..." },
  ...
]
```

The shapes match the wire types in `crates/core/domain` (Contact / Transaction). Either side can deserialize the other's snapshot if needed.

---

## The `SnapshotStore` trait

Defined in `crates/core/snapshots/src/lib.rs`. Six methods, mapped to one SQL statement each:

| Method | What it does |
|---|---|
| `next_snapshot_index(wallet_id)` | `COALESCE(MAX(snapshot_index), -1) + 1` |
| `save(...)` | One INSERT |
| `count(wallet_id)` | `SELECT COUNT(*)` |
| `delete_oldest_n(wallet_id, n)` | DELETE the n smallest snapshot_indices |
| `get_latest(wallet_id)` | Highest snapshot_index |
| `get_before_event_count(wallet_id, target)` | Highest snapshot with `event_count < target` |

Two implementations:
- `crates/server/src/services/server_snapshot_store.rs` — `ServerSnapshotStore` over `&PgPool`
- `crates/client/src/sdk_snapshot_store.rs` — `SdkSnapshotStore` over the global SQLite connection

---

## Shared rules

These constants and predicates live in `crates/core/snapshots` and both sides import them:

```rust
pub const DEFAULT_MAX_SNAPSHOTS: i64 = 5;     // per wallet
pub const DEFAULT_SNAPSHOT_INTERVAL: i64 = 10; // every N events

pub fn should_create_snapshot(event_count: i64) -> bool;
pub fn should_create_snapshot_with_interval(event_count: i64, interval: i64) -> bool;

pub async fn save_snapshot<S: SnapshotStore + Sync>(...);
pub async fn save_snapshot_with_limit<S: SnapshotStore + Sync>(..., max: i64);
```

`save_snapshot` orchestrates: `next_snapshot_index` → `save` → `cleanup_old_snapshots_with_limit`. The trait + the rules together mean each side just has to handle SQL; the policy is shared.

---

## Reading the stack

The newest snapshot has the largest `snapshot_index` for its wallet. For UNDO rollback:

1. `get_before_event_count(wallet_id, undone_event_position)` finds the snapshot to restore.
2. Restore: deserialize `contacts_snapshot` + `transactions_snapshot`, bulk-insert into projection tables.
3. Replay events after the snapshot's `last_event_id`, skipping UNDO and undone events.

Step 2 (restore) is not yet shared between server and client — restoring from JSON into the projection tables is per-side. See [[../06-client/01-design-notes]] Decision 4 for status.
