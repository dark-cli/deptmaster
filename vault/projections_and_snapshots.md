# Projections and Snapshots Architecture

## Overview

This document explains the **Event Sourcing** pattern with **Snapshot Optimization** used in the debt tracker application for efficient projection rebuilding.

### Core Concepts

**Event Sourcing**: Store complete history of state changes (events) instead of current state
- Events table: Immutable log of what happened
- Projections: Materialized view of current state (rebuilt from events)
- Snapshots: Periodic checkpoints to avoid replaying all events

**Projections**: Denormalized copies of entity state for fast queries
- `contacts_projection`: Current contact information
- `transactions_projection`: Current transaction information
- Both have `last_event_id` to track which events have been applied

---

## Event Application Flow

### Two Entry Points

Both paths ultimately use the same core logic:

```
┌──────────────────────────┐
│  New Event Arrives       │
│  (HTTP POST /sync)       │
└────────────┬─────────────┘
             │
             ├─→ Insert into events table
             │
             ├─→ apply_event_to_projections()
             │   ├─ Fetch event from database
             │   └─ Apply to projections
             │
             ├─→ Save snapshot (if needed)
             │
             └─→ Broadcast update


┌──────────────────────────┐
│  Rebuild Projections     │
│  (UNDO or manual)        │
└────────────┬─────────────┘
             │
             ├─→ Check if snapshots exist
             │
             ├─→ Load new events since last_event_id
             │   (Phase 1 optimization)
             │
             ├─→ Restore from snapshot + apply new events
             │   OR
             │   Full rebuild with batch processing
             │   (Phase 2 optimization - planned)
             │
             └─→ Update projections
```

### Single Source of Truth: `apply_events_to_projections_impl()`

All event application (sync or rebuild) delegates to one function:

```rust
pub async fn apply_events_to_projections_impl(
    &self,
    events: &[&sqlx::postgres::PgRow],  // Row(s) from events table
    user_id: Uuid,
    wallet_id: Uuid,
    undone_event_ids: &mut HashSet<Uuid>,
) -> Result<(), sqlx::Error>
```

This ensures:
- ✅ Same logic for sync and rebuild
- ✅ Single place to fix bugs
- ✅ Consistent behavior everywhere
- ✅ Automatic last_event_id tracking

---

## Snapshot Optimization Algorithm

### When Snapshots Help

**Without snapshots** (1M events):
- Load all 1M events into memory: ~1GB RAM
- Replay all 1M events: slow, expensive
- Memory cost grows with wallet size

**With snapshots** (1M events, snapshot at event 100K):
- Load snapshot (compact JSON): ~10KB
- Load only 900K new events: ~900MB RAM
- Replay 900K events: much faster

### The 5-Step Algorithm

```
1. Load events (with Phase 1 optimization)
   └─ Only load events after last_event_id (skip already-applied)

2. Build event position map
   └─ event_uuid → position (for UNDO lookup)

3. Check for UNDO events
   ├─ If UNDO exists: find earliest undone event position
   └─ If no UNDO: use most recent event

4. Search for snapshot before target position
   └─ Only use snapshots that happened before any undone events

5. Apply events
   ├─ Restore from snapshot (if found)
   └─ Apply only new events after snapshot
      OR
      Full rebuild (if no snapshot)
```

### Critical Detail: UNDO Handling

UNDO events are special - they don't update state, they mark other events as "deleted":

```
Event 1:  CREATE Contact "Alice"
Event 2:  UPDATE Contact "Alice Smith"
Event 3:  UPDATE Contact phone "555-1234"
Event 4:  UNDO Event 2  ← This deletes the UPDATE from Event 2

Result: Contact has Event 1 + Event 3, Event 2 is ignored
```

**Why snapshots must come before UNDO**:
- Snapshot at Event 3 might contain "Alice Smith" (from Event 2)
- But Event 4 undoes Event 2
- So snapshot at Event 3 contains wrong state!
- Must find snapshot BEFORE Event 2 instead

---

## Phase 1 Optimization: last_event_id Tracking

### The Problem

Each projection row has a `last_event_id` field tracking which event was last applied:

```sql
contacts_projection:
  id (contact uuid) | name | phone | ... | last_event_id
  ─────────────────┬──────┬───────┬─────┬───────────────
  contact-123      | Alice| ...   | ...  | 1000  ← Event 1000 was applied
```

