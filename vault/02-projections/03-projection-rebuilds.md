# Projection Rebuilds

**Main question this file answers:** When and why do we rebuild projections from scratch?

---

## What Is a Rebuild?

A **rebuild** is when we:
1. Delete all projection data
2. Reprocess all events from the beginning
3. Rebuild projection tables from scratch

```
contacts_projection: [alice, bob, charlie]
         ↓
    DELETE all rows
         ↓
contacts_projection: []
         ↓
Reprocess all events
  Event 1: ContactCreated alice → INSERT alice
  Event 2: ContactCreated bob → INSERT bob
  Event 3: ContactCreated charlie → INSERT charlie
         ↓
contacts_projection: [alice, bob, charlie]
```

## When Do Rebuilds Happen?

### Reason 1: UNDO Events (Most Important)

When an UNDO event is present, rebuilds are **required**.

**Why?** Because undoing one past event affects all computations afterward.

Example:
```
Event 1: ContactCreated alice
Event 2: ContactUpdated alice (name: "Alice Smith")
Event 3: UNDO { undone_event_id: 1 }
         ↓
Rebuild from scratch:
  Event 1: (skipped, it's undone)
  Event 2: ContactUpdated alice (but alice doesn't exist!) ← ERROR
         ↓
Solution: Rebuild to handle skipped events correctly
```

### Reason 2: Data Corruption

If a projection table gets corrupted, rebuild to fix it.

```
contacts_projection has garbage data
         ↓
DELETE all rows
         ↓
Reprocess events
         ↓
Clean state restored
```

### Reason 3: Schema Changes

If the projection table schema changes, rebuild to repopulate with new columns.

## Rebuild Process

### Step 1: Detect UNDO Events

When syncing, check if any UNDO events are present:

```rust
let has_undo_events = events.iter()
    .any(|e| e.event_type == "UNDO");
```

### Step 2: Clear All Projections (if needed)

If UNDO is present, delete all projection data:

```rust
if has_undo_events {
    DomainEvent::clear_aggregate_type(pool, AggregateType::Contact, wallet_id).await?;
    DomainEvent::clear_aggregate_type(pool, AggregateType::Transaction, wallet_id).await?;
    DomainEvent::clear_aggregate_type(pool, AggregateType::Permission, wallet_id).await?;
}
```

This clears:
- `contacts_projection`
- `transactions_projection`
- `wallet_users` (keeping owner)
- `user_groups`, `contact_groups`

### Step 3: Process All Events

Reprocess ALL events from the beginning:

```rust
// Load all events (or from latest snapshot if available)
let all_events = db.get_all_events(wallet_id).await?;

for event in all_events {
    // Skip undone events
    if should_skip_event(&event) {
        continue;
    }
    
    // Apply event to projections
    event.apply_self(pool, wallet_id).await?;
}
```

### Step 4: Verify State

After rebuild, projections should match events:
- Every ContactCreated event → contact in contacts_projection
- Every TransactionCreated event → transaction in transactions_projection
- No ContactDeleted events should have rows in contacts_projection

## Rebuild with Snapshots

**Without snapshots (slow):**
```
Rebuild 1 million events:
  1. Load all 1 million events into memory
  2. Process each one
  3. Takes 30+ seconds, uses 1 GB RAM
```

**With snapshots (fast):**
```
Latest snapshot: at event 500,000

Rebuild:
  1. Restore from snapshot (loads precomputed state)
  2. Load only recent events (500,001-1,000,000)
  3. Process only those
  4. Takes 2 seconds, uses 50 MB RAM
```

(See Chapter 03: Snapshots for details)

## Types of UNDO Events

### UNDO for Contact Events
```json
{
  "event_type": "UNDO",
  "event_data": {
    "undone_event_id": 100  // Undo whatever event 100 was
  }
}
```

### UNDO for Transaction Events
```json
{
  "event_type": "UNDO",
  "event_data": {
    "undone_event_id": 200
  }
}
```

### UNDO for Permission Events
```json
{
  "event_type": "UNDO",
  "event_data": {
    "undone_event_id": 300
  }
}
```

**Key insight:** UNDO works the same way for all event types. During rebuild, we simply skip any event with `undone_event_id` in an UNDO event.

## Clearing Permission Tables During Rebuild

Permission tables have special handling (since they're not true projections):

```rust
AggregateType::Permission => {
    // Clear user memberships
    sqlx::query("DELETE FROM user_group_members WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(pool)
        .await?;
    
    // Clear user groups
    sqlx::query("DELETE FROM user_groups WHERE wallet_id = $1 AND system = false")
        .bind(wallet_id)
        .execute(pool)
        .await?;
    
    // Clear contact groups and members
    sqlx::query("DELETE FROM contact_group_members WHERE group_id IN (
        SELECT id FROM contact_groups WHERE wallet_id = $1 AND system = false
    )")
    .bind(wallet_id)
    .execute(pool)
    .await?;
    
    sqlx::query("DELETE FROM contact_groups WHERE wallet_id = $1 AND system = false")
        .bind(wallet_id)
        .execute(pool)
        .await?;
    
    // Keep wallet_users but remove non-owners
    sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND role != 'owner'")
        .bind(wallet_id)
        .execute(pool)
        .await?;
    
    Ok(())
}
```

**Why keep owners?** The owner is special—they can't be removed from the wallet. Permission events shouldn't be able to undo that.

## Idempotency During Rebuilds

Rebuilds are **idempotent**: running them multiple times produces the same result.

This is safe because:
1. Events are immutable (same events produce same result)
2. Projection clearing is deterministic
3. Handler logic doesn't depend on prior state

So if a rebuild is interrupted and restarted, the result is the same.

## Performance Implications

**Small wallet (100 events):**
- Rebuild time: <100ms
- Memory: <1MB

**Medium wallet (100,000 events):**
- Rebuild time: 2-5 seconds
- Memory: 50-100MB

**Large wallet (1,000,000+ events):**
- Without snapshot: >30 seconds, >1GB RAM ❌
- With snapshot: 2-5 seconds, 50-100MB RAM ✅

(This is why Chapter 03: Snapshots is important)

---

Next: [../03-snapshots/01-why-snapshots.md](../03-snapshots/01-why-snapshots.md) — Understand the snapshot optimization strategy
