# When Each Optimization Applies

**Main question this file answers:** When is Phase 1 used vs Phase 2 vs Snapshots? How do they work together?

---

## Three Scenarios

### Scenario 1: Normal Sync (Most Common)

**Trigger:** New events arrive from client

**What happens:**
```
1. Check max_processed_id (last event we saw)
2. Query: WHERE id > max_processed_id  ← Phase 1!
3. Load only NEW events (small batch)
4. Apply to projections
5. Save new max_processed_id
```

**Memory:** Always small (100 new events = 1MB)
**Optimization:** Phase 1 (last_event_id filtering)
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
3. Find snapshot BEFORE event #500
4. Restore snapshot (say, at event #400)
5. Load only events #401-#1,000,000
6. Apply in batches (Phase 2)
7. Filter out UNDO and event #500
8. Create NEW snapshot (safeguard for future UNDOs)
```

**Memory:** Snapshot (~1MB) + 1 batch of events (~2MB) = ~3MB
**Optimization:** Snapshots (step back) + Phase 2 (batch process remaining)
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
**Optimization:** Phase 2 (batch processing)
**Status:** ✅ Bounded memory (never exceed 1 batch size)

---

## Decision Tree

```
Event arrives at sync handler
  │
  ├─ Is it an UNDO event?
  │  │
  │  YES ──→ Clear projections
  │       ├─ Find snapshot BEFORE undone event
  │       ├─ Restore snapshot
  │       ├─ Apply remaining events in batches (Phase 2)
  │       └─ Memory: snapshot + 1 batch = ~3MB ✓
  │
  └─ NO (normal event)
     │
     ├─ Has max_processed_id set? (from last sync)
     │  │
     │  YES ──→ Query: WHERE id > max_processed_id (Phase 1)
     │       └─ Memory: always small ✓
     │
     └─ NO (cold start)
        │
        ├─ Count events
        │  │
        ├─ If count < 5000: Load all (safe)
        │  └─ Memory: ~50MB ✓
        │
        └─ If count >= 5000: Use batch loop (Phase 2)
           └─ Memory: 1 batch = ~2MB ✓
```

---

## The Complete Picture

**Three safety nets work together:**

1. **Phase 1 (Normal operation)**
   - `last_event_id` filtering
   - Only load new events
   - Memory = event count since last sync (always small)

2. **Phase 2 (Batching)**
   - When we must load many events, batch them (1000 at a time)
   - Memory = 1 batch + snapshot = ~3MB max

3. **Snapshots (UNDO recovery)**
   - Created after every UNDO event
   - Lets us "step back" to a known good state
   - Process only events after snapshot

**Result:** Memory is ALWAYS bounded (< 50MB for any wallet size)

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

## Common Misconceptions

### ❌ "Snapshots prevent loading events"

**Wrong.** Snapshots prevent loading ALL 1M events at once.

**Right.** Snapshots let us skip events 1-400,000 and only load/batch events 400,001-1,000,000.

### ❌ "Phase 2 batching means we use it for every sync"

**Wrong.** Phase 1 (last_event_id) handles normal syncs. Phase 2 only triggers for cold starts or UNDO rebuilds (rare).

**Right.** Normal syncs are fast because Phase 1 filters to only new events. Phase 2 is a safety net for rebuilds.

### ❌ "If memory is bounded, why do we have three optimizations?"

**Wrong.** Redundancy is wasteful.

**Right.** Each optimization handles a different scenario:
- Phase 1: Normal operation (most common)
- Phase 2: Batching when we must load many (rare)
- Snapshots: UNDO recovery (rare but critical)

Together they ensure **any scenario stays memory-safe**.

---

Next: [../04-permissions-and-undo/01-undo-events.md](../04-permissions-and-undo/01-undo-events.md) — How UNDO events work and how snapshots prevent OOM
