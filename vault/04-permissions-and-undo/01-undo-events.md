# UNDO Events

**Main question this file answers:** What are UNDO events and how do they work?

---

## What Is an UNDO Event?

An **UNDO event** marks another event as "never happened" without deleting the history.

```
Event 100: TransactionCreated { amount: 50, contact: alice }
Event 101: UNDO { undone_event_id: 100 }

Result: As if event 100 never happened, but the history is preserved
```

## Why Not Just Delete?

**Why use UNDO instead of deleting the event from the database?**

Reasons:

### Reason 1: Immutable History
Events are immutable. Once written, they stay. UNDO respects this:
- Event 100: TransactionCreated (still in database)
- Event 101: UNDO (marks it as undone, also in database)

Both are preserved.

### Reason 2: Auditability
You can see the complete history:
- What transaction was created
- When it was created
- When it was undone
- By whom (implicit in the event)

### Reason 3: Reversibility
You can reverse an UNDO if needed:
- Add another UNDO event to undo the undo
- Or replay from a snapshot before the UNDO

### Reason 4: Simplicity
Just write a new event instead of updating/deleting old ones.

## How UNDO Works

### Step 1: Create UNDO Event

When user requests "undo transaction 100":

```json
{
  "event_type": "UNDO",
  "aggregate_type": "transaction",  // Can be any aggregate type
  "event_data": {
    "undone_event_id": 100
  }
}
```

### Step 2: Store UNDO Event

Insert into events table like any other event:

```sql
INSERT INTO events (aggregate_type, event_type, event_data, ...)
VALUES ('transaction', 'UNDO', '{"undone_event_id": 100}', ...)
```

### Step 3: Detect UNDO During Processing

When syncing events, check if any UNDO events are present:

```rust
let has_undo = events.iter()
    .any(|e| e.event_type == "UNDO");
```

### Step 4: Trigger Full Rebuild

If UNDO is present, **clear all projections and rebuild from scratch**:

```rust
if has_undo {
    // Clear all projections
    DomainEvent::clear_aggregate_type(pool, AggregateType::Contact, wallet_id).await?;
    DomainEvent::clear_aggregate_type(pool, AggregateType::Transaction, wallet_id).await?;
    DomainEvent::clear_aggregate_type(pool, AggregateType::Permission, wallet_id).await?;
    
    // Reprocess all events, skipping undone ones
    let all_events = db.get_all_events(wallet_id).await?;
    for event in all_events {
        if should_skip_because_of_undo(&event) {
            continue;
        }
        event.apply_self(pool, wallet_id).await?;
    }
}
```

### Step 5: Result

Transaction 100 is not in projections (it was undone), but it's still in the events table (audit trail).

## UNDO Examples

### Contact UNDO
```
Event 50: ContactCreated { name: "Alice" }
Event 51: UNDO { undone_event_id: 50 }

Result: Alice is not in contacts_projection
        But events 50 and 51 are in events table
```

### Transaction UNDO
```
Event 100: TransactionCreated { amount: 50, contact: bob }
Event 101: UNDO { undone_event_id: 100 }

Result: Transaction is removed from transactions_projection
        Bob's balance is recalculated (no longer owes $50)
        But both events are preserved
```

### Permission UNDO
```
Event 200: WalletUserAdded { user_id: alice, role: admin }
Event 201: UNDO { undone_event_id: 200 }

Result: Alice is removed from wallet_users
        wallet_users table rebuilt without her
        But both events are preserved
```

## UNDO Chain Example

What if you undo an undo?

```
Event 100: TransactionCreated { amount: 50 }
Event 101: UNDO { undone_event_id: 100 }
Event 102: UNDO { undone_event_id: 101 }

Processing:
1. Event 100: Add transaction
2. Event 101: UNDO 100 (skip event 100)
3. Event 102: UNDO 101 (skip event 101, but that means undo the undo!)

Result: Transaction IS in projections (undo was undone)
```

The algorithm: **for each event, check if it's in any UNDO event's undone_event_id**.

```rust
fn should_skip_event(event_id: i64, all_events: &[DomainEvent]) -> bool {
    all_events.iter()
        .filter(|e| e.event_type == "UNDO")
        .any(|e| e.undone_event_id == event_id)
}
```

## Why UNDO Triggers Full Rebuild

**Question:** Why rebuild all projections when UNDO is present?

**Answer:** Because undoing one event affects **all future state**.

### Example: Why Full Rebuild Is Needed

```
Event 1: TransactionCreated { contact: alice, amount: 50 }
Event 2: TransactionUpdated { contact: alice, amount: 60 }
Event 3: ContactUpdated { name: alice, email: "new@example.com" }
Event 4: UNDO { undone_event_id: 1 }

If we only process new events after UNDO:
  Event 2: TransactionUpdated... but transaction doesn't exist! ❌
  Event 3: ContactUpdated works fine

If we rebuild from scratch:
  Event 1: Skip (undone)
  Event 2: Skip (transaction doesn't exist, nothing to update)
  Event 3: ContactUpdated works fine ✅
```

Only a full rebuild can correctly handle dependent events.

## UNDO and Snapshots

UNDO events interact with snapshots:

### Without Snapshot
```
Full rebuild from event 1
Time: 30+ seconds
Memory: 1 GB
```

### With Snapshot
```
Latest snapshot at event 500,000
UNDO arrives (marking an old event)
         ↓
Rebuild from event 1 (not from snapshot, since UNDO affects old state)
Time: 30+ seconds (same as without snapshot) ⚠️
Memory: 1 GB (same as without snapshot) ⚠️
```

**Important:** When UNDO events are present, snapshots don't help (you still have to rebuild from the beginning).

## UNDO Frequency

**Question:** How often do UNDO events happen?

**Answer:** Depends on user behavior. Typically:
- Most syncs: 0 UNDO events (frequent)
- Some syncs: 1-5 UNDO events (occasional)
- Rare syncs: 10+ UNDO events (after a user reviews and corrects many entries)

When UNDO is common, consider:
- Improving the app UX to reduce corrections
- Optimizing rebuild performance (Phase 2 batching helps)

## UNDO vs. DELETE Events

**Question:** Why have both DELETE events and UNDO events?

**Answer:** Different purposes:

- **DELETE events:** User actively deletes something (removes from projections immediately)
- **UNDO events:** User wants to undo a past action (requires rebuild)

Example:
```
User adds transaction (Event 1)
User later deletes transaction (Event 2)
  → DELETE event applied immediately
  → Transaction removed from projections

vs.

User adds transaction (Event 1)
Later user wants to undo (Event 2)
  → UNDO event triggers full rebuild
  → Event 1 is skipped during rebuild
```

Both lead to the same result (transaction not in projections), but UNDO is used for the "historical correction" use case.


Next: [02-permission-events.md](02-permission-events.md) — Understand permission events and how they differ