### How It Works

**During sync** (apply_event_to_projections):
1. New event inserted (db id = 1001)
2. Event applied to projection
3. Projection updated with `last_event_id = 1001`

**During rebuild** (apply_events_to_projections_impl):
1. Query `MAX(last_event_id)` from projections = 1000
2. Load only events WHERE id > 1000
3. Skip events 1-1000 (already in projections)

### Memory Impact

```
Without Phase 1:  Load ALL 1M events  → ~1GB RAM
With Phase 1:     Load only 100 new   → ~10KB RAM

Improvement: 100,000x reduction
```

### Code Integration

```rust
// In rebuild_projections_from_events()
let max_processed_id = sqlx::query_scalar(
    "SELECT MAX(last_event_id) FROM (
        SELECT COALESCE(MAX(last_event_id), 0) FROM contacts_projection
        UNION ALL
        SELECT COALESCE(MAX(last_event_id), 0) FROM transactions_projection
    ) t"
)
.fetch_optional(&pool)
.await?
.flatten();

// Load only new events
let events = sqlx::query(
    "SELECT ... FROM events 
     WHERE wallet_id = $1 AND id > COALESCE($2, 0)"
)
.bind(wallet_id)
.bind(max_processed_id.unwrap_or(0))
.fetch_all(&pool)
.await?;

// Early return if nothing new
if events.is_empty() && has_existing_projections {
    return Ok(());  // Already up to date!
}
```

---

## Phase 2 Optimization: Batch Processing (Planned)

For full rebuilds (when no prior projections exist), avoid loading all events at once:

```rust
const BATCH_SIZE: usize = 1000;  // Configurable via environment

let mut offset = 0;
loop {
    // Load one batch at a time
    let batch = sqlx::query(
        "SELECT ... FROM events 
         WHERE wallet_id = $1 AND id > $2
         ORDER BY created_at ASC
         LIMIT $3 OFFSET $4"
    )
    .bind(wallet_id)
    .bind(max_processed_id.unwrap_or(0))
    .bind(BATCH_SIZE)
    .bind(offset)
    .fetch_all(&pool)
    .await?;
    
    if batch.is_empty() { break; }
    
    // Process batch
    apply_events_to_projections_impl(&batch, ...)?;
    
    offset += batch.len();
}
```

**Benefits**:
- Memory bounded at ~5-10MB regardless of wallet size
- Works seamlessly with snapshot optimization
- No changes to event application logic

---

## Event Application: Consistent Behavior

### apply_event_to_projections()

Entry point for single event (sync path):

```rust
pub async fn apply_event_to_projections(
    &self,
    event_uuid: Uuid,
    user_id: Uuid,
    wallet_id: Uuid,
) -> Result<(), sqlx::Error> {
    // Fetch event from database
    let event_row = sqlx::query(
        "SELECT event_id, aggregate_type, aggregate_id, 
                event_type, event_data, created_at, id
         FROM events WHERE event_id = $1 AND wallet_id = $2"
    )
    .bind(event_uuid)
    .bind(wallet_id)
    .fetch_optional(&pool)
    .await?;

    if let Some(row) = event_row {
        // Delegate to core logic
        apply_events_to_projections_impl(&[&row], user_id, wallet_id, ...)?;
    }

    Ok(())
}
```

### apply_events_to_projections_impl()

Core logic (both sync and rebuild use this):

```rust
pub async fn apply_events_to_projections_impl(
    &self,
    events: &[&sqlx::postgres::PgRow],
    user_id: Uuid,
    wallet_id: Uuid,
    undone_event_ids: &mut HashSet<Uuid>,
) -> Result<(), sqlx::Error> {
    // 1. Collect UNDO events
    // 2. For each event:
    //    - Skip if UNDO or undone
    //    - INSERT or UPDATE projection
    //    - Set last_event_id = current event's db id
    // 3. Return Ok
}
```

**Key insight**: Whether applying 1 event or 1M events, the same code runs, same last_event_id tracking happens.

---

## Database Schema

