# How Memory Stays Bounded: Three Architectural Optimizations

**Main question this file answers:** How do incremental syncing, event batching, and snapshots work together to keep memory bounded?

---

## Three Operational Scenarios

### Scenario 1: Normal Sync (Most Common)

**Trigger:** New events arrive from client

**What happens:**
```
1. Check max_processed_id (last event we processed)
2. Query: WHERE id > max_processed_id  ← Last_event_id optimization
3. Load only NEW events (small batch)
4. Apply to projections
5. Save new max_processed_id
```

**Memory:** Always small (100 new events = 1MB)
**Architecture:** Last_event_id optimization (incremental sync)
**Status:** ✅ Bounded memory (constant)

**Example:**
```
Last sync: processed events 1-1000
New sync: only load events 1001-1050
Apply only new ones
```

---

### Scenario 2: UNDO Event (Rare but Important)

**Trigger:** Client sends UNDO event

**What happens:**
```
1. Event received: "UNDO event #500 (in 1M event wallet)"
2. Clear projections (to rebuild from clean state)
3. Find snapshot BEFORE event #500  ← Snapshot checkpointing
4. Restore snapshot (say, at event #400)
5. Load only events #401-#1,000,000
6. Apply in batches (Event batching)  ← 1000-event batches
7. Filter out UNDO and event #500
8. Create NEW snapshot (safeguard for future UNDOs)
```

**Memory:** Snapshot (~1MB) + 1 batch of events (~2MB) = ~3MB
**Architecture:** Snapshot checkpointing + Event batching
**Status:** ✅ Bounded memory (never loads full wallet)

**Example:**
```
1M event wallet
UNDO event at #500,000
  ↓
Find snapshot at event #400,000
  ↓
Restore snapshot state (1MB)
  ↓
Load events #400,001-#1,000,000 in 1000-event batches
  ↓
Apply each batch, discard after (keep 2MB in RAM)
  ↓
Reach final state
Memory never exceeds snapshot + 1 batch = ~3MB
```

---

### Scenario 3: Cold Start / Full Rebuild (Very Rare)

**Trigger:** Brand new wallet, OR all projections corrupted

**What happens:**
```
1. No last_event_id (projections empty)
2. Query: WHERE id > 0  ← loads ALL events
3. If count > 5000: Use batch fallback loop
4. Otherwise: Load all (safe for small wallets)
```

**Memory:** Depends on batch size (~2MB per batch)
**Architecture:** Event batching (1000-event chunks for large wallets)
**Status:** ✅ Bounded memory (never exceed 1 batch size)

---

## Decision Tree

```
Event arrives at sync handler
  │
  ├─ Is it an UNDO event?
  │  │
  │  YES ──→ Clear projections
  │       ├─ Find snapshot BEFORE undone event  (Snapshot checkpointing)
  │       ├─ Restore snapshot
  │       ├─ Apply remaining events in batches  (Event batching)
  │       └─ Memory: snapshot + 1 batch = ~3MB ✓
  │
  └─ NO (normal event)
     │
     ├─ Has max_processed_id set? (from last sync)
     │  │
     │  YES ──→ Query: WHERE id > max_processed_id  (Last_event_id optimization)
     │       └─ Memory: always small ✓
     │
     └─ NO (cold start)
        │
        ├─ Count events
        │  │
        ├─ If count < 5000: Load all (safe)
        │  └─ Memory: ~50MB ✓
        │
        └─ If count >= 5000: Use batch loop  (Event batching)
           └─ Memory: 1 batch = ~2MB ✓
```

---

## The Complete Architecture

**Three optimizations work together to bound memory:**

1. **Last_event_id optimization (Incremental syncing)**
   - Tracks the last processed event ID
   - Next sync: `WHERE id > max_processed_id`
   - Only new events loaded, old ones never touched
   - Memory = new events since last sync (always small)

2. **Event batching (Bounded processing)**
   - When rebuilding, process events in 1000-event chunks
   - Never load entire wallet into RAM
   - Memory = 1 batch + snapshot = ~3MB max

3. **Snapshot checkpointing (UNDO recovery)**
   - Created after every UNDO event
   - Provides a checkpoint: "state at event N"
   - On UNDO: restore snapshot, process only events after it
   - Avoids reprocessing events before the UNDO

**Result:** Memory is ALWAYS bounded (< 50MB regardless of wallet size)

---

## Why This Matters

**Without these optimizations:**
- 1M event wallet + UNDO = load 1M events = 1GB RAM = OOM ❌

**With these optimizations:**
- 1M event wallet + UNDO = restore snapshot + batch process = 3MB RAM ✓
- 10M event wallet + UNDO = restore snapshot + batch process = 3MB RAM ✓
- 100M event wallet + UNDO = restore snapshot + batch process = 3MB RAM ✓

**Wallet size is irrelevant to memory usage!**

---

## Common Misconceptions (Avoid These)

### ❌ "Snapshots prevent loading events"

**Wrong.** Snapshots prevent loading ALL 1M events at once.

**Correct.** Snapshots let us skip events 1-400,000 and only load/batch events 400,001-1,000,000.

### ❌ "Event batching is used for every sync"

**Wrong.** Last_event_id optimization handles normal syncs. Batching only kicks in for cold starts or UNDO rebuilds (rare).

**Correct.** Normal syncs are fast because last_event_id filters to only new events. Batching is a safety net for rebuilds.

### ❌ "Why do we need three optimizations if memory is bounded?"

**Wrong.** They're redundant.

**Correct.** Each architecture handles a different scenario:
- **Last_event_id optimization:** Normal operation (most common, always small memory)
- **Event batching:** Cold starts/rebuilds (rare, memory = 1 batch)
- **Snapshot checkpointing:** UNDO recovery (rare but critical, memory = snapshot + 1 batch)

Together they ensure **any scenario stays memory-safe without waste**.

---

Next: [../04-permissions-and-undo/01-undo-events.md](../04-permissions-and-undo/01-undo-events.md) — How UNDO events work and how snapshots prevent OOM
