# Code Organization

**Main question this file answers:** Where does each piece of code live in the codebase?

---

## File Structure

```
src/
├── domain/
│   └── events.rs
│       ├── DomainEvent enum (all event types)
│       ├── AggregateType enum
│       ├── apply_self() method
│       ├── apply_contact_event() handler
│       ├── apply_transaction_event() handler
│       ├── apply_permission_event() handler
│       └── clear_aggregate_type() method
│
├── database/
│   └── repository/
│       ├── mod.rs (DatabaseRepository trait)
│       ├── events.rs
│       │   ├── apply_event_batch()
│       │   ├── apply_event_batch_type_driven()
│       │   ├── apply_event_to_projections()
│       │   └── get_sync_events_since()
│       └── [other repository methods]
│
├── handlers/
│   └── sync.rs
│       ├── post_sync_events() HTTP handler
│       ├── get_sync_events() HTTP handler
│       └── get_sync_hash() HTTP handler
│
├── services/
│   └── projection_snapshot_service.rs
│       ├── save_snapshot()
│       ├── restore_snapshot()
│       └── cleanup_old_snapshots()
│
└── permissions/
    └── model.rs
        ├── PermissionModel
        └── check_permissions()

tests/
└── snapshot_optimization_test.rs
    ├── test_batch_processing_with_permission_events()
    ├── test_permission_events_with_undo()
    └── test_permission_events_with_snapshot()
```

## Key Files

### src/domain/events.rs (800+ lines)

**What:** Event definitions and handlers

**Contains:**
- `DomainEvent` enum (20+ variants)
- `AggregateType` enum
- `apply_self()` method
- `apply_contact_event()`, `apply_transaction_event()`, `apply_permission_event()` handlers
- `clear_aggregate_type()` method
- Helper methods like `aggregate_type_enum()`

**When to edit:**
- Adding new event types
- Modifying event structure
- Updating handlers
- Changing how events are applied

**Never edit:**
- This is the source of truth for events
- All handlers live here with their type definitions

### src/database/repository/events.rs (200+ lines)

**What:** Database operations for events

**Contains:**
- `apply_event_batch()` (old string-based, deprecated)
- `apply_event_batch_type_driven()` (new, type-driven)
- `apply_event_to_projections()` (applies one event)
- `get_sync_events_since()` (loads events since timestamp)
- `get_sync_hash()` (gets aggregate hash for conflict detection)

**When to edit:**
- Changing how events are loaded or batched
- Modifying batch size
- Updating event query logic

### src/handlers/sync.rs (2000+ lines being refactored)

**What:** HTTP endpoints for syncing

**Contains:**
- `post_sync_events()` - accepts events from client
- `get_sync_events()` - returns recent events
- `get_sync_hash()` - returns hash for conflict detection
- Validation logic
- Permission checks
- Snapshot management

**Note:** Being refactored to ~200 lines (thin orchestration layer)

### src/services/projection_snapshot_service.rs

**What:** Snapshot management

**Contains:**
- `save_snapshot()` - saves a snapshot
- `restore_snapshot()` - loads a snapshot
- `cleanup_old_snapshots()` - deletes old snapshots
- `should_create_snapshot()` - decides if snapshot should be created

**When to edit:**
- Changing snapshot creation frequency
- Modifying snapshot storage format
- Updating cleanup policy

### src/permissions/model.rs

**What:** Permission checking

**Contains:**
- `PermissionModel` struct
- `check_permission()` - checks if user can do action
- `get_readable_contacts()` - filters contacts by permission
- `get_readable_transactions()` - filters transactions by permission

**When to edit:**
- Adding new permissions
- Changing permission logic
- Modifying access control

## Database Schema Files

### migrations/

SQL files for table creation:
- `events` table
- `contacts_projection` table
- `transactions_projection` table
- `wallet_users` table
- `user_groups`, `contact_groups` tables
- `snapshots` table

### Schema Visualization

```
events → (type-driven handler) → contacts_projection
         ↓                      → transactions_projection
         ↓                      → wallet_users (permission)
         ↓                      → user_groups (permission)
         ↓
     (every 1000 events)
         ↓
      snapshots
```

## Testing Files

### tests/snapshot_optimization_test.rs

Tests for snapshot and batch processing behavior:
- `test_batch_processing_with_permission_events()`
- `test_permission_events_with_undo()`
- `test_permission_events_with_snapshot()`
- All 13 tests passing

## Adding Files (When Needed)

### Adding a New Handler
```
src/handlers/[name].rs
├── pub async fn [name]() { ... }
└── Use existing repository/permission/service layers
```

### Adding a New Service
```
src/services/[name]_service.rs
├── pub struct [Name]Service
└── pub async fn [methods]() { ... }
```

### Adding a New Repository Module
```
src/database/repository/[name].rs
├── Implement trait methods
└── Add to DatabaseRepository trait in mod.rs
```

## Dependency Flow

```
HTTP handlers (sync.rs)
    ↓
Database repository (repository/*)
    ↓
Domain logic (domain/events.rs)
    ↓
Database (PostgreSQL)

Services (snapshots, permissions)
    ↓ (used by handlers)
    ↓
Database
```

**Key principle:** Domain logic (events) doesn't depend on HTTP or database details. Event handlers are pure: given an event and a database pool, they apply the event.


Next: [03-testing-event-handlers.md](03-testing-event-handlers.md) — Learn how to test event handlers
