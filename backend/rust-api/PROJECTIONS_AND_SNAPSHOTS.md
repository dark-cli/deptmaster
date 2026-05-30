# Projections and Snapshots: Deep Dive

## Overview

This document explains how the Projections and Snapshots system works in the debt tracker application. It's an implementation of **event sourcing** with **snapshot optimization** to handle large event histories efficiently.

### Event Sourcing Pattern

Instead of storing the current state of entities (contacts, transactions), we store a complete history of events that happened to them:

```
Events Table:
ID  Type      Data                  Created
1   CREATED   name: "Alice"        2024-01-01
2   UPDATED   name: "Alice Smith"  2024-01-02
3   UPDATED   phone: "555-1234"    2024-01-03
...

Projection (Current State):
ID        name          phone
alice-id  Alice Smith   555-1234
```

The **projection** is the materialized view of the current state, rebuilt by replaying all events in order.

### Why Snapshots?

As the events table grows, rebuilding projections from scratch becomes expensive:
- 1,000 events = quick to rebuild
- 1,000,000 events = slow, expensive database queries

**Snapshots** are periodic checkpoints of the projection state, allowing us to:
1. Restore from a recent snapshot instead of event 0
2. Only replay events after the snapshot
3. Skip most of the historical events

---

## The 5-Step Snapshot Optimization Algorithm

### Algorithm Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Rebuild Projections from Events                            │
└─────────────────────────────────────────────────────────────┘
           │
           ├─ Step 1: Load all events for wallet
           │
           ├─ Step 2: Build event position map (for UNDO lookup)
           │
           ├─ Step 3: Check for UNDO events
           │          ├─ If yes: Find earliest undone event
           │          │         └─ Search for snapshot BEFORE that
           │          └─ If no: Search for snapshot BEFORE last event
           │
           ├─ Step 4: Use snapshot if found
           │          ├─ Restore projection from snapshot JSON
           │          └─ Apply only NEW events after snapshot
           │
           ├─ Step 5: Fallback to full rebuild if needed
           │          ├─ Clear projections
           │          └─ Apply ALL events (filtered for UNDO)
           │
           └─ Result: Projection contains current state
```

---

## Detailed Algorithm Steps

### Step 1: Load Events

```rust
let events = sqlx::query(
    "SELECT event_id, aggregate_type, aggregate_id, event_type, 
            event_data, created_at, id
     FROM events WHERE wallet_id = $1 ORDER BY created_at ASC"
)
.bind(wallet_id)
.fetch_all(&pool)
.await?;
```

- Fetch ALL events for the wallet in chronological order
- Include database row ID (`id`) for snapshot positioning
- Keep in memory for processing

**Cost**: O(n) database query where n = event count

### Step 2: Build Event Position Map

```rust
let mut event_id_to_position: HashMap<Uuid, i64> = HashMap::new();
for (index, row) in events.iter().enumerate() {
    let event_id: Uuid = row.get("event_id");
    event_id_to_position.insert(event_id, (index + 1) as i64);
}
```

- Maps event UUID → position (1-based index)
- Enables fast lookup of UNDO target events
- Why: UNDO events reference other events by UUID

**Example**:
```
event_id_to_position = {
  "abc-123": 1,  // First event
  "def-456": 2,  // Second event
  "ghi-789": 3,  // Third event (UNDO references this)
}
```

**Cost**: O(n) map construction

### Step 3a: UNDO Event Path

If ANY UNDO events exist:

```rust
for row in &events {
    if event_type == "UNDO" {
        let event_data: Value = row.get("event_data");
        if let Some(undone_id_str) = event_data.get("undone_event_id") {
            if let Ok(undone_id) = Uuid::parse_str(undone_id_str) {
                undone_event_ids.insert(undone_id);
                
                // Find position of undone event
                if let Some(position) = event_id_to_position.get(&undone_id) {
                    undone_event_positions.push(*position);
                }
            }
        }
    }
}

// Find earliest undone event
let min_undone_position = undone_event_positions.iter().min().copied();
```

**Why this matters**:
- UNDO events are special: they don't modify state, they mark another event as "undone"
- We need to find snapshots BEFORE the undone event
- Can't use recent snapshots because they might contain the undone state

**Example Timeline**:
```
Event 1: CREATE Contact "Alice"
Event 2: UPDATE Contact "Alice Smith"  
Event 3: UPDATE Contact "Alice S." 
Event 10: [SNAPSHOT created here]
Event 11-20: More updates
Event 21: UNDO Event 2 (the "Smith" update)
Event 22-30: More updates

