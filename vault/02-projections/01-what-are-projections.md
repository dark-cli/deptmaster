# What Are Projections?

**Main question this file answers:** What are projections and why do we need them?

---

## Definition

A **projection** is a materialized view of the current state, built from events.

Instead of computing "how much does Alice owe Bob?" every time someone asks, we **precompute the answer** and store it. That's a projection.

## The Problem Without Projections

Without projections, answering "who are all my contacts?" would require:

```
1. Load all events into memory
2. Replay each one:
   - ContactCreated for Alice → add Alice
   - ContactUpdated for Alice → update Alice
   - ContactCreated for Bob → add Bob
   - etc.
3. Return the current state
```

**This is slow** especially for large wallets (1 million events = 1 second per query).

## The Solution: Projections

With projections, answering "who are all my contacts?" is instant:

```
SELECT * FROM contacts_projection WHERE wallet_id = ?
```

Why? Because we **already computed the answer** when the events arrived.

```
Event arrives: ContactCreated { name: "Alice" }
       ↓
Handler runs:
  INSERT INTO contacts_projection (name) VALUES ('Alice')
       ↓
Answer is ready: Alice is in contacts_projection
```

## How Projections Work

### Step 1: Event Arrives

```
POST /sync with ContactCreated { name: "Alice" }
```

### Step 2: Event Stored

```
INSERT INTO events (aggregate_type, event_type, event_data, ...)
VALUES ('contact', 'CREATED', '{"name": "Alice"}', ...)
```

### Step 3: Handler Applied

The type-driven handler processes the event:

```
DomainEvent::ContactCreated { name: "Alice", ... }
  → apply_contact_event()
    → INSERT INTO contacts_projection (name) VALUES ('Alice')
```

### Step 4: Projection Updated

```
contacts_projection now has:
id: 123, name: "Alice", email: null, ...
```

### Step 5: User Gets Current State

```
SELECT name FROM contacts_projection WHERE id = 123
Result: "Alice"
```

## Event → Projection Examples

### Contact Events

```
Event: ContactCreated { name: "Alice", email: "alice@example.com" }
  → INSERT INTO contacts_projection (name, email) VALUES ('Alice', 'alice@example.com')

Event: ContactUpdated { id: 123, name: "Alice Smith" }
  → UPDATE contacts_projection SET name = 'Alice Smith' WHERE id = 123

Event: ContactDeleted { id: 123 }
  → DELETE FROM contacts_projection WHERE id = 123
```

### Transaction Events

```
Event: TransactionCreated { contact_id: 123, amount: 5000, direction: "owed" }
  → INSERT INTO transactions_projection (contact_id, amount, direction) VALUES (123, 5000, 'owed')

Event: TransactionUpdated { id: 456, amount: 6000 }
  → UPDATE transactions_projection SET amount = 6000 WHERE id = 456
```

## Permission Events (Different Pattern)

Permission events don't have a "permissions_projection" table. Instead, they update **operational tables**:

```
Event: WalletUserAdded { user_id: "alice", role: "admin" }
  → INSERT INTO wallet_users (wallet_id, user_id, role) VALUES (wallet_id, 'alice', 'admin')

Event: UserGroupCreated { group_id: "group-1", name: "Managers" }
  → INSERT INTO user_groups (id, name) VALUES ('group-1', 'Managers')
```

Same idea: event applied → table updated → answer ready.

## Projection vs. Event Table

| Table | Purpose | Updated When |
|---|---|---|
| **events** | Complete history | New event arrives |
| **contacts_projection** | Current state | ContactCreated/Updated/Deleted event applied |
| **transactions_projection** | Current state | TransactionCreated/Updated event applied |
| **wallet_users** | Current permissions | WalletUserAdded/RoleChanged event applied |

## Why Projections Matter

### Reason 1: Speed
Queries return instantly (table lookup, not event replay).

### Reason 2: Simplicity
Application code reads projections, not raw events.

### Reason 3: Flexibility
You can have multiple projections of the same events.

For example, you could have:
- `contacts_projection` (all contacts)
- `contacts_by_group_projection` (contacts organized by group)
- `contacts_by_last_contact_date_projection` (most recently contacted)

All built from the same events, just organized differently.

### Reason 4: Rebuild Capability
If a projection gets corrupted:
1. Delete it
2. Rerun events
3. Rebuild from scratch

Events are immutable, so rebuilding is deterministic and safe.

## Projection Consistency

**Question:** Can projections get out of sync with events?

**Answer:** Only during rebuilds. During normal operation:
- Event arrives → immediately applied to projection
- They stay in sync

**During rebuild:**
- Projections are cleared
- Events are replayed
- They are brought back in sync

(This is why rebuilds are atomic—they complete all-or-nothing.)

---

Next: [02-projection-tables-schema.md](02-projection-tables-schema.md) — Understand the projection tables in detail
