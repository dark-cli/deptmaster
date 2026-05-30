# Event Sourcing Improvements Roadmap

## Current State
- ✅ Type-driven validation (SyncEventRequest with deserializers)
- ✅ Snapshot service exists
- ✅ last_event_id tracking in projections
- ✅ Permission model integration
- ⏳ Batch processing (planned)

---

## Tier 1: Quick Wins (1-2 hours each)

### 1. Database Indexing for Faster Queries
**Impact**: 10-100x faster event queries
**Complexity**: Low

Current problem:
```sql
SELECT * FROM events WHERE wallet_id = $1 AND id > $2
```

Add indices:
```sql
CREATE INDEX idx_events_wallet_id_desc 
ON events(wallet_id, id DESC);

CREATE INDEX idx_events_wallet_created 
ON events(wallet_id, created_at ASC);

CREATE INDEX idx_events_undo_only
ON events(wallet_id, id) 
WHERE event_type = 'UNDO';  -- For UNDO check query
```

**Expected**: Query time from 500ms → 5ms

---

### 2. Separate UNDO Event Detection
**Impact**: Avoid loading large event_data for UNDO check
**Complexity**: Low

Current:
```rust
// Loads all events including large event_data
let events = fetch_all_events();
let has_undo = events.iter().any(|e| e.event_type == "UNDO");
```

Better:
```rust
// Only load event_type column
let has_undo: bool = sqlx::query_scalar(
    "SELECT EXISTS(
        SELECT 1 FROM events 
        WHERE wallet_id = $1 AND event_type = 'UNDO'
    )"
)
.bind(wallet_id)
.fetch_one(&pool)
.await?;

// Only if UNDO exists, load UNDO events separately
if has_undo {
    let undo_events = sqlx::query(
        "SELECT event_data FROM events 
         WHERE wallet_id = $1 AND event_type = 'UNDO'"
    )
    .fetch_all(&pool)
    .await?;
}
```

**Expected**: Skip loading event_data for 95% of wallets

---

### 3. Metrics & Monitoring
**Impact**: Visibility into rebuild performance
**Complexity**: Low

Add metrics:
```rust
pub struct RebuildMetrics {
    pub wallet_id: Uuid,
    pub total_events: i64,
    pub new_events: i64,
    pub batches_processed: i64,
    pub duration_ms: u64,
    pub memory_peak_mb: f64,
    pub events_per_second: f64,
}

// Log in rebuild function
tracing::info!(
    wallet_id = %wallet_id,
    total_events = event_count,
    new_events = batch_size,
    duration_ms = elapsed.as_millis(),
    "Rebuild completed"
);
```

**Expected**: Understand rebuild patterns, catch regressions

---

### 4. Event Count & Statistics Cache
**Impact**: Fast queries for event count
**Complexity**: Low

Add table:
```sql
CREATE TABLE event_statistics (
    wallet_id UUID PRIMARY KEY,
    total_event_count BIGINT NOT NULL,
    last_event_id BIGINT NOT NULL,
    last_updated TIMESTAMP NOT NULL
);
```

Update on each sync:
```rust
// After inserting event
UPDATE event_statistics 
SET total_event_count = total_event_count + 1,
    last_event_id = $1
WHERE wallet_id = $2;
```

**Expected**: Event count queries instant instead of COUNT(*)

---

## Tier 2: Medium Improvements (2-4 hours each)

### 5. Snapshot Optimization During Rebuild
**Impact**: 10-100x faster when snapshots exist
**Complexity**: Medium

Current: Snapshots created but not used during rebuild
Problem: We rebuild from scratch, ignoring available snapshots

Solution:
```rust
pub async fn rebuild_projections_from_events(
    state: &AppState,
    wallet_id: Uuid,
) -> Result<(), sqlx::Error> {
    // Step 1: Check if snapshot exists
    if let Some(snapshot) = get_latest_snapshot(wallet_id).await? {
        // Step 2: Restore projection from snapshot
        restore_projections_from_snapshot(&snapshot).await?;
        
        // Step 3: Only apply events after snapshot
        let events_after = fetch_events_batch(
            wallet_id,
            snapshot.last_event_id,
            BATCH_SIZE
        ).await?;
        
        apply_events(events_after).await?;
        return Ok(());
    }
    
    // Fallback: full rebuild with batching
    // ... existing batch logic
}
```