Problem: Snapshot at Event 10 includes Event 2's changes
Solution: Need snapshot BEFORE Event 2 (doesn't exist here)
         → Fall back to full rebuild, excluding Event 2
```

### Step 3b: No UNDO Path

If NO UNDO events:

```rust
if let Some(last_id) = last_event_db_id {
    if let Ok(Some(snapshot)) = snapshots::get_snapshot_before_event(
        &pool,
        last_id,
        wallet_id,
    ).await {
        // Snapshot found - use it!
```

Query for snapshot:
```sql
SELECT * FROM projection_snapshots
WHERE last_event_id < $1 AND wallet_id = $2
ORDER BY snapshot_index DESC
LIMIT 1
```

- Find the MOST RECENT snapshot before the last event
- Most recent = highest snapshot_index

**Cost**: O(1) or O(log n) with proper indexing

### Step 4: Use Snapshot (If Found)

```rust
// Restore from snapshot JSON
let db = Database::new(pool.clone());
db.restore_projections_from_snapshot(
    &snapshot,      // Contains old projection state
    user_id,
    wallet_id,
    &undone_event_ids
).await?;

// Apply only new events after snapshot
let events_after_snapshot: Vec<_> = cleaned_events.iter()
    .filter(|row| {
        let event_db_id: Option<i64> = row.get("id");
        event_db_id.map_or(false, |id| id > snapshot.last_event_id)
    })
    .copied()
    .collect();

// Apply these new events
db.apply_events_to_projections_impl(
    &events_after_snapshot,
    user_id,
    wallet_id,
    &mut empty_undone_set
).await?;
```

**What gets restored**:
```rust
pub struct ProjectionSnapshot {
    pub contacts_snapshot: serde_json::Value,      // JSON of all contacts
    pub transactions_snapshot: serde_json::Value,  // JSON of all transactions
    pub last_event_id: i64,                        // DB ID of last event in snapshot
    pub event_count: i64,                          // How many events processed
}
```

**Restoration process**:
1. Parse JSON snapshots
2. Clear current projections
3. Insert all contacts from `contacts_snapshot`
4. Insert all transactions from `transactions_snapshot`
5. Apply new events (events with `id > last_event_id`)

**Cost**: O(m) where m = events after snapshot (typically small)

**Performance Gain**: Instead of O(n) replaying 1,000,000 events, replay only O(m) where m < 10,000

### Step 5: Full Rebuild (Fallback)

If snapshot not found or restoration failed:

```rust
if !used_snapshot {
    // Clear existing projections
    DELETE FROM transactions_projection WHERE wallet_id = $1;
    DELETE FROM contacts_projection WHERE wallet_id = $1;
    
    // Filter events (remove UNDO and undone events)
    let filtered: Vec<_> = events.iter()
        .filter(|row| {
            let event_type = row.get::<String>("event_type");
            
            if event_type == "UNDO" {
                return false;  // Skip UNDO itself
            }
            if undone_event_ids.contains(&event_id) {
                return false;  // Skip undone events
            }
            true
        })
        .collect();
    
    // Apply all remaining events
    db.apply_events_to_projections_impl(
        &filtered,
        user_id,
        wallet_id,
        &mut undone_event_ids
    ).await?;
}
```

**Cost**: O(n) - must process all events

---

## Snapshot Creation Strategy

Snapshots are created automatically in the sync handler when certain conditions are met:

```rust
const SNAPSHOT_INTERVAL: i64 = 10;  // Create snapshot every 10 events

pub fn should_create_snapshot(event_count: i64) -> bool {
    event_count % SNAPSHOT_INTERVAL == 0
}
```

**When snapshots are created**:
- Every 10th event (10, 20, 30, ...)
- After any UNDO event (to prepare for future UNDO scenarios)

**Process**:
```rust
if should_create_snapshot(event_count) || event.event_type == "UNDO" {
    // 1. Extract current projection state
    let (contacts_json, transactions_json) = 
        snapshots::create_snapshot_json(&pool, wallet_id).await?;
    
    // 2. Save snapshot with current state
    snapshots::save_snapshot(
        &pool,
        db_id,           // DB ID of last event
        event_count,     // Total events processed
        contacts_json,   // Current contacts projection
        transactions_json, // Current transactions projection
        wallet_id
    ).await?;
    
    // 3. Cleanup old snapshots (keep only 5 most recent)
    cleanup_old_snapshots(&pool, wallet_id, 5).await?;
}
```

**Storage**:
```sql
CREATE TABLE projection_snapshots (
    id BIGSERIAL PRIMARY KEY,
    wallet_id UUID NOT NULL,
    snapshot_index BIGINT NOT NULL,    -- Sequential number for this wallet
    last_event_id BIGINT NOT NULL,     -- DB ID of last event in snapshot
    event_count BIGINT NOT NULL,       -- Total events at snapshot time
    contacts_snapshot JSONB NOT NULL,  -- Full contacts projection
    transactions_snapshot JSONB NOT NULL, -- Full transactions projection
    created_at TIMESTAMP NOT NULL
);
```

---

## UNDO Event Handling

### What is an UNDO Event?

An UNDO event doesn't modify state directly—it marks another event as "undone":

```json
{
  "type": "UNDO",
  "aggregate_type": "contact",
  "aggregate_id": "contact-123",
  "event_data": {
    "undone_event_id": "event-456"  // Reference to undone event
  },
  "timestamp": "2024-01-21T10:00:00Z"
}
```

### Processing UNDO Events

**During rebuild**:
1. Collect all undone event UUIDs into a set
2. Filter them OUT during event application
3. Also skip the UNDO events themselves

**Example**:
```
Original sequence:
1. CREATED Contact "Alice"
2. UPDATED Contact "Bob"
3. UPDATED Contact "Alice Smith"
4. UNDO [undone_event_id: event-3]  <- Mark event 3 as undone
5. UPDATE Contact "Alice S."

Application process:
- Event 1: Apply (CREATE Alice)
- Event 2: Apply (CREATE Bob)  
- Event 3: SKIP (it's in undone_event_ids)
- Event 4: SKIP (it's an UNDO event itself)
- Event 5: Apply (UPDATE Alice S.)

Final state: Alice = "Alice S.", Bob = "Bob"
```

---

## Performance Analysis

### Scenario: 1,000,000 Events

**Without Snapshots**:
- Rebuild must replay all 1,000,000 events
- Cost: ~1-5 seconds depending on event complexity
- Database load: HIGH

**With Snapshots** (every 10 events, 5 snapshots kept):
- Latest snapshot: at event 999,990 (10 snapshots ago from 1M)
- Replay only: 10 events
- Cost: ~0.001 seconds
- Database load: LOW
- **Speedup**: 1000-5000x faster

### Snapshot Retention Policy

```
SNAPSHOT_INTERVAL = 10
MAX_SNAPSHOTS = 5

Snapshots created at events: 10, 20, 30, 40, 50, 60, 70, ...
Latest 5 kept:              50, 60, 70, 80, 90
Oldest deleted:             10, 20, 30, 40
```

At 1,000,000 events:
- Snapshots every 10 events = 100,000 snapshots possible
- We keep only 5 = 99,995 deleted
- Latest snapshot ~50-90 events back
- Cost of cleanup: O(n snapshots) = O(5) = O(1) effectively

---

## Key Data Structures

### EventRow

```rust
pub struct EventRow {
    pub event_id: Uuid,           // Unique event identifier
    pub aggregate_type: String,   // "contact", "transaction", "permission"
    pub aggregate_id: Uuid,       // Which contact/transaction this affects
    pub event_type: String,       // "CREATED", "UPDATED", "DELETED", "UNDO"
    pub data: serde_json::Value,  // Event payload (name, phone, amount, etc.)
    pub created_at: NaiveDateTime,// When event occurred (not DB insertion time)
    pub version: i32,             // Event schema version
}
```

### ProjectionSnapshot

```rust
pub struct ProjectionSnapshot {
    pub id: i64,
    pub snapshot_index: i64,                    // 0, 1, 2, ... for this wallet
    pub last_event_id: i64,                     // DB ID where snapshot ends
    pub event_count: i64,                       // Total events at snapshot
    pub contacts_snapshot: serde_json::Value,   // All contacts as JSON
    pub transactions_snapshot: serde_json::Value, // All transactions as JSON
    pub created_at: NaiveDateTime,
}
```

### Contacts Projection Schema

```sql
CREATE TABLE contacts_projection (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    wallet_id UUID NOT NULL,
    name VARCHAR NOT NULL,
    username VARCHAR,
    phone VARCHAR,
    email VARCHAR,
    notes TEXT,
    is_deleted BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    last_event_id BIGINT
);
```

---

## Code Flow: Complete Example

### Scenario: Rebuild after 5000 events

```rust
// Step 1: Load all events
let events = db.get_all_events_for_wallet(wallet_id).await?;
// Returns: Vec of 5000 EventRow

// Step 2: Build position map
let mut map = HashMap::new();
for (i, event) in events.iter().enumerate() {
    map.insert(event.event_id, i + 1);
}
// map has 5000 entries

// Step 3: Check for UNDO
let has_undo = events.iter().any(|e| e.event_type == "UNDO");
// false - no UNDO events

// Step 4: Try snapshot optimization
if let Some(snapshot) = get_snapshot_before_event(
    5000,  // last_event_db_id
    wallet_id
).await? {
    // Found snapshot created at event 4990
    // Snapshot has contacts/transactions from that point
    
    // Restore
    db.restore_projections_from_snapshot(snapshot).await?;
    // Inserts contacts and transactions from snapshot JSON
    
    // Get events after snapshot
    let events_after = events.iter()
        .filter(|e| e.id > snapshot.last_event_id)  // 4990
        .collect();
    // events_after has ~10 events (4991-5000)
    
    // Apply only new events
    db.apply_events_to_projections_impl(events_after).await?;
    // UPDATE contact names, add transactions, etc.
    
    return Ok(()); // Done! Very fast.
}

// Fallback: no snapshot or restore failed
db.clear_projections(wallet_id).await?;
db.apply_events_to_projections_impl(all_5000_events).await?;
// Slow, but correct
```

---

## Testing

### Test Coverage

1. **`test_snapshot_optimization_used_when_no_undo_events`**
   - Creates 10 events (triggers snapshot)
   - Creates 3 more events
   - Rebuilds and verifies snapshot was used
   - ✅ Snapshot optimization path works

2. **`test_full_rebuild_used_when_undo_events_present`**
   - Creates 10 events (triggers snapshot)
   - Creates UNDO event
   - Rebuilds and verifies undone event is excluded
   - ✅ UNDO handling works

3. **`test_snapshot_restoration_correctness`**
   - Creates snapshot
   - Modifies database directly
   - Rebuilds and verifies snapshot restores correct state
   - ✅ Snapshot restoration is accurate

4. **`test_snapshot_optimization_with_transactions`**
   - Tests snapshot with both contacts AND transactions
   - ✅ Works with multiple aggregates

---

## Common Issues and Debugging

### Issue: Contact name is wrong after rebuild

**Possible Causes**:
1. UPDATE event not being applied
2. Parameter binding bug in UPDATE query
3. Event ordering incorrect

**Debug**:
```sql
-- Check event count
SELECT COUNT(*) FROM events WHERE wallet_id = $1;

-- Check snapshots exist
SELECT * FROM projection_snapshots WHERE wallet_id = $1;

-- Check projection state
SELECT name FROM contacts_projection WHERE id = $1;

-- Manually replay events
SELECT event_type, event_data FROM events 
WHERE aggregate_id = $1 
ORDER BY created_at;
```

### Issue: Snapshots not being created

**Possible Causes**:
1. Event count not reaching 10
2. `should_create_snapshot()` returning false
3. Snapshot table has write errors

**Debug**:
```sql
-- Count events
SELECT COUNT(*) as total, 
       (COUNT(*) % 10) as remainder 
FROM events 
WHERE wallet_id = $1;

-- Check snapshots
SELECT COUNT(*), MAX(snapshot_index) 
FROM projection_snapshots 
WHERE wallet_id = $1;
```

---

## Future Optimizations

1. **Incremental Snapshots**: Store only changes since last snapshot, not full state
2. **Async Snapshot Creation**: Create snapshots in background without blocking sync
3. **Snapshot Compression**: Store snapshots in compressed format
4. **Event Filtering**: Only keep snapshots for aggregates that changed
5. **Distributed Snapshots**: Replicate snapshots across regions for disaster recovery

