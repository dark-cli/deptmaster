# Event Sourcing Memory Optimization: Critical Performance Issue

## Problem Statement

The current `rebuild_projections_from_events()` implementation loads **ALL events for a wallet into RAM** before processing:

```rust
let events = sqlx::query(
    "SELECT event_id, aggregate_type, aggregate_id, event_type, 
            event_data, created_at, id
     FROM events WHERE wallet_id = $1 ORDER BY created_at ASC"
)
.bind(wallet_id)
.fetch_all(&pool)  // <-- THIS IS THE PROBLEM
.await?;
```

## Why This is Bad

### 0. CRITICAL: Loads ALL events BEFORE deciding on optimization strategy

The worst part: the code loads ALL events **REGARDLESS of whether snapshot optimization will be used**:

```rust
// Loads ALL 1M events into RAM
let events = sqlx::query("SELECT ... FROM events WHERE wallet_id = $1")
    .fetch_all(&pool)  // <-- 1GB RAM for 1M events
    .await?;

// Then builds position map for ALL events
for event in events { /* process 1M events */ }

// Then checks for UNDO in ALL events
let has_undo = events.iter().any(...);

// THEN decides: snapshot or full rebuild?
if use_snapshot {
    // Too late! Already loaded all 1M events
}
```

**This defeats the entire purpose of snapshots!**

Even with snapshot optimization:
- Load 1M events (1GB RAM) ❌
- Identify snapshot exists ✅
- Restore from snapshot (50MB) ✅
- Apply 10 events after snapshot ✅
- **Result**: Still consumed 1GB RAM to avoid processing 1M events

### 1. Memory Consumption

**Scenario: 1M events**
- Average event_data: ~500 bytes (JSON with contact info, transaction details)
- Total: 1M × ~1KB = **1GB of RAM per wallet rebuild**
- Multiple concurrent rebuilds = Multiple GBs consumed
- Worst case: OOM crash on large wallets

**Scenario: 10M events**
- Total: **10+ GB of RAM**
- Most production servers have 16-64GB total
- One wallet rebuild could starve other operations

### 2. GC Pressure

- Creating 1M Rust objects causes allocator stress
- Garbage collection pauses
- Latency spikes during rebuild
- Worse with concurrent workloads

### 3. No Streaming

- Must wait for ALL events to load before processing first event
- Can't start building projection until fetch completes
- Higher time-to-first-byte

### 4. Snapshot Optimization is Undermined

The whole point of snapshots is to avoid processing all events:

```
Without snapshot optimization:
- Load 1M events → Process 1M events

With snapshot optimization (current):
- Load 1M events into RAM (!!!)
- Filter to 10 events after snapshot
- Process 10 events
- Result: Still used 1GB RAM, only processed 10 events!
```

---

## Three-Tier Optimization Strategy

The solution depends on the path taken:

### Path 1: Snapshot Exists (Fast Path) - 95% of rebuilds

**Current**: Load all 1M events, then use snapshot (wasteful!)
**Optimized**: Don't load all events upfront

```
Snapshot path (when snapshot exists):
1. Check if snapshot exists
2. If yes: ONLY load events AFTER snapshot (typically 0-20 events)
3. Skip loading all events entirely
4. Memory: O(1) instead of O(n)
```

### Path 2: Full Rebuild (Slow Path) - 5% of rebuilds

**Current**: Load all 1M events into RAM, process
**Optimized**: Stream/batch events, process as you go

```
Full rebuild path (no snapshot or restore failed):
1. Load events in batches of 1000
2. Clear projections
3. Process batch, then next batch
4. Memory: O(BATCH_SIZE) instead of O(n)
```

### Path 3: UNDO Detection - Optimization opportunity

**Current**: Load all 1M events just to check if ANY are UNDO
**Optimized**: Only load UNDO events

```sql
-- Instead of: SELECT * FROM events WHERE wallet_id = $1
-- Do this:
SELECT event_data FROM events 
WHERE wallet_id = $1 AND event_type = 'UNDO'
```

---

## Better Approaches

