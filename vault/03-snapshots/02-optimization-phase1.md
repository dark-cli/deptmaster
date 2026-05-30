# Snapshot Optimization: Phase 1 (Tracking)

**Main question this file answers:** How does Phase 1 (last_event_id tracking) prevent reprocessing?

---

## The Problem Phase 1 Solves

Every time you sync, the system might reprocess events it's already processed.

```
First sync: Process events 1-1000
         ↓
Second sync: Process events 1-1000 again? (redundant!)
         ↓
Memory: 1000 events × 1000 syncs = 1,000,000 events in RAM
```

**Result:** O(n²) memory growth—catastrophic for large wallets!

## Phase 1 Solution: last_event_id Tracking

Track **the last event ID that was already processed** and only process new events.

```
First sync: Process events 1-1000
  Save: last_event_id = 1000
         ↓
Second sync: Load last_event_id = 1000
  Process only events 1001-2000 (skip 1-1000, already done)
  Save: last_event_id = 2000
         ↓
Third sync: Load last_event_id = 2000
  Process only events 2001-3000 (skip 1-2000, already done)
```

**Result:** Memory stays constant (only 1000 events per sync, not cumulative)

## How Phase 1 Works

### Step 1: Create Snapshot with Event ID

After processing events, save a snapshot that includes **which event was last processed**:

```sql
INSERT INTO snapshots (wallet_id, aggregate_type, last_event_id, state, created_at)
VALUES (
  'wallet-123',
  'contact',
  1000,  -- ← Last event processed
  '{"contacts_projection": [alice, bob, ...]}',
  NOW()
)
```

### Step 2: On Next Sync, Load last_event_id

```sql
SELECT last_event_id FROM snapshots
WHERE wallet_id = 'wallet-123'
AND aggregate_type = 'contact'
ORDER BY created_at DESC LIMIT 1
-- Result: 1000
```

### Step 3: Only Load New Events

```sql
SELECT * FROM events
WHERE wallet_id = 'wallet-123'
AND id > 1000  -- Skip already-processed events
ORDER BY id ASC
-- Result: events 1001-2000 only
```

### Step 4: Process Only New Events

```
for event in events_1001_to_2000:
  event.apply_self()
```

### Step 5: Update Snapshot with New last_event_id

```sql
UPDATE snapshots SET last_event_id = 2000
WHERE wallet_id = 'wallet-123'
AND aggregate_type = 'contact'
```

## Memory Impact

### Without Phase 1 (O(n²) Growth)
```
Sync 1: Load 1,000 events = 1,000 events in memory
Sync 2: Load 1,000-2,000 = 2,000 events in memory
Sync 3: Load 1,000-3,000 = 3,000 events in memory
...
Sync 1000: Load 1,000-1,000,000 = 1,000,000 events in memory ❌ OOM!
```

### With Phase 1 (O(n) Constant)
```
Sync 1: Load 1,000 events = 1,000 events in memory
Sync 2: Load only 1,001-2,000 = 1,000 events in memory
Sync 3: Load only 2,001-3,000 = 1,000 events in memory
...
Sync 1000: Load only 999,001-1,000,000 = 1,000 events in memory ✅ Constant!
```

**Result:** 100,000x memory reduction for large wallets!

## The last_event_id Index

The `last_event_id` is the key to Phase 1. It acts as a **watermark**:

```
events table:
id | event_data
1  | ContactCreated alice
2  | TransactionCreated ...
...
1000 | ContactUpdated bob
     ↑
  last_event_id = 1000 (saved in snapshot)

Next sync: Start from id > 1000
     ↓
1001 | ContactCreated charlie
1002 | ...
```

## Phase 1 Limitations

Phase 1 solves the **reprocessing problem** but doesn't solve the **batch size problem**:

```
What if you have 1 million unprocessed events?
Load events 1-1,000,000
Process each one
Memory: Still 1 GB! (problem not solved)
```

**Solution:** Phase 2 (batch processing) handles this.

## Phase 1 vs. No Optimization (Comparison)

| Metric | No Optimization | Phase 1 |
|---|---|---|
| Sync 1 (1K events) | 1 GB | 10 MB |
| Sync 10 (1K events each) | 10 GB | 10 MB |
| Sync 100 (1K events each) | 100 GB ❌ | 10 MB |
| Sync 1000 (1K events each) | 1 TB ❌ | 10 MB |

**Phase 1 benefit:** Constant memory, scales indefinitely!

## When Phase 1 Kicks In

Phase 1 helps in this scenario:
```
Wallet has 100,000 events already
User syncs 1,000 new events
Without Phase 1: Load 101,000 events (OOM)
With Phase 1: Load only 1,000 events ✅
```

## UNDO Events and Phase 1

**Question:** When UNDO events are present, does Phase 1 still work?

**Answer:** No—UNDO triggers a full rebuild.

```
UNDO event arrives
         ↓
Clear all projections
         ↓
Rebuild from event 1 (ignore last_event_id)
         ↓
Process all events (not just new ones)
         ↓
Update last_event_id when done
```

UNDO requires processing all events because:
- An undone event changes the entire history
- You can't just process "new" events and expect correct state
- You need to know which old events are undone

After rebuild completes, Phase 1 kicks in again for subsequent syncs.

---

Next: [03-optimization-phase2.md](03-optimization-phase2.md) — Understand Phase 2 optimization (batching)
