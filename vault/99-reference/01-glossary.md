# Glossary

**Main question this file answers:** What do all these terms mean?

---

## Core Concepts

### Aggregate
A grouping of related events. In the debt tracker:
- **Contact Aggregate:** All events about a specific contact
- **Transaction Aggregate:** All events about a specific transaction
- **Permission Aggregate:** All events about permissions

Each aggregate has its own event types, handler, and (usually) projection tables.

### Aggregate Type
An enum representing the three main aggregates: Contact, Transaction, Permission.

Used by the type-driven handler system to route events to the correct handler.

### DomainEvent
A strongly-typed Rust enum representing all possible events in the system.

Instead of strings like "contact_created", we use `DomainEvent::ContactCreated { ... }`.

### Event
An immutable record of something that happened. Once written to the database, it never changes.

Events are the source of truth for the system. Everything else (projections, snapshots) is computed from events.

### Event Handler
A function that applies an event to the database.

When a `ContactCreated` event arrives, the handler inserts a row into `contacts_projection`.

### Event Sourcing
An architecture pattern where state changes are stored as immutable events, instead of storing current state.

Instead of "Alice owes Bob $50", store the history: "Alice borrowed $50", "Alice paid $20" → Alice owes $30.

### Idempotency
The ability to apply the same operation multiple times with the same result.

If the same sync request arrives twice, the result is the same (no duplicates).

### Idempotency Key
A unique identifier for each request (usually a UUID).

Used to detect duplicate requests and prevent double-processing.

### Materialized View
See: Projection.

### Projection
A computed view of current state, built from events.

`contacts_projection` is a materialized view of all contacts (computed from `ContactCreated`/`ContactUpdated`/`ContactDeleted` events).

### Snapshot
A checkpoint: "here's the state at this point in time."

Used to speed up rebuilds by avoiding reprocessing all events from the beginning.

### UNDO Event
A special event that marks another event as "never happened."

`UNDO { undone_event_id: 100 }` marks event 100 as deleted (but both are preserved in the audit trail).

### Watermark
See: last_event_id.

## Database Tables

### events
The immutable event log. Every change is recorded here.

Never deleted, only appended to.

### contacts_projection
Materialized view of current contacts.

Rebuilt from `ContactCreated`/`ContactUpdated`/`ContactDeleted` events.

### transactions_projection
Materialized view of current transactions (debts).

Rebuilt from `TransactionCreated`/`TransactionUpdated` events.

### wallet_users
Operational table: who has access to the wallet and their role.

Updated by permission events (`WalletUserAdded`, `WalletUserRoleChanged`).

### user_groups
Groups of users (for permission management).

Updated by permission events (`UserGroupCreated`, `UserGroupDeleted`).

### contact_groups
Groups of contacts.

Updated by permission events (`ContactGroupCreated`, `ContactGroupUpdated`, `ContactGroupMember*`).

### snapshots
Checkpoint data: state at specific points in time.

Keyed by `(wallet_id, aggregate_type)` for O(1) lookup.

## Optimization Terms

### Batch Processing (Phase 2)
Processing events in configurable batches (default: 1,000) to keep memory bounded.

Instead of loading all 1 million events at once (1 GB RAM), load 1,000 at a time (10 MB RAM).

### last_event_id (Phase 1)
A watermark tracking the last event that was already processed.

Prevents reprocessing the same events in subsequent syncs. Enables O(n) instead of O(n²) memory growth.

### Memory Bound
Keeping maximum memory usage constant regardless of wallet size.

Target: 5-10 MB per sync, even for wallets with millions of events.

### Rebuild
Clearing all projections and reprocessing all events from scratch.

Triggered by: UNDO events, data corruption, schema changes.

### Snapshot Frequency
How often to create snapshots (default: every 1,000 events).

Configurable: smaller = more snapshots (slower rebuild, more storage), larger = fewer snapshots (faster rebuild, less storage).

## Permission Terms

### Owner
Special role, can't be removed, represents the wallet creator.

Only one owner per wallet.

### Admin
Full access role, can do everything including inviting users.

Can be removed or downgraded.

### Viewer
Read-only role, can see everything but can't modify anything.

### Role
User's permission level in the wallet: owner, admin, or viewer.

### System Group
A group automatically created by the system (e.g., "All Users").

Marked with `system = true`, preserved during rebuilds.

### User-Created Group
A group created by a user.

Marked with `system = false`, deleted during rebuilds.

## Testing Terms

### Integration Test
Tests the full flow end-to-end (API → database).

Uses `POST /sync` to test actual event processing.

### Unit Test
Tests a single component in isolation.

Tests event handlers directly without the HTTP layer.

### Idempotent Test
A test that produces the same result even if run multiple times.

Safe to retry without affecting the result.

## HTTP/API Terms

### Aggregate ID
The ID of the specific thing that changed (contact ID, transaction ID, etc.).

Used to link events to the things they describe.

### Event Data
The JSON payload containing event details (all fields specific to that event type).

Different for each event type (contact name, transaction amount, permission role, etc.).

### Event Type
The kind of change: CREATED, UPDATED, DELETED, UNDO.

Combined with aggregate_type to identify the exact event.

### Sync
The HTTP endpoint where clients send events to the server.

`POST /sync` with a list of events.

### Sync Request
The HTTP request to `/sync` containing events.

### Sync Response
The HTTP response from `/sync` containing current state.

## Architecture Terms

### Type-Driven Handler
An event handler that uses Rust enums instead of string matching.

Routes events based on compiled type information, not runtime strings.

### String-Based Handler
The old approach: using strings like "contact_created" to route events.

No longer used in the system (replaced by type-driven handlers).

### Handler Delegation
When `apply_self()` routes to aggregate-specific handlers.

`apply_self()` → (matches aggregate type) → `apply_contact_event()` / `apply_transaction_event()` / etc.

## Data Flow Terms

### Sync Arrives
The moment a new sync request (events) arrives at the `/sync` endpoint.

Triggers: validation, storage, application, snapshotting.

### Event Applied
The moment an event is processed and its effects committed to the database.

Projections and operational tables are updated.

### State Updated
Synonym for "event applied".

Projections now reflect the new state.

### Rebuild Triggered
The moment a full rebuild starts (usually because UNDO events are present).

All projections are cleared and reprocessed.

---

Use this glossary whenever you encounter unfamiliar terms in the documentation.