### Option 1: Database Cursor / Streaming (BEST)

**Idea**: Stream events from database, process as they arrive

```rust
// Don't use fetch_all() - use a cursor/stream
let mut events = sqlx::query_as::<_, EventRow>(
    "SELECT ... FROM events WHERE wallet_id = $1 ORDER BY created_at ASC"
)
.bind(wallet_id)
.fetch(&pool);  // <-- Returns a stream, not Vec

// Process as we go
let mut event_position = 0;
while let Some(row) = events.next().await? {
    event_position += 1;
    event_id_to_position.insert(row.event_id, event_position);
    
    // Process event immediately
    if has_undo && row.event_type == "UNDO" {
        // Handle UNDO
    }
}

// Memory usage: O(1) - only current event in memory
// Time to process: O(n) same, but no GC pressure
```

**Pros**:
- O(1) memory regardless of event count
- Can start processing immediately
- Naturally handles very large event streams
- SQLx supports this natively

**Cons**:
- Can only iterate once (can't re-sort)
- Need to redesign UNDO handling (see below)

### Option 2: Two-Pass Algorithm

**Pass 1: Build position map** (small memory)
```rust
// Only fetch event_id and id columns, not event_data
let mut event_id_to_position = HashMap::new();
let mut rows = sqlx::query(
    "SELECT event_id, id FROM events WHERE wallet_id = $1 ORDER BY id ASC"
)
.bind(wallet_id)
.fetch(&pool);

let mut position = 0;
while let Some(row) = rows.next().await? {
    position += 1;
    event_id_to_position.insert(row.get::<Uuid>("event_id"), position);
}
// Memory: O(n) for HashMap, but no event_data

// Pass 2: Check for UNDO events
let undo_events = sqlx::query(
    "SELECT event_data FROM events 
     WHERE wallet_id = $1 AND event_type = 'UNDO'"
)
.bind(wallet_id)
.fetch_all(&pool)
.await?;

let undone_event_ids: HashSet<_> = undo_events
    .iter()
    .filter_map(|row| /* extract undone_event_id */)
    .collect();

// Pass 3: Process events with streaming
let mut events = sqlx::query_as::<_, EventRow>(
    "SELECT ... FROM events WHERE wallet_id = $1 ORDER BY created_at ASC"
)
.bind(wallet_id)
.fetch(&pool);

while let Some(event) = events.next().await? {
    if undone_event_ids.contains(&event.event_id) {
        continue;
    }
    apply_event(event).await?;
}
```

**Pros**:
- Still O(1) event memory
- Can build position map in first pass
- Clear separation of concerns

**Cons**:
- Multiple passes over events (more DB traffic)
- But each pass is faster (smaller columns)

### Option 3: Hybrid Approach (Recommended)

**Small batches + snapshot optimization**

```rust
const BATCH_SIZE: usize = 1000;  // Process 1000 events at a time

// Still use snapshots
if let Some(snapshot) = get_snapshot() {
    restore_from_snapshot().await?;
    
    // Only load events AFTER snapshot in batches
    let mut offset = 0;
    loop {
        let batch = sqlx::query_as::<_, EventRow>(
            "SELECT ... FROM events 
             WHERE wallet_id = $1 AND id > $2
             ORDER BY created_at ASC
             LIMIT $3 OFFSET $4"
        )
        .bind(wallet_id)
        .bind(snapshot.last_event_id)
        .bind(BATCH_SIZE)
        .bind(offset)
        .fetch_all(&pool)
        .await?;
        
        if batch.is_empty() {
            break;
        }
        
        for event in &batch {
            apply_event(event).await?;
        }
        
        offset += batch.len();
    }
}

// Memory usage: O(BATCH_SIZE), typically 1-5MB regardless of wallet size
// With snapshot optimization: usually just 1 batch!
```

**Pros**:
- Bounded memory (O(BATCH_SIZE))
- Still benefits from snapshots
- Works with snapshot optimization
- Easy to implement

**Cons**:
- Multiple round trips to DB
- Can optimize with higher BATCH_SIZE

---

## Performance Comparison

### 1M events, no snapshot

| Approach | Memory | Time | Scalability |
|----------|--------|------|-------------|
| Current (fetch_all) | 1GB+ | 5s | ❌ Bad |
| Streaming | ~50MB | 5s | ✅ Good |
| Batches (1000) | ~5MB | 5.5s | ✅ Good |
| Hybrid + snapshot | ~5MB | 0.5s | ✅ Excellent |

### 10M events, no snapshot

| Approach | Memory | Time | Scalability |
|----------|--------|------|-------------|
| Current (fetch_all) | 10GB+ | 50s | ❌ FAILS |
| Streaming | ~50MB | 50s | ✅ Good |
| Batches (1000) | ~5MB | 55s | ✅ Good |
| Hybrid + snapshot | ~5MB | 0.5s | ✅ Excellent |

---

## ⭐ SIMPLEST SOLUTION: Use Tracked `last_event_id`

**KEY INSIGHT**: We already track `last_event_id` in every projection row!

```sql
contacts_projection:
  id, user_id, name, ..., last_event_id BIGINT

transactions_projection:
  id, contact_id, amount, ..., last_event_id BIGINT
```

Instead of loading all events, **just load events AFTER the last processed event**:

```rust
// Get the last event we've already processed
let max_event_id = sqlx::query_scalar::<_, Option<i64>>(
    "SELECT COALESCE(MAX(last_event_id), 0) FROM contacts_projection WHERE wallet_id = $1"
)
.bind(wallet_id)
.fetch_one(&pool)
.await?;

// Only fetch NEW events
let events = sqlx::query("SELECT ... FROM events WHERE id > $1 ORDER BY created_at ASC")
    .bind(max_event_id.unwrap_or(0))
    .fetch_all(&pool)  // Only new events!
    .await?;
```

**Result**:
- No complex snapshot logic needed
- No batching complexity
- Memory: ~10KB regardless of wallet size
- **100,000x faster for normal case**

---

## Old Approaches (for reference)

### Optimal Multi-Path Solution (OUTDATED)

Instead of loading all events then deciding, **check snapshot FIRST**:

```rust
// Step 1: Check for snapshot FIRST (fast query)
if let Some(snapshot) = get_snapshot_before_last_event(wallet_id).await {
    // Fast path: only load events after snapshot
    restore_from_snapshot(&snapshot).await?;
    
    let batch = fetch_events_batch(
        wallet_id,
        snapshot.last_event_id,
        1000  // Only events after snapshot
    ).await?;
    
    apply_events(batch).await?;
    return Ok(());  // Done! Minimal memory used
}

// Step 2: If no snapshot, check for UNDO events (minimal query)
let has_undo = has_any_undo_events(wallet_id).await?;

// Step 3: Full rebuild (use batching)
if has_undo {
    // Load UNDO events separately (small)
    let undo_events = load_undo_events(wallet_id).await?;
    let undone_ids = extract_undone_ids(&undo_events);
    
    // Batch-load and process other events
    let mut offset = 0;
    loop {
        let batch = fetch_events_batch(wallet_id, offset, 1000).await?;
        if batch.is_empty() { break; }
        
        for event in batch {
            if !undone_ids.contains(&event.id) {
                apply_event(&event).await?;
            }
        }
        offset += batch.len();
    }
}
```

**Memory usage by scenario**:

| Scenario | Path | Memory | Time |
|----------|------|--------|------|
| Normal rebuild with snapshot | Snapshot path | ~5MB | 0.1s |
| Large wallet, needs rebuild | Full rebuild (batched) | ~5MB | 5s |
| Multiple UNDO events | Full rebuild (batched) | ~5MB | 5s |
| Snapshot + UNDO after | Snapshot path | ~5MB | 0.1s |

---

## RECOMMENDED SOLUTION ⭐ (Two-Part)

### Optimization 1: Skip Already-Processed Events (Trivial)

**Use `last_event_id` tracking (already exists!)**

```rust
// Get the last event we've already processed
let max_event_id = sqlx::query_scalar::<_, Option<i64>>(
    "SELECT COALESCE(MAX(last_event_id), 0) FROM contacts_projection WHERE wallet_id = $1"
)
.bind(wallet_id)
.fetch_one(&pool)
.await?;

// Only fetch NEW events
let events = sqlx::query("SELECT ... FROM events WHERE id > $1 ...")
    .bind(max_event_id.unwrap_or(0))
    .fetch_all(&pool)
    .await?;
```

**Impact**: Most rebuilds have 0-100 new events = ~1KB memory

---

### Optimization 2: Batch Processing for Full Rebuilds (When No Prior State)

For initial setup or disaster recovery where projections are empty:

```rust
const BATCH_SIZE: usize = 1000;  // Configurable via .env

let mut offset = 0;
loop {
    // Fetch one batch
    let batch = sqlx::query(
        "SELECT ... FROM events WHERE wallet_id = $1 AND id > $2
         ORDER BY created_at ASC LIMIT $3 OFFSET $4"
    )
    .bind(wallet_id)
    .bind(max_event_id.unwrap_or(0))
    .bind(BATCH_SIZE)
    .bind(offset)
    .fetch_all(&pool)
    .await?;
    
    if batch.is_empty() { break; }
    
    // Process this batch
    for event in &batch {
        apply_event_to_projection(event).await?;
    }
    
    offset += batch.len();
}
```

**Impact**: Memory capped at ~5-10MB per batch, regardless of total events

---

## Combined Effect

| Scenario | Memory | Speed |
|----------|--------|-------|
| Normal rebuild (1-100 new events) | ~1KB | <1s |
| Full rebuild (1M events) | ~5-10MB | 5-10s |
| Full rebuild (10M events) | ~5-10MB | 50-100s |

**With both optimizations**: Scalable to any wallet size

**Implementation Plan (Two-Phase)**:

### Phase 1: Skip Already-Processed Events (Priority: IMMEDIATE)

```
1. Add query: SELECT COALESCE(MAX(last_event_id), 0) FROM contacts_projection
2. Change WHERE clause: add "AND id > $2"
3. Bind max_event_id parameter
4. Test: verify normal rebuilds use <10KB memory
```

**Time**: 15 minutes
**Impact**: 90% of rebuilds now instant with minimal memory

---

### Phase 2: Batch Processing for Full Rebuilds (Priority: SOON)

```
1. Add config in .env:
   EVENT_REBUILD_BATCH_SIZE=1000
   
2. Add env variable to Config struct:
   pub event_rebuild_batch_size: usize
   
3. Implement batch loop in rebuild_projections_from_events:
   for offset in (0..total).step_by(batch_size) {
       fetch batch
       apply batch
   }
   
4. Test with 10M+ event wallet
```

**Time**: 30 minutes
**Impact**: Full rebuilds bounded to ~10MB memory, linear time

---

## Naming: "Batch" vs Alternatives

Term | Usage | Pros | Cons |
|-----|-------|------|------|
| **Batch** | Standard in DB/event sourcing | Industry term, clear | Could mean HTTP batch requests |
| Chunk | File/stream processing | Clear "piece" metaphor | Less formal |
| Window | Streaming/timeseries | Common in Kafka | May confuse with time windows |
| Page | Pagination context | Familiar to web devs | Less about "batch processing" |
| Segment | Data warehouse | Technical but vague | Overloaded term |

**Recommendation**: `BATCH` - it's the industry standard for event sourcing and database operations.

**Config naming**:
```env
# Event Sourcing Batch Settings
EVENT_REBUILD_BATCH_SIZE=1000    # How many events to process at once during rebuild
```

---

**Expected Results**:
- Optimization 1: Most rebuilds <1s, ~1KB memory
- Optimization 2: Full rebuilds ~5-10MB memory, linear time
- Combined: Scalable to 1B+ events per wallet

---

## Implementation Code Snippets

### Snippet 1: Phase 1 - Skip Already-Processed Events

```rust
// In src/services/projections.rs - Projections::rebuild_projections_from_events()

// BEFORE (line 26-44):
let user_id = sqlx::query_scalar::<_, Uuid>(...)
    .bind(wallet_id)
    .fetch_one(&*state.db_pool)
    .await?;

let events = sqlx::query(
    r#"
    SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, id
    FROM events
    WHERE wallet_id = $1
    ORDER BY created_at ASC
    "#
)
.bind(wallet_id)
.fetch_all(&*state.db_pool)
.await?;

// AFTER:
let user_id = sqlx::query_scalar::<_, Uuid>(...)
    .bind(wallet_id)
    .fetch_one(&*state.db_pool)
    .await?;

// NEW: Get max event ID already processed
let max_processed_id: Option<i64> = sqlx::query_scalar(
    "SELECT COALESCE(MAX(last_event_id), 0) FROM contacts_projection WHERE wallet_id = $1"
)
.bind(wallet_id)
.fetch_one(&*state.db_pool)
.await?;

let events = sqlx::query(
    r#"
    SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, id
    FROM events
    WHERE wallet_id = $1 AND id > $2
    ORDER BY created_at ASC
    "#
)
.bind(wallet_id)
.bind(max_processed_id.unwrap_or(0))  // NEW parameter
.fetch_all(&*state.db_pool)
.await?;
```

---

### Snippet 2: Phase 2 - Batch Processing for Full Rebuild

```rust
// In src/services/projections.rs - Full rebuild section (around line 237)

const BATCH_SIZE: usize = 1000;  // Or load from config.event_rebuild_batch_size

if !used_snapshot {
    tracing::warn!("Snapshot optimization failed, performing full rebuild");
    
    // CHANGE: Instead of processing all events at once,
    // fetch and process in batches
    
    let mut offset = 0;
    
    loop {
        // Fetch one batch
        let batch = sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, id
            FROM events
            WHERE wallet_id = $1 AND id > $2
            ORDER BY created_at ASC
            LIMIT $3 OFFSET $4
            "#
        )
        .bind(wallet_id)
        .bind(max_processed_id.unwrap_or(0))
        .bind(BATCH_SIZE as i64)
        .bind(offset as i64)
        .fetch_all(&*state.db_pool)
        .await?;
        
        if batch.is_empty() {
            break;  // No more events
        }
        
        // Collect undone event IDs (can reuse from earlier check)
        let mut undone_event_ids = /* from earlier */;
        
        // Process this batch
        let filtered: Vec<_> = batch.iter()
            .filter(|row| {
                let event_type: String = row.get("event_type");
                if event_type == "UNDO" {
                    return false;
                }
                true
            })
            .map(|row| row as &sqlx::postgres::PgRow)
            .collect();
        
        // Apply events in this batch
        let rows_to_apply: Vec<_> = filtered.iter().map(|row| *row).collect();
        let db = Database::new((*state.db_pool).clone());
        db.apply_events_to_projections_impl(&rows_to_apply, user_id, wallet_id, &mut undone_event_ids).await?;
        
        tracing::info!("Processed batch of {} events (offset: {})", batch.len(), offset);
        
        offset += batch.len();
    }
}
```

---

### Snippet 3: Configuration (in .env)

```bash
# Event Sourcing Configuration
# Batch size for rebuilding projections from events
# Larger values = more memory per batch but fewer DB queries
# Smaller values = less memory but more DB round-trips
# Optimal: 500-5000 depending on event_data size
# Default: 1000
EVENT_REBUILD_BATCH_SIZE=1000
```

---

### Snippet 4: Load from Config

```rust
// In src/config.rs
pub struct Config {
    // ... existing fields ...
    pub event_rebuild_batch_size: usize,
}

impl Config {
    pub fn from_env() -> Result<Self, Error> {
        Ok(Self {
            // ... existing fields ...
            event_rebuild_batch_size: std::env::var("EVENT_REBUILD_BATCH_SIZE")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(1000),  // Default: 1000 events per batch
        })
    }
}

// In src/services/projections.rs
pub async fn rebuild_projections_from_events(
    state: &AppState,
    wallet_id: Uuid,
) -> Result<(), sqlx::Error> {
    let batch_size = state.config.event_rebuild_batch_size;
    // ... use batch_size in loop ...
}
```

---

## Monitoring & Metrics

**Add metrics to track**:
```rust
// In apply_events_to_projections_impl
let start_memory = get_memory_usage();
let events_processed = 0;

for batch in batches {
    for event in batch {
        apply_event(&event).await?;
        events_processed += 1;
    }
    
    let current_memory = get_memory_usage();
    tracing::info!(
        "Processed {} events, memory usage: {}MB",
        events_processed,
        current_memory / 1024 / 1024
    );
}
```

**Track**:
- Memory per wallet rebuild
- Time per batch
- Events per second throughput
- Peak memory during rebuild

---

## Database Schema Optimization

**Current Schema Issue**:
```sql
SELECT event_id, aggregate_type, aggregate_id, event_type, 
       event_data, created_at, id
FROM events WHERE wallet_id = $1 ORDER BY created_at ASC
```

Fetches `event_data` (the large column) for ALL events.

**Optimized Schema**:
```sql
-- For position map (small)
SELECT event_id, id FROM events 
WHERE wallet_id = $1 
ORDER BY id ASC;

-- For UNDO detection (medium)  
SELECT id, event_type, event_data FROM events
WHERE wallet_id = $1 AND event_type = 'UNDO';

-- For event processing (with snapshot filter)
SELECT event_id, aggregate_type, aggregate_id, event_type, 
       event_data, created_at, id
FROM events
WHERE wallet_id = $1 AND id > $2  -- $2 = snapshot.last_event_id
ORDER BY created_at ASC
LIMIT $3 OFFSET $4;
```

**Add Database Index**:
```sql
CREATE INDEX idx_events_wallet_created 
ON events(wallet_id, created_at ASC);

CREATE INDEX idx_events_wallet_id_type
ON events(wallet_id, id, event_type);
```

---

## UNDO Event Handling in Streaming Mode

**Challenge**: Current code builds position map first, then checks UNDOs.

**Streaming Alternative**:
```rust
// Track as we stream
let mut position = 0;
let mut event_id_to_position = HashMap::new();
let mut undone_event_ids = HashSet::new();

let mut events = fetch_events_stream().await?;

while let Some(event) = events.next().await? {
    position += 1;
    event_id_to_position.insert(event.event_id, position);
    
    // Check if this is an UNDO event
    if event.event_type == "UNDO" {
        if let Some(undone_id) = parse_undone_event_id(&event.event_data) {
            undone_event_ids.insert(undone_id);
        }
    }
}

// Now have position map and undone set without loading all in memory
```

---

## Risk Assessment

### Low Risk Changes
- ✅ Adding BATCH_SIZE constant
- ✅ Using LIMIT/OFFSET in queries
- ✅ Adding metrics/logging

### Medium Risk Changes  
- ⚠️ Refactoring event loading loops
- ⚠️ Changing query structure
- ⚠️ Impact on snapshot logic

### Mitigation
- Add comprehensive tests before refactoring
- Run performance tests on test database
- Gradual rollout with feature flags
- Monitor memory during rollout

---

## Alternatives Considered

### Don't rebuild at all
- ❌ Then projections get out of sync
- ❌ Consistency issues

### Only rebuild when requested
- ❌ Still need to handle rebuild efficiently
- ❌ Just delays the problem

### Cache projections indefinitely
- ❌ Still need snapshots/rebuilds for data integrity
- ❌ Defeats the point of event sourcing

### Use external cache (Redis)
- ⚠️ Adds complexity
- ⚠️ Distributed cache invalidation issues
- ⚠️ Snapshots already serve this role

---

## Decision Log

**Status**: ⚠️ CRITICAL - Needs Implementation

**Decision**: Implement Option 3 (Hybrid Batching + Snapshots)
- Low risk, high benefit
- Keep snapshot logic, just add batching
- Bounded memory regardless of wallet size

**Owner**: Backend team
**Priority**: HIGH
**Timeline**: Next sprint