**Expected**: 95% of rebuilds: 0.1s instead of 5-10s

---

### 6. Async Snapshot Creation
**Impact**: Don't block sync handler on snapshot creation
**Complexity**: Medium

Current:
```rust
// In post_sync_events handler
if should_create_snapshot(event_count) {
    create_and_save_snapshot().await?;  // BLOCKS
}
```

Better:
```rust
// Spawn background task
if should_create_snapshot(event_count) {
    let pool = state.db_pool.clone();
    tokio::spawn(async move {
        let _ = snapshots::save_snapshot_async(&pool, wallet_id).await;
    });
}
```

**Expected**: Sync endpoint latency: -100ms

---

### 7. Event Compression for Archived Events
**Impact**: Reduce database storage for old events
**Complexity**: Medium

Idea:
```sql
-- Archive events older than 1 year
SELECT event_id, gzip(event_data) as compressed_data
FROM events
WHERE created_at < NOW() - INTERVAL '1 year';
```

**Expected**: Storage: -50-70% for large wallets

---

### 8. UNDO Event Batch Optimization
**Impact**: Faster UNDO detection, smaller position map
**Complexity**: Medium

Current: Build position map for ALL events, then check UNDO
Better: 
```rust
// Step 1: Load UNDO events separately
let undo_events = fetch_undo_events(wallet_id).await?;
let mut undone_ids = HashSet::new();
for undo in undo_events {
    if let Some(id) = extract_undone_id(&undo.event_data) {
        undone_ids.insert(id);
    }
}

// Step 2: Only build position map for events that need it
if !undone_ids.is_empty() {
    let position_map = build_position_map(wallet_id).await?;
} else {
    // No UNDO events, no need for position map
}

// Step 3: Filter events during load, not after
let events = fetch_events_filtered(
    wallet_id,
    max_processed_id,
    BATCH_SIZE,
    &undone_ids  // Pass to DB filter
).await?;
```

**Expected**: Position map: -99% for 99% of wallets

---

## Tier 3: Advanced Improvements (4-8 hours each)

### 9. Event Deduplication & Idempotency
**Impact**: Handle duplicate event submissions safely
**Complexity**: High

Problem: If sync request is retried, same event inserted twice

Solution:
```sql
CREATE TABLE event_idempotency (
    request_id UUID PRIMARY KEY,
    event_id UUID NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL
);

-- Before insert
if EXISTS(SELECT 1 FROM event_idempotency WHERE request_id = $1) {
    return existing_event_id;
}

-- After insert
INSERT INTO event_idempotency (request_id, event_id, created_at)
VALUES ($1, $2, NOW());
```

**Expected**: Safe retries, no duplicate data

---

### 10. Event Streaming (Kafka/Pub-Sub)
**Impact**: Real-time updates to clients
**Complexity**: High

Idea:
```rust
// When event is inserted
async fn post_sync_events(...) {
    let event = insert_event(...).await?;
    
    // Publish to Kafka/RabbitMQ
    event_bus.publish("events", &event).await?;
    
    // Clients listening to WebSocket get real-time updates
    broadcast_tx.send(event).ok();
}
```

**Expected**: Real-time sync across clients

---

### 11. Projection Versioning & Migration
**Impact**: Handle event schema changes
**Complexity**: High

Problem: event_data structure changes, old events have old format

Solution:
```rust
#[derive(Deserialize)]
pub struct EventData {
    #[serde(with = "legacy_contact_name")]
    pub contact_name: String,  // Handle renamed field
}

mod legacy_contact_name {
    pub fn deserialize<'de, D>(deserializer: D) -> Result<String, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        // Try new field name first, fall back to old
        #[derive(Deserialize)]
        struct Helper {
            #[serde(alias = "name")]
            contact_name: Option<String>,
        }
        
        let h = Helper::deserialize(deserializer)?;
        Ok(h.contact_name.unwrap_or_default())
    }
}
```

**Expected**: Handle event schema evolution safely

---

### 12. Parallel Event Processing (Per-Aggregate)
**Impact**: Faster rebuild for independent aggregates
**Complexity**: High

