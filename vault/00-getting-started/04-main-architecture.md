# Main Architecture

**Main question this file answers:** How do events, projections, and snapshots work together — and how is the same logic running on both server and client?

---

## Crate layout

```
crates/
├── core/                ← shared rules, no storage engine
│   ├── domain           DomainEvent, EventData (28 variants), typed IDs
│   ├── applier          Projection trait + apply() dispatch
│   ├── resolver         PermissionStore trait + permission rules
│   └── snapshots        SnapshotStore trait + rotation + UNDO predicates
├── server/              ← Postgres backend (sqlx adapters)
└── client/              ← Rust client lib for Flutter/mobile (rusqlite adapters)
```

The `core/*` crates are **pure Rust** — no Postgres, no SQLite, no axum, no FRB. They define the rules. The server and client each implement three storage adapter traits (`Projection`, `PermissionStore`, `SnapshotStore`) against their own engines. Same rules, two engines.

---

## The Complete Flow

A sync request:

```
1. Event arrives (push from client, or applied internally on the server)
   ↓
2. Events table stores it
   { id, aggregate_type, event_type, event_data, timestamp, version, idempotency_key }
   ↓
3. applier::apply(projection, event) dispatches on EventData
   ↓
   Per-variant rules call into the Projection trait:
     - upsert_contact_row, soft_delete_contact_row, ...
     - upsert_transaction_row, ...
     - upsert_wallet_user, add_user_to_system_group, ...
   ↓
   The trait impl runs the SQL appropriate for its engine
   (Postgres on server, SQLite on client).
   ↓
4. Every N events (default 10), or after an UNDO:
   snapshots::save_snapshot writes a checkpoint via SnapshotStore.
   Older snapshots beyond DEFAULT_MAX_SNAPSHOTS are pruned.
   ↓
5. Return current state to caller (server: HTTP response; client: FFI return)
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

## Shared rule dispatch

Events don't decide how to be applied — the shared `applier::apply()` function does:

```
Event arrives: DomainEvent::ContactCreated { name: "Alice" }
       ↓
applier::apply(projection, &event)
       ↓
match on EventData variant (exhaustive — all 28 variants covered)
       ↓
Call projection.upsert_contact_row(...)
       ↓
Per-side impl writes to its own table:
       - Server: INSERT INTO contacts_projection (sqlx + Postgres)
       - Client: INSERT INTO contacts (rusqlite + SQLite)
```

**Key invariant:** the match arms in `applier::apply` are the same on both sides because both sides import the same crate. A new event variant requires:
1. Adding it to `EventData` in `crates/core/domain`
2. Adding a match arm in `crates/core/applier::apply`
3. Adding a Projection trait method (if a new shape of write is needed)
4. Implementing the trait method on BOTH `ServerPermissionProjection` and `SdkProjection`

The Rust compiler enforces step 4 — exhaustive trait impls means a missing method is a compile error.

## Permission Events (Same Pattern, Different Tables)

Permission events flow through the same `applier::apply` dispatch as data events. They land in operational tables, not projections:

```
Event: WalletUserAdded { user_id: "alice", role: "owner" }
       ↓
applier::apply
       ↓
projection.upsert_wallet_user(wallet_id, alice, "owner")
projection.add_user_to_system_group(wallet_id, alice, "all_users")
       ↓
Tables touched:
       - wallet_users (membership + role)
       - wallet_owners (when role='owner', client mirrors server's behavior)
       - user_group_members (added to all_users)
```

The rules layer is the same; only the SQL each side runs differs. **Permission resolution** is then handled by `resolver::resolve_actions` / `permitted_contacts_for_action`, which read these tables via the `PermissionStore` trait. Same crate runs on both sides — the client's local `can_perform()` answers via the same rules the server enforces.

## UNDO and Rebuilds

`applier::apply` treats UNDO variants as **no-ops** — the undone event's effect is still in the projection tables after dispatch. The caller has to recognize UNDO and rebuild.

Shared utilities in `crates/core/snapshots` make this uniform:

```
snapshots::batch_has_undo(event_types)         → bool: any UNDO in batch?
snapshots::collect_undone_event_ids(events)    → HashSet<String>: which event ids are undone
snapshots::UNDO_EVENT_TYPE                     → "UNDO" constant
```

Both sides use these:

- **Client (`sync.rs::pull_and_merge`)**: if `batch_has_undo`, call `rebuild_projection_tables` — wipe the projection tables and replay all events except UNDO + undone ones. The `collect_undone_event_ids` helper builds the skip set.

- **Server (`projections.rs`)**: same idea, plus a snapshot path — finds the snapshot at/before the earliest undone event, restores from it, replays forward skipping UNDO + undone. (Snapshot-aware rollback on the client is future work.)

```
Event 1: ContactCreated { name: "Alice" }
Event 2: ContactCreated { name: "Bob" }
Event 3: UNDO { undone_event_id: 2 }
       ↓
Rebuild triggered:
   undone_ids = {2}
   For each event in [1, 2, 3]:
     - Event 1: apply         → Alice exists
     - Event 2: skip (undone)
     - Event 3: skip (UNDO itself)
   Result: only Alice exists
```

**Why this is necessary:** `applier::apply` would happily run Event 1 (create Alice) then Event 2 (create Bob), and Event 3's no-op leaves Bob in the table. The wipe-and-replay is the simplest correct response.

---

Next: [05-key-tables.md](05-key-tables.md) — Understand the database schema
