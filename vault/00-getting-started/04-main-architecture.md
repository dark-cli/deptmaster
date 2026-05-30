# Main Architecture

**Main question this file answers:** How do events, projections, and snapshots work together?

---

## The Complete Flow

Here's how a sync request flows through the entire system:

```
1. User syncs new events
   ↓
2. Events table stores them
   { id, aggregate_type, event_type, event_data, timestamp, version }
   ↓
3. For each event:
   a. Deserialize into DomainEvent enum
   b. Call event.apply_self() 
   c. Type-driven handler processes it
   d. Update projection tables
   ↓
4. Every 1000 events:
   a. Check if snapshot needed
   b. If yes: create snapshot
   c. Snapshot stores aggregate type + state + event_id
   ↓
5. Return current state to user
```

## Tables and Their Relationships

### Events Table (Immutable History)
```
events
├── id (primary key)
├── aggregate_type (contact, transaction, permission)
├── event_type (CREATED, UPDATED, DELETED, UNDO, etc.)
├── aggregate_id (which contact/transaction/etc.)
├── event_data (JSON with all event details)
├── version (for idempotency)
└── created_at (when this event occurred)
```

Used for: Complete history, rebuilding, auditing

### Projection Tables (Current State)
```
contacts_projection
├── id (contact id)
├── wallet_id (which wallet owns this)
├── name, email, phone (contact details)
├── created_at, updated_at
└── (rebuilt from ContactCreated/ContactUpdated/ContactDeleted events)

transactions_projection
├── id (transaction id)
├── wallet_id
├── contact_id (who was involved)
├── amount, direction (lent or owed)
├── (rebuilt from TransactionCreated/TransactionUpdated events)

wallet_users (Permissions)
├── wallet_id
├── user_id
├── role (owner, admin, viewer)
├── (rebuilt from WalletUserAdded/WalletUserRoleChanged events)
```

Used for: Fast queries, answering "what is the current state?"

### Snapshots Table (Checkpoint)
```
snapshots
├── wallet_id (which wallet)
├── aggregate_type (contact, transaction, permission)
├── last_event_id (events up to this ID)
├── state (JSON snapshot of projections at this point)
└── created_at
```

Used for: Fast rebuilds (start from checkpoint, not from beginning)

## Example: Adding a Contact

### Step 1: User Syncs Event
```json
POST /sync
{
  "event_type": "CREATED",
  "aggregate_type": "contact",
  "event_data": { "name": "Alice" }
}
```

### Step 2: Event Stored in Database
```
INSERT INTO events (aggregate_type, event_type, event_data, ...)
VALUES ('contact', 'CREATED', '{"name": "Alice"}', ...)
```

### Step 3: Event Applied to Projection
```
1. Deserialize into: DomainEvent::ContactCreated { name: "Alice", ... }
2. Call: event.apply_self() 
3. Type system routes to: apply_contact_event()
4. Handler executes:
   INSERT INTO contacts_projection (name, ...) VALUES ('Alice', ...)
```

### Step 4: Projection Table Updated
```
contacts_projection now contains:
id: 123, name: "Alice", wallet_id: ...
```

### Step 5: User Can Query It
```
SELECT name FROM contacts_projection WHERE id = 123
Result: "Alice"
```

## Example: Rebuilding from a Snapshot

### Scenario
Wallet has 100,000 events. Need to rebuild from event 50,000 onward.

### Without Snapshot (Slow)
```
1. Load events 1-100,000 into memory
2. Process each one
3. RAM usage: ~1 GB ❌
```

### With Snapshot (Fast)
```
1. Find latest snapshot: "at event 50,000, state was..."
2. Restore projection tables from snapshot
3. Load events 50,001-100,000 into memory
4. Process recent events
5. RAM usage: ~50 MB ✅
```

## Type-Driven Handler System

Events don't decide themselves how to be applied. Instead, the system has **type-driven handlers**:

```
Event arrives: DomainEvent::ContactCreated { name: "Alice" }
       ↓
Call: event.apply_self()
       ↓
Match on: aggregate_type_enum()
       ↓
Route to: apply_contact_event()
       ↓
Handler: INSERT into contacts_projection
```

**Key insight:** Each aggregate type (Contact, Transaction, Permission) has its own handler function. The type system ensures:
- No string matching (compiler catches typos)
- No invalid event types (enum prevents them)
- Easy to add new types (just add variant + handler)

## Permission Events (Different Pattern)

Permission events don't have their own projection table. Instead, they update **operational tables**:

```
Event: WalletUserAdded { user_id: "alice", role: "admin" }
       ↓
Apply to: wallet_users table (not a projection)
       ↓
Result: INSERT INTO wallet_users (wallet_id, user_id, role) ...
```

Permission events still:
- Get stored in events table
- Get type-driven handlers
- Can be undone with UNDO events
- Trigger rebuilds when UNDO events present

But they update operational tables instead of projections.

## UNDO and Rebuilds

When an UNDO event is present, the system **rebuilds from scratch**:

```
Event 1: ContactCreated { name: "Alice" }
Event 2: ContactCreated { name: "Bob" }
Event 3: UNDO { undone_event_id: 2 }
       ↓
Rebuild triggered:
   1. Delete all contacts_projection rows
   2. Reprocess ALL events (1-3)
   3. Skip event 2 (because UNDO marks it as deleted)
   4. Result: Only Alice exists
```

**Why full rebuild?** Because event 2 being undone affects event 3's "current state". If we didn't rebuild, event 3's effects would linger.

---

Next: [05-key-tables.md](05-key-tables.md) — Understand the database schema