Idea:
```rust
// Process contacts and transactions in parallel
let (contacts_result, transactions_result) = tokio::join!(
    process_contact_events(wallet_id, batch),
    process_transaction_events(wallet_id, batch)
);
```

**Expected**: Rebuild time: -30-50% (if I/O bound)

---

## Tier 4: Strategic Improvements (Long-term)

### 13. Read Model Separation
**Impact**: Dedicated read models for each query pattern
**Complexity**: Very High

Current: Projections serve both writes and reads
Better: Separate read models for different access patterns

```
Events → Projection (write model) → Read Models
                                  ├─ User View (by user)
                                  ├─ Contact View (by contact)
                                  ├─ Transaction View (paginated)
                                  └─ Dashboard View (aggregated)
```

**Expected**: Faster queries, independent optimization

---

### 14. Event Sourcing at Scale (1B+ events)
**Impact**: Handle enterprise-scale wallets
**Complexity**: Very High

Needed:
- Event sharding by date range
- Distributed snapshots
- Event archival & retention policies
- Cold storage (S3) for old events

---

### 15. CQRS Pattern (Complete)
**Impact**: Full separation of write and read logic
**Complexity**: Very High

Current: Commands trigger events → Events update projections

Complete:
- Commands → Event Store
- Events → Multiple Read Models in parallel
- Queries read from optimized Read Models
- Reconciliation job verifies consistency

---

## Recommended Priority Order

### Immediate (Next Sprint)
1. ✅ Last_event_id filtering (already planned - Phase 1)
2. ✅ Batch processing (already planned - Phase 2)
3. **Database indexing** (Tier 1.1) - 30 min
4. **Separate UNDO detection** (Tier 1.2) - 30 min
5. **Metrics & monitoring** (Tier 1.3) - 1 hour

**Impact**: Query performance +100x, visibility, ready for scale

### Soon After (2-3 Weeks)
6. **Snapshot optimization during rebuild** (Tier 2.1) - 3 hours
7. **Event statistics cache** (Tier 1.4) - 1 hour
8. **Async snapshot creation** (Tier 2.2) - 2 hours

**Impact**: Rebuild performance +100x, no blocking on snapshots

### Later (Monthly)
9. UNDO batch optimization (Tier 2.4)
10. Event deduplication (Tier 3.1)
11. Event streaming (Tier 3.2)

---

## Quick Impact Assessment

| Improvement | Implementation | Query Speed | Rebuild Speed | Storage | Memory |
|-------------|-----------------|-------------|---------------|---------|--------|
| Batch processing | ⭐ Trivial | - | 5x faster | - | ✅ -1000x |
| Indexing | ⭐ Easy | ✅ 100x | 10x | - | - |
| Snapshot rebuild | ⭐⭐ Medium | - | ✅ 100x | - | - |
| UNDO optimization | ⭐⭐ Medium | 2x | 2x | - | ✅ -50% |
| Async snapshots | ⭐⭐ Medium | - | - | - | - (latency) |
| Event compression | ⭐⭐ Medium | - | - | ✅ -70% | - |
| Event streaming | ⭐⭐⭐ Complex | - | - | - | - |

---

## Decision: What Should Be Done Now?

### Must Do (Blocking scale):
1. ✅ Batch processing (Phase 2 planned)
2. **Database indexing** (30 min)
3. **Separate UNDO detection** (30 min)

### Should Do (2-3 hours total):
4. **Metrics & monitoring** (visibility)
5. **Event statistics cache** (instant counts)
6. **Async snapshot creation** (latency)

### Could Do Later (if needed):
7. Snapshot optimization
8. UNDO batch optimization
9. Event compression

---

## Questions to Answer

1. **Scale target**: What's max events per wallet we need to support?
   - 1M: Current solution fine
   - 10M: Need snapshot rebuild
   - 100M+: Need event archival

2. **Performance target**: What's acceptable rebuild time?
   - <1s: Use snapshots every 10 events
   - <10s: Batching enough
   - <1min: No rush

3. **Real-time requirement**: Do clients need live updates?
   - If yes: Need event streaming
   - If no: Polling is fine

4. **Storage constraint**: Database size acceptable?
   - If constrained: Need compression/archival
   - If abundant: Keep everything
