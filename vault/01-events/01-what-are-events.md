# What Are Events?

**Main question this file answers:** What are events and why does the system use them instead of storing current state?

---

## Definition

An **event** is an immutable record of something that happened at a specific time.

Examples from the debt tracker:
- "Alice was added as a contact on 2024-06-01"
- "Alice borrowed $50 from Bob on 2024-06-02"
- "Charlie was granted admin access to my wallet on 2024-06-03"
- "That $50 transaction was a mistake—undo it on 2024-06-04"

Once written, events **never change**. This is the foundation of event sourcing.

## Events vs. Current State

### Traditional Approach (Current State Storage)

```
Database stores: "Alice owes Bob $30"

When Alice pays $20:
  UPDATE transactions SET amount = 10 WHERE ...

Problem: You lose the history
  - You don't know Alice originally owed $50
  - You can't answer "how much did Alice owe on Tuesday?"
  - If corruption happens, you can't rebuild
```

### Event Sourcing Approach (Event Storage)

```
Database stores the history:
  Event 1: Alice borrowed $50 from Bob
  Event 2: Alice paid Bob $20
  Event 3: (deduced) Alice owes Bob $30

When you need the current state:
  Replay events → compute answer

Benefits:
  ✅ Complete history (you know everything that happened)
  ✅ Audit trail (when did each change happen)
  ✅ Rebuilds (if corruption, replay from event 1)
  ✅ Time travel (what was the state on Tuesday?)
```

## Why Events?

### Reason 1: Complete Audit Trail

Every change is recorded with a timestamp. You can answer:
- "When was this contact added?"
- "Who changed this?"
- "In what order did these events happen?"

### Reason 2: Rebuild from Scratch

If a projection table gets corrupted:
1. Delete the corrupted table
2. Replay all events from the beginning
3. Rebuild the correct state

### Reason 3: No Data Loss

You can't accidentally lose history. Events are immutable—once written, they stay.

### Reason 4: Type Safety

Instead of strings like "contact_created" (easy to typo), the system uses Rust enums:

```rust
DomainEvent::ContactCreated { ... }  // Compiler ensures this is valid
```

No more "oops, I misspelled the event type."

## Event Structure

Each event has:
- **id**: Unique identifier (for ordering)
- **aggregate_type**: "contact", "transaction", or "permission"
- **event_type**: "CREATED", "UPDATED", "DELETED", "UNDO"
- **aggregate_id**: Which thing changed (contact ID, transaction ID, etc.)
- **event_data**: All the details (as JSON)
- **timestamp**: When this event occurred
- **version**: For idempotency (if the same request arrives twice)

### Example Event
```json
{
  "id": 12345,
  "aggregate_type": "contact",
  "event_type": "CREATED",
  "aggregate_id": "contact-123",
  "event_data": {
    "name": "Alice",
    "email": "alice@example.com",
    "phone": null
  },
  "timestamp": "2024-06-01T10:30:00Z",
  "version": 1
}
```

## Event Types by Aggregate

### Contact Events
- `CREATED`: New contact added
- `UPDATED`: Contact details changed
- `DELETED`: Contact removed

### Transaction Events
- `CREATED`: New transaction recorded
- `UPDATED`: Transaction details changed
- `DELETED`: Transaction removed

### Permission Events
- `WALLET_USER_ADDED`: User granted access
- `WALLET_USER_ROLE_CHANGED`: User's role updated
- `USER_GROUP_CREATED`: New group created
- `USER_GROUP_DELETED`: Group removed
- `CONTACT_GROUP_CREATED`: Group of contacts created
- `CONTACT_GROUP_UPDATED`: Group updated
- `CONTACT_GROUP_MEMBER_ADDED`: Contact added to group
- `CONTACT_GROUP_MEMBER_REMOVED`: Contact removed from group

### Special Event: UNDO
- `UNDO`: Marks another event as "never happened"

Example:
```json
{
  "aggregate_type": "transaction",
  "event_type": "UNDO",
  "event_data": {
    "undone_event_id": 12344
  }
}
```

This says: "Event 12344 is undone—ignore it when rebuilding."

## Where Events Are Stored

Events live in the **events table**:

```sql
CREATE TABLE events (
  id BIGSERIAL PRIMARY KEY,
  wallet_id UUID NOT NULL,
  aggregate_type TEXT NOT NULL,
  event_type TEXT NOT NULL,
  aggregate_id UUID NOT NULL,
  event_data JSONB NOT NULL,
  version INT NOT NULL,
  created_at TIMESTAMP NOT NULL
);
```

This table:
- Never gets DELETE statements (only INSERT)
- Is append-only (new events always go to the end)
- Is the source of truth for rebuilding

## How Events Become Projections

1. Event arrives: `{"event_type": "CREATED", "name": "Alice"}`
2. Event is stored in the events table
3. Event is applied to projections:
   - For contact events: UPDATE `contacts_projection`
   - For transaction events: UPDATE `transactions_projection`
   - For permission events: UPDATE operational tables

Next time you query "who are all my contacts?", you get the answer from the projection—no replay needed.

## Tags
`#events` `#event-sourcing` `#architecture` `#immutable-history`

## Related Topics
- **How handlers process events:** [03-type-driven-handlers.md](03-type-driven-handlers.md)
- **Where events are applied:** [../02-projections/01-what-are-projections.md](../02-projections/01-what-are-projections.md)
- **UNDO events (special case):** [../04-permissions-and-undo/01-undo-events.md](../04-permissions-and-undo/01-undo-events.md)
- **Event types catalog:** [02-event-types-reference.md](02-event-types-reference.md)
- **Glossary:** [../99-reference/01-glossary.md](../99-reference/01-glossary.md) (see: event, aggregate, event sourcing)

---

Next: [02-event-types-reference.md](02-event-types-reference.md) — See all event types defined
