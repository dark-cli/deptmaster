# Snapshot Optimization: Phase 2 (Batching)

**Main question this file answers:** How does Phase 2 (batch processing) keep memory bounded?

---

## The Problem Phase 2 Solves

Phase 1 prevents **reprocessing already-processed events**, but it doesn't help when you have a **large backlog of new events**:

```
Wallet has 100,000 events (already processed)
User syncs 500,000 new events
Phase 1 says: load events 100,001-600,000
         ↓
Load all 500,000 at once
Process all at once
Memory: 5 GB ❌ OOM!
```

Phase 2 solves this by **processing events in batches**.

## Phase 2 Solution: Batch Processing

Instead of loading all events at once, load them in **configurable batches** (default: 1,000 events).

```
500,000 new events to process
         ↓
Batch 1: Load events 100,001-101,000 (1,000 events)
  Process all 1,000
  Memory: 10 MB ✅
         ↓
Batch 2: Load events 101,001-102,000 (1,000 events)
  Process all 1,000
  Memory: 10 MB ✅
         ↓
... (500 batches total) ...
         ↓
Batch 500: Load events 599,001-600,000 (1,000 events)
  Process all 1,000
  Memory: 10 MB ✅
         ↓
Total memory: 10 MB (not 5 GB!)
```

## How Phase 2 Works

### Batch Processing Loop

```rust
let batch_size = 1000;
let mut last_event_id = get_last_snapshot_event_id(wallet_id);
let total_events = get_total_event_count(wallet_id);

while last_event_id < total_events {
    // Load one batch
    let events = db.load_events(wallet_id, last_event_id, batch_size).await?;
    
    // Process all in batch
    for event in events {
        event.apply_self(pool, wallet_id).await?;
    }
    
    // Save progress
    last_event_id += events.len();
    save_snapshot(wallet_id, last_event_id).await?;
}
```

### Step-by-Step Example

**Scenario:** 5,000 events, batch size = 1,000

```
Initial: last_event_id = 0

Iteration 1:
  Load events 1-1000
  Process all 1000
  Memory: 10 MB ✅
  Save: last_event_id = 1000
  
Iteration 2:
  Load events 1001-2000
  Process all 1000
  Memory: 10 MB ✅
  Save: last_event_id = 2000
  
Iteration 3:
  Load events 2001-3000
  Process all 1000
  Memory: 10 MB ✅
  Save: last_event_id = 3000
  
Iteration 4:
  Load events 3001-4000
  Process all 1000
  Memory: 10 MB ✅
  Save: last_event_id = 4000
  
Iteration 5:
  Load events 4001-5000
  Process all 1000
  Memory: 10 MB ✅
  Save: last_event_id = 5000

Done!
Total time: 5 seconds
Max memory: 10 MB (constant, not 50 MB)
```

## Memory Benefits

### Batch Size Impact

Memory is proportional to **batch size**, not total events:

```
Batch size = 100 events
  Memory: 1 MB
  Processing 1 million events: still 1 MB at any time
  
Batch size = 1000 events
  Memory: 10 MB
  Processing 1 million events: still 10 MB at any time
  
Batch size = 10,000 events
  Memory: 100 MB
  Processing 1 million events: still 100 MB at any time
```

**Key insight:** Doubling the batch size doubles memory, but halves the number of iterations.

## Default Batch Size

The system defaults to **batch_size = 1000**:

```
Per event: ~10 KB
Batch size: 1000 events
Memory per batch: 10 MB (acceptable)
```

Tuning:
```
- If memory is tight: batch_size = 500 (uses 5 MB)
- If rebuilds are slow: batch_size = 5000 (uses 50 MB)
- If rebuilds are very slow: batch_size = 10000 (uses 100 MB)
```

## Phase 1 + Phase 2 Combined

The two phases work together:

```
Phase 1: "Skip already-processed events"
         Load events 100,001-600,000 only
         
Phase 2: "Process in manageable batches"
         Batch 1: events 100,001-101,000
         Batch 2: events 101,001-102,000
         ...
         Batch 500: events 599,001-600,000
```

**Result:** Constant memory, handles any wallet size!

## Snapshot Creation During Batching

Snapshots are updated after **each batch**:

```
Before Batch 1: snapshot.last_event_id = 100,000
After Batch 1:  snapshot.last_event_id = 101,000
After Batch 2:  snapshot.last_event_id = 102,000
...
After Batch 500: snapshot.last_event_id = 600,000
```

**Benefit:** If processing is interrupted, you resume from the last saved batch (not from the beginning).

## Example: Restaurant Chain Rebuild

Imagine a restaurant chain syncing 5 years of transactions:

**Without batching:**
```
Load all 5 million events
Memory: 50 GB ❌ OOM!
```

**With Phase 1 + 2:**
```
Phase 1: Skip already-processed (say, 4 million)
  Process only 1 million new events
  
Phase 2: Batch the 1 million
  Batch size: 1000
  Iterations: 1000
  Memory: 10 MB ✅
  Time: 5 seconds ✅
```

## Batch Processing Guarantees

### All-or-Nothing Batches

Each batch is either fully processed or fully skipped:
- If batch processing fails, snapshot isn't updated
- Next attempt starts from same batch
- No partial batches

### Deterministic Processing

Same events always produce same result (idempotency):
- Process same batch twice → same result
- Safe to retry interrupted batches

### Atomic Snapshots

Snapshot updates are atomic:
- Snapshot saved with updated last_event_id
- All-or-nothing: either saved or not saved
- No corrupt snapshots

## Monitoring Batch Processing

In logs, you'd see:
```
Processing wallet-123
Batch 1/500: events 100001-101000 (10 MB, 200ms)
Batch 2/500: events 101001-102000 (10 MB, 180ms)
Batch 3/500: events 102001-103000 (10 MB, 220ms)
...
Batch 500/500: events 599001-600000 (10 MB, 190ms)
Total: 5 minutes, 500 MB processed
```

## UNDO Events and Phase 2

When UNDO events are present:

```
Full rebuild triggered
         ↓
Phase 1 disabled (process all events, not just new ones)
Phase 2 enabled (batch them)
         ↓
Batch 1: events 1-1000 (some might be undone)
Batch 2: events 1001-2000
...
Batch 500: events 499001-500000
```

UNDO + batching: rebuild is fast and memory-efficient.

## Tags
`#optimization` `#phase-2` `#batching` `#batch-processing` `#memory-bounds`

## Related Topics
- **Phase 1 (tracking):** [02-optimization-phase1.md](02-optimization-phase1.md)
- **Why snapshots:** [01-why-snapshots.md](01-why-snapshots.md)
- **Snapshot tables:** [04-snapshot-tables-schema.md](04-snapshot-tables-schema.md)
- **UNDO with batching:** [../04-permissions-and-undo/01-undo-events.md](../04-permissions-and-undo/01-undo-events.md)
- **Memory bounds analysis:** [../07-advanced-topics/01-memory-bounds-analysis.md](../07-advanced-topics/01-memory-bounds-analysis.md)
- **Performance benchmarks:** [../07-advanced-topics/03-performance-benchmarks.md](../07-advanced-topics/03-performance-benchmarks.md)
- **Glossary:** [../99-reference/01-glossary.md](../99-reference/01-glossary.md) (see: batch processing, memory bounds, phase 2)

---

Next: [04-snapshot-tables-schema.md](04-snapshot-tables-schema.md) — Understand snapshot table structure
