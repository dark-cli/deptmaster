# Core Concepts

**Main question this file answers:** What are the core ideas behind event sourcing?

---

## Concept 1: Events (Immutable History)

An **event** is a record of something that happened. It's immutable—once written, it never changes.

Examples from the debt tracker:
- `ContactCreated { id: 123, name: "Alice", created_at: 2024-05-30 }`
- `TransactionCreated { id: 456, amount: 50, direction: "lent", created_at: 2024-05-31 }`
- `WalletUserAdded { user_id: 789, role: "admin", created_at: 2024-06-01 }`

**Key insight:** Events record *what happened*, not *the current state*.

| Traditional Database | Event Sourcing |
|---|---|
| Store current state: "Alice owes Bob $50" | Store what happened: "Alice borrowed $50", "Alice paid $20" |
| Update the record | Write a new event |
| No history | Complete history |

## Concept 2: Projections (Materialized Views)

A **projection** is a computed view of the current state, built from events.

When an event arrives, we **apply** it to update the projection:

```
Event: TransactionCreated { amount: 50, direction: "lent", contact_id: "bob" }
            ↓
Apply to projection
            ↓
transactions_projection.total_owed += 50
```

**Key insight:** Projections are answers to questions:
- "How much does Alice owe Bob?" → Look up `transactions_projection`
- "What is Alice's email?" → Look up `contacts_projection`
- "Who can see my wallet?" → Look up `wallet_users`

This is fast because we compute the answer once (when the event arrives), not every time someone asks.

## Concept 3: Aggregates (Grouping Related Events)

An **aggregate** is a group of related events.

In the debt tracker, we have three main aggregates:

**Contact Aggregate**
- Events: ContactCreated, ContactUpdated, ContactDeleted
- These are all about one contact's data

**Transaction Aggregate**
- Events: TransactionCreated, TransactionUpdated, TransactionDeleted
- These are all about one transaction's data

**Permission Aggregate**
- Events: WalletUserAdded, WalletUserRoleChanged, UserGroupCreated, etc.
- These are all about who can do what

**Key insight:** Each aggregate has its own projection tables and handler logic. When you add a new aggregate type (like User or Team), you add:
1. New event types
2. New projection tables
3. New handler logic
4. Done.

## Concept 4: Snapshots (Speed Without Memory)

A **snapshot** is a checkpoint: "here's the state at this point in time."

**Why we need them:**

Imagine a wallet with 1 million events. If we rebuild projections from scratch:
1. Load all 1 million events from the database into memory
2. Process each one
3. This requires ~1 GB of RAM

**Solution: Snapshots**

Instead:
1. Store snapshots: "at event 500,000, the state was..."
2. When rebuilding, start from the latest snapshot
3. Only process recent events (last 50,000, not 1 million)
4. This requires ~50 MB of RAM

**Key insight:** Snapshots are an optimization, not a requirement. The system can work without them; snapshots just make it faster.

## Concept 5: UNDO Events (Soft Deletes)

An **UNDO event** marks another event as deleted without actually deleting the history.

Example:
```
Event 1: TransactionCreated { amount: 50 }
Event 2: TransactionCreated { amount: 20 }
Event 3: UNDO { undone_event_id: 2 }  ← Marks event 2 as "never happened"

Result: Only the $50 transaction counts
```

**Why use UNDO instead of deleting?**
- Preserves the audit trail (you can still see what was undone and when)
- Simpler to implement (just write a new event, don't modify old ones)
- Easy to reverse an UNDO if needed

**Key insight:** UNDO events trigger a full projection rebuild (because one past event changed, all future projections might be wrong).

## Concept 6: Type-Driven Handlers (No Strings)

The system uses **strong typing** instead of string matching to decide how to handle events.

**Old (Bad) Way:**
```
if event_type == "contact_created" && aggregate_type == "contact" {
  // handle it
}
```

**New (Good) Way:**
```
match event {
  DomainEvent::ContactCreated { ... } => {
    // Handle it (compiler ensures this is the right type)
  }
}
```

**Key insight:** Using Rust enums instead of strings means:
- Compiler catches typos (no more "oops, I misspelled CONTACT_CREATE")
- Easy to add new event types (just add a variant)
- No invalid states possible (the type system prevents them)

## How They Work Together

```
1. Event arrives
   ↓
2. Apply event to projection
   (using type-driven handler)
   ↓
3. Projection table updated
   (contacts_projection, transactions_projection, etc.)
   ↓
4. Every 1000 events: create snapshot
   (save "state at event 5000")
   ↓
5. Next rebuild starts from snapshot
   (only process events 5001-6000, not events 1-6000)
```

---

Next: [04-main-architecture.md](04-main-architecture.md) — See how everything fits together
