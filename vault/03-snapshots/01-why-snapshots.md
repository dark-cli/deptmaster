# Why Snapshots?

**Main question this file answers:** Why do we need snapshots? What problem do they solve?

---

## The Problem: Memory Explosion

When rebuilding projections, you need to **process all events from the beginning**.

### Example: Small Wallet (1,000 events)
```
Load events 1-1000
Process each one
Memory: 10 MB
Time: 100 ms
```

No problem.

### Example: Medium Wallet (100,000 events)
```
Load events 1-100,000
Process each one
Memory: 100 MB
Time: 1-2 seconds
```

Still okay.

### Example: Large Wallet (1,000,000+ events)
```
Load events 1-1,000,000
Process each one
Memory: 1-2 GB  ❌ OOM!
Time: 30+ seconds
```

**Problem:** Loading 1 million events into RAM causes out-of-memory errors!

## The Solution: Snapshots

A **snapshot** is a checkpoint: "Here's the state at event 500,000."

Instead of reprocessing all 1 million events:

```
Find latest snapshot: "state at event 500,000"
         ↓
Restore projections from snapshot
         ↓
Load only recent events (500,001-1,000,000)
         ↓
Process only those
         ↓
Memory: 50 MB ✅
Time: 2-3 seconds ✅
```

### Memory Math

**Without snapshots:**
- 1,000,000 events × ~1 KB per event = 1 GB RAM

**With snapshots:**
- Load snapshot (contains precomputed state)
- Load only 100,000 recent events × ~1 KB = 100 MB RAM

**Result:** 10x memory reduction!

## How Snapshots Work

### Step 1: Create Snapshot After Events

Every 1,000 events (configurable), create a snapshot:

```
Event 1: ContactCreated alice
Event 2: TransactionCreated ...
...
Event 1000: ContactUpdated bob
         ↓
Create snapshot:
  "At event 1000, state was:"
  {
    contacts_projection: [alice, bob, charlie, ...],
    transactions_projection: [100 transactions]
  }

Event 1001: ContactCreated charlie
Event 1002: ...
```

### Step 2: Use Snapshot on Rebuild

When rebuilding:

```
1. Find latest snapshot: "state at event 500,000"
2. Restore projections from that snapshot
3. Load events 500,001-1,000,000
4. Process only those
5. Reach current state
```

```
Timeline:
Event 1 ──────► Event 500,000 ──────► Event 1,000,000
                     ↑
                (Snapshot here)
                     ↓
            Restore and continue
```

## Example: Restaurant Debts

Imagine you're a restaurant tracking customer debts.

**Without snapshots:**
- 5 years of transactions = 1 million events
- Rebuild takes 30 seconds, uses 1 GB RAM

**With snapshots:**
- Snapshots created every 1,000 transactions
- Latest snapshot: "after 1 million transactions"
- Rebuild uses that snapshot
- Rebuild takes 1 second, uses 10 MB RAM

## When Snapshots Are Useful

### Scenario 1: Large Wallets
Wallets with 100,000+ events benefit greatly from snapshots.

### Scenario 2: Frequent Syncs
If projections are rebuilt often, snapshots reduce the work.

### Scenario 3: UNDO Events
When UNDO events trigger rebuilds, snapshots make them fast.

## Snapshot Trade-offs

### Storage Cost
```
snapshots table stores:
  - wallet_id
  - aggregate_type
  - last_event_id
  - state (JSON)
  
Per snapshot: ~1-10 MB
Stored per aggregate type: Contact, Transaction, Permission
Total: 3-30 MB per wallet

Acceptable trade-off for 10x memory reduction!
```

### Rebuild Overhead
```
With snapshots:
  1. Find latest snapshot (fast query)
  2. Restore from snapshot (deserialize JSON)
  3. Process recent events (fast)

Total overhead: <100ms
Worth it for 10x memory reduction!
```

## Snapshot Consistency

**Question:** Can snapshots become stale or inconsistent?

**Answer:** Only if you don't update them.

The system automatically:
1. Updates snapshots after every 1,000 events
2. Verifies snapshots match events during rebuild
3. Recreates snapshots if they're wrong

So snapshots stay correct automatically.

## Snapshot Lifecycle

```
Event 1-1000: Process events
         ↓
Create snapshot "state at event 1000"
         ↓
Event 1001-2000: Process events
         ↓
Create snapshot "state at event 2000" (old snapshot still exists)
         ↓
...eventually...
         ↓
Delete old snapshots (keep only last few)
```

The system keeps only recent snapshots to save space.

## What's Next?

Now that you understand why snapshots exist, the next chapters explain **how** they work:

- **Phase 1:** Tracking (last_event_id index prevents reprocessing)
- **Phase 2:** Batching (process events in 1,000-event batches to keep memory bounded)

---

Next: [02-optimization-phase1.md](02-optimization-phase1.md) — Understand Phase 1 optimization (tracking)
