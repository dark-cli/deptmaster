---
tags:
  - sync
  - architecture
  - backend
---

# Sync Handler Deep Dive (sync.rs)

**File Size**: 2,400 lines  
**Current Status**: Monolithic - should be split into smaller focused modules

## What It Does

The sync handler is the **heart of the sync API**. It's responsible for:
1. **Push** — Accept events from clients, validate, store, broadcast
2. **Pull** — Send events to clients based on their permissions
3. **Hash Sync** — Calculate hash of events user can see (for efficient sync detection)
4. **Projections** — Rebuild contacts/transactions state from events
5. **Snapshots** — Cache projection snapshots for fast rebuilds

## Main Public Functions

### 1. `get_sync_hash()` (line 193)
**What**: Returns SHA256 hash of all events user is allowed to see  
**Used for**: Client detects if server state changed (hash comparison before pull)

```
Client: GET /api/sync/hash
  → Returns: { hash: "abc123def456...", count: 42 }
  → If hash differs from local hash → Client knows to pull events
```

**Steps**:
1. Fetch all events from DB for wallet
2. Filter by permission (what user can read)
3. Hash the filtered event IDs + timestamps
4. Return hash + count

**Key helpers**:
- `event_read_allowed()` — checks if user can see specific event
- `transaction_contact_ids_for_events()` — maps transactions to contacts for permission check
- `permission_service::sync_read_context()` — precomputes what user is allowed to read

---

### 2. `get_sync_events()` (line 309)
**What**: Returns paginated events user is allowed to read  
**Used for**: Client pulls events from server

```
Client: GET /api/sync/events?since=<timestamp>
  → Returns: { events: [...], has_more: true }
```

**Steps**:
1. Get user's read permissions (contact IDs + permission actions)
2. Fetch events since timestamp
3. Filter by permission (only return events user can read)
4. Paginate with `has_more` flag
5. Return full events with data

**Key logic**:
- `event_read_allowed()` — filter for readable events
- Permission matrix lookup — what actions can user perform
- Transaction filtering — check if transaction's contact is readable

---

### 3. `post_sync_events()` (line 590) — **THE BIGGEST FUNCTION**
**What**: Accept events from client, validate, store, broadcast to all clients  
**Used for**: Client pushes new events (create/update/delete) to server

```
Client: POST /api/sync/events
  Body: { events: [{ id, aggregate_type, event_type, event_data, ... }] }
  → Server stores in DB
  → Server broadcasts to all connected WebSocket clients
  → Returns: { accepted_ids: [...] }
```

**This function is 300+ lines and handles**:
1. **Validate events** — Check structure, required fields, event types
2. **Check permissions** — Does user have permission to create this event?
3. **Check idempotency** — Is this a duplicate? (idempotency_key)
4. **Apply to projections** — Update contacts_projection, transactions_projection
5. **Store in events table** — Append to immutable event log
6. **Broadcast** — Send WebSocket notification to all clients
7. **Handle group membership** — For CONTACT_UPDATED, sync group memberships
8. **Return accepted IDs** — So client knows which events were stored

**Permission checks happen here**:
- `map_event_to_permission_action()` — What permission needed?
- `permission_service::can_perform()` — Does user have it?
- Owner/Admin bypass (HARDCODED - should be removed)

**Applied to projections**:
- `apply_events_to_projections()` — Updates contact/transaction data
- `apply_permission_event()` — Special handling for permission changes
- `apply_contact_group_ids_from_event_data()` — Update group memberships

---

### 4. `rebuild_projections_from_events()` (line 921)
**What**: Rebuilds contacts/transactions/balances from scratch using snapshots + events  
**Used for**: Admin commands, permission changes, data consistency recovery

```
Timeline:
  T=0: Create snapshot of current state
  T=0 to T=now: Apply events since snapshot
  T=now: Projections rebuilt and current
```

**Steps**:
1. Check if snapshot exists and is recent
2. Load snapshot if good, else rebuild from events since last good snapshot
3. Apply events on top of snapshot
4. Verify data consistency
5. Return rebuilt projections

**Why snapshots?**
- Rebuilding from 10,000 events is slow
- Snapshots every N events = faster rebuilds
- On permission change: rebuild only that user's projections

---

## Helper Functions (The Supporting Cast)

### Permission & Read Access
- `event_read_allowed()` — Can user read this specific event?
- `map_event_to_permission_action()` — Event → Permission needed
- `transaction_contact_ids_for_events()` — Map transactions to contacts

### Event Processing
- `validate_event()` — Check event structure
- `apply_events_to_projections()` — Apply events to projection tables
- `apply_permission_event()` — Special permission event handling
- `apply_contact_group_ids_from_event_data()` — Sync contact→group memberships

### Snapshot Management
- `create_snapshot_json()` — Serialize current projections
- `restore_projections_from_snapshot()` — Load from snapshot

### Utilities
- `calculate_total_debt()` — Sum up debts from projection
- `get_sync_hash()` — SHA256 of filtered events

---

## Data Flow: Post Event Example

```
Client sends: POST /api/sync/events
  {
    "events": [{
      "id": "abc-123",
      "aggregate_type": "contact",
      "event_type": "CREATED",
      "aggregate_id": "contact-uuid",
      "event_data": { "name": "Alice", "group_ids": [...] },
      "idempotency_key": "form-uuid-1"
    }]
  }

Server (post_sync_events):
  1. Validate structure → OK
  2. Check idempotency → New event (not duplicate)
  3. Map to permission → contact:create needed
  4. Check permission → User has it
  5. Store in events table → INSERT event
  6. Apply to projection:
     - INSERT into contacts_projection
     - INSERT into contact_group_members (for each group_id)
     - Update total_debt if needed
  7. Broadcast WebSocket → All clients notified
  8. Return { accepted_ids: ["abc-123"] }

Client receives:
  - Event stored
  - WebSocket notification received
  - Pulls via GET /api/sync/events?since=<timestamp>
  - Rebuilds local state with new contact
```

---

## Why It's a Monster

**2400 lines because**:
1. **Permission checking** — Complex permission matrix lookups for every event
2. **Projection updates** — Different logic for contacts, transactions, permissions
3. **Snapshot management** — Cache invalidation, rebuild logic
4. **Error handling** — Every DB operation has error handling
5. **Filtering** — Filter events by permission, by aggregate type, by timestamp
6. **Validation** — Validate event structure, fields, types

**Should be split into**:
- `sync_pull.rs` — GET /api/sync/events, get_sync_hash
- `sync_push.rs` — POST /api/sync/events (core logic)
- `event_validator.rs` — validate_event, permission checks
- `projection_applier.rs` — apply_events_to_projections, apply_permission_event
- `snapshot_manager.rs` — snapshot creation/restore
- `group_manager.rs` — contact group membership updates

---

## Key Architectural Issues

1. **Permission checks are inline** — Should use trait-based (see todos)
2. **Owner/Admin bypass** — Hardcoded special case (line ~650)
3. **SQL scattered throughout** — No repository pattern (see todos)
4. **No request correlation** — Can't trace a single sync operation through logs
5. **Transaction group membership not synced** — Only contact groups

---

## Related
- [[sync-architecture.md]] — High-level sync design
- [[permission-system-deep-dive.md]] — How permission checks work
- [[todos.md]] — Refactoring plan for splitting this file