### Events Table
```sql
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,           -- Auto-increment for ordering
    event_id UUID UNIQUE NOT NULL,      -- Client-provided UUID for idempotency
    wallet_id UUID NOT NULL,            -- Scoped to wallet
    user_id UUID NOT NULL,              -- User who created event
    aggregate_type VARCHAR(50),         -- "contact", "transaction", "permission"
    aggregate_id UUID NOT NULL,         -- Contact/transaction ID
    event_type VARCHAR(50),             -- "CREATED", "UPDATED", "DELETED", "UNDO"
    event_data JSONB,                   -- Event payload
    created_at TIMESTAMP,               -- When event occurred
    ...
);
```

### Projection Tables
```sql
CREATE TABLE contacts_projection (
    id UUID PRIMARY KEY,                -- Contact ID
    wallet_id UUID NOT NULL,            -- Scoped to wallet
    user_id UUID NOT NULL,              -- Owner
    name VARCHAR(255),
    phone VARCHAR(20),
    email VARCHAR(255),
    ...
    last_event_id BIGINT,               -- DB ID of last applied event
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    ...
);

CREATE TABLE transactions_projection (
    id UUID PRIMARY KEY,                -- Transaction ID
    wallet_id UUID NOT NULL,
    contact_id UUID NOT NULL,
    amount BIGINT,
    direction VARCHAR(10),              -- "lent" or "owed"
    ...
    last_event_id BIGINT,               -- DB ID of last applied event
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    ...
);
```

### Snapshots Table
```sql
CREATE TABLE projection_snapshots (
    id BIGSERIAL PRIMARY KEY,
    wallet_id UUID NOT NULL,
    event_id BIGINT NOT NULL,           -- DB ID of last event in snapshot
    snapshot_index INT,                 -- Creation order (for retention)
    event_count BIGINT,                 -- For metrics
    contacts_snapshot JSONB,            -- Serialized contacts_projection rows
    transactions_snapshot JSONB,        -- Serialized transactions_projection rows
    created_at TIMESTAMP,
    ...
);
```

---

## Performance Characteristics

### Query Speed
```
Without snapshots:  Load 1M events → ~500-1000ms
With snapshots:     Load 100K from snapshot → ~5-50ms
Improvement:        10-100x faster
```

### Memory Usage
```
Without Phase 1:    Load 1M events → ~1GB RAM
With Phase 1:       Load 100 new  → ~10KB RAM
Improvement:        100,000x better
```

### Rebuild Time
```
Without snapshot:      Replay 1M events → 5-10 seconds
With snapshot:         Restore + replay 100K → 0.1-0.5 seconds
Improvement:           50-100x faster
```

---

## Common Patterns

### Checking if Rebuild Is Needed

```rust
// After UNDO event
if event.event_type == "UNDO" {
    // UNDO events need full rebuild to handle undone state correctly
    rebuild_projections_from_events(&state, wallet_id).await?;
}
```

### Creating Snapshots

```rust
// After syncing events
let event_count = db.get_event_count_for_wallet(wallet_id).await;
if should_create_snapshot(event_count) {
    let snapshot_json = snapshots::create_snapshot_json(&pool, wallet_id).await?;
    snapshots::save_snapshot(
        &pool,
        event_db_id,
        event_count,
        snapshot_json.contacts,
        snapshot_json.transactions,
        wallet_id,
    ).await?;
}
```

---

## Testing the System

### Unit Tests
- `snapshot_optimization_test.rs`: Verify snapshot creation, restoration, and optimization
- Test UNDO event handling
- Test full rebuild fallback

### Key Test Scenarios
1. ✅ Events applied successfully
2. ✅ Snapshots created at correct intervals
3. ✅ Snapshot optimization reduces event loading
4. ✅ UNDO events handled correctly
5. ✅ Full rebuild triggered when needed
6. ✅ last_event_id tracking prevents reprocessing

---

## Future Improvements

### Phase 2: Batch Processing
- Load events in configurable batches (1000 events default)
- Bounded memory regardless of wallet size
- Enabled via `EVENT_REBUILD_BATCH_SIZE` environment variable

### Phase 3: Event Streaming
- Real-time updates via Kafka/WebSocket
- Clients notified immediately when events sync
- Currently: polling-based

### Phase 4: Advanced Optimizations
- Event deduplication via idempotency keys
- Event compression for archived events
- Event archival to cold storage (S3)
- CQRS complete separation
- Read model multiplexing (different views of data)
