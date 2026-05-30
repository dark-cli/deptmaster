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

## Recommended Solution

**Implement Option 3 (Hybrid + Batches)** because:

1. **Low Risk**: Minimal code changes, keeps snapshot logic intact
2. **High Benefit**: 10-100x memory reduction
3. **Good Performance**: Bounded memory with minimal time overhead
4. **Scalable**: Works with wallets of any size
5. **Can Iterate**: Easy to optimize BATCH_SIZE later

**Implementation Plan**:

```
Phase 1: Add BATCH_SIZE constant
Phase 2: Refactor snapshot path to use batches
Phase 3: Refactor full rebuild path to use batches
Phase 4: Add monitoring/metrics for memory usage
Phase 5: Benchmark and tune BATCH_SIZE
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
