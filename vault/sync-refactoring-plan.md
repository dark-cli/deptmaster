# sync.rs Refactoring: Type-Driven Validation & Thin Orchestration

## Context
sync.rs is 2467 lines with mixed concerns:
- **apply_events_to_projections**: 744 lines of business logic
- **post_sync_events**: 322 lines orchestrating validation, permissions, application
- **validate_event**: 95 lines of imperative validation rules
- **ReadContext**: Permission filtering duplicating PermissionModel
- **Event types**: Generic EventRow/Event with String fields and serde_json::Value data

**Goal:** Build proper Event Sourcing architecture with:
1. **Strongly-typed domain events** (ContactCreated, TransactionUpdated, etc.)
2. **Type safety**: Invalid states unrepresentable
3. **Validation at boundaries**: Serde deserializers enforce rules
4. **Reusable types**: Use DomainEvent throughout codebase
5. **Thin sync.rs**: HTTP orchestration only

## Current State Analysis

### Existing Event Models (Generic)
```rust
// database/models/event.rs
pub struct EventRow {
    pub event_id: Uuid,
    pub aggregate_type: String,      // ❌ String, not typed
    pub event_type: String,          // ❌ String, not typed
    pub data: serde_json::Value,     // ❌ Untyped JSON
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub version: i32,
}
```

### Issues
- No type safety for event structure
- Invalid states possible (ContactCreated without name)
- Validation scattered in validate_event() function
- Same untyped event structure everywhere (sync, snapshot, repository)
- Hard to pattern match on specific event types

## Proposed Architecture: Strongly-Typed Domain Events

### New Event Type Structure
```
src/domain/
└── events.rs
    └── DomainEvent enum with 12-15 typed variants:
        ├── ContactCreated { id, name, wallet_id, ... }
        ├── ContactUpdated { id, name, group_ids, ... }
        ├── ContactDeleted { id }
        ├── ContactUndone { id, undone_event_id }
        ├── TransactionCreated { id, contact_id, amount, direction, ... }
        ├── TransactionUpdated { id, contact_id, amount, direction, ... }
        ├── TransactionDeleted { id }
        ├── TransactionUndone { id, undone_event_id }
        ├── PermissionCreated { ... }
        ├── PermissionUpdated { ... }
        ├── PermissionDeleted { ... }
        └── ... (other permission event types)
```

### Key Principle: Invalid States Unrepresentable
```rust
enum DomainEvent {
    ContactCreated { 
        id: Uuid, 
        name: String,                    // ✅ Must have - can't be created without
        wallet_id: Uuid,
        // ... other required fields
    },
    ContactUpdated { 
        id: Uuid, 
        name: Option<String>,             // ✅ Optional in updates
        group_ids: Vec<Uuid>,
        // ... other optional fields
    },
    // ... rest of variants
}

// Can't accidentally create ContactCreated without name - compiler won't allow it
```

### Conversion Strategy
```
HTTP Request (JSON)
    ↓
[Custom Serde Deserializer]
    ↓
DomainEvent (Strongly-Typed) ✅ VALIDATED
    ↓
[Business Logic Uses DomainEvent]
    ↓
[Store as EventRow - convert back to JSON]
    ↓
Database (EventRow with JSON)
    ↓
[Read EventRow - convert to DomainEvent]
    ↓
[Apply to Projections]
```

## Implementation Plan (5 Phases - Foundation First)

### Phase 0: Create Strongly-Typed Domain Events (4-5 hours)
**Files to create:**
- `src/domain/mod.rs` - module init
- `src/domain/events.rs` - DomainEvent enum with all variants

**What to do:**
1. Define `DomainEvent` enum with 12-15 variants:
   - Contact: Created, Updated, Deleted, Undone (4 variants)
   - Transaction: Created, Updated, Deleted, Undone (4 variants)
   - Permission: Created, Updated, Deleted, etc. (3-4 variants based on PERMISSION_EVENT_TYPES)
2. Each variant has only its required/optional fields:
   ```rust
   enum DomainEvent {
       ContactCreated {
           id: Uuid,
           name: String,
           wallet_id: Uuid,
       },
       ContactUpdated {
           id: Uuid,
           name: Option<String>,
           group_ids: Option<Vec<Uuid>>,
       },
       // ... etc
   }
   ```
3. Implement serde traits with custom deserializers for validation
4. Add conversion methods: `DomainEvent → serde_json::Value` (for storage)
5. Add conversion methods: `serde_json::Value → DomainEvent` (for reading)

**Verification:**
- All variants compile
- Can construct events without invalid states
- Serialization/deserialization works
- No validate_event() function needed

**Result:** Foundation of type-safe events ready to use everywhere

### Phase 1: Update Database Models & Repository (3-4 hours)
**Files to modify:**
- `src/database/models/event.rs` - Keep EventRow generic (DB storage)
- `src/database/models/mod.rs` - Export DomainEvent
- `src/database/repository/events.rs` - NEW methods for DomainEvent

**What to do:**
1. Keep EventRow as-is (generic, how it's stored in DB)
2. Add repository methods:
   - `convert_event_row_to_domain(EventRow) -> DomainEvent` 
   - `convert_domain_to_event_data(DomainEvent) -> serde_json::Value`
3. Update event insertion:
   - Accept `DomainEvent` instead of raw fields
   - Convert to JSON before storing
4. Create new repository methods:
   - `get_events_as_domain(wallet_id, since) -> Vec<DomainEvent>`
   - `insert_domain_event(wallet_id, DomainEvent) -> Result`

**Verification:**
- Can insert DomainEvent and retrieve it back
- Round-trip conversion works: DomainEvent → JSON → DomainEvent
- No data loss in conversions
- All 44 existing tests still pass

**Result:** DomainEvent integrated into database layer

### Phase 2: Update sync.rs Event Handling (3-4 hours)
**Files to modify:**
- `src/handlers/sync.rs` - Use DomainEvent instead of validate_event()
- Create `src/handlers/sync/request.rs` - SyncEventRequest with deserializer

**What to do:**
1. Create `SyncEventRequest` struct with custom deserializer:
   ```rust
   #[derive(Deserialize)]
   pub struct SyncEventRequest {
       #[serde(flatten, deserialize_with = "deserialize_domain_event")]
       pub event: DomainEvent,  // ← Already validated!
       // timestamp, version, etc
   }
   ```
2. The deserializer converts JSON → DomainEvent (validates structure)
3. Remove `validate_event()` function from sync.rs
4. Remove `ReadContext` usage (will be removed in later phase)
5. Update `post_sync_events()` to use `SyncEventRequest` with DomainEvent

**Verification:**
- Invalid JSON rejected at deserialization (400 errors)
- Valid events processed correctly
- All sync tests pass
- No more manual validate_event() calls

**Result:** sync.rs uses type-safe DomainEvent

### Phase 3: Update Event Application Logic (2-3 hours)
**Files to modify:**
- `src/handlers/sync.rs` - apply_events_to_projections
- `src/database/repository/events.rs` - add event application methods

**What to do:**
1. Update `apply_events_to_projections()` to pattern match on DomainEvent:
   ```rust
   fn apply_event(event: &DomainEvent, db: &Database) {
       match event {
           DomainEvent::ContactCreated { id, name, wallet_id } => {
               // Apply contact creation
           }
           DomainEvent::ContactUpdated { id, name, group_ids } => {
               // Apply contact update
           }
           // ... etc for each variant
       }
   }
   ```
2. Move this logic to repository/events.rs
3. Type-safe - can't accidentally miss a variant

**Verification:**
- Events apply correctly to projections
- Pattern matching covers all variants
- Compiler warns if new variant added but not handled
- All tests pass

**Result:** Event application uses type-safe DomainEvent

### Phase 4: Update Snapshots (1-2 hours)
**Files to modify:**
- `src/services/projection_snapshot_service.rs` - Use DomainEvent if needed

**What to do:**
1. Verify snapshot logic works with DomainEvent conversions
2. Update any snapshot creation/restoration to use typed events
3. Test snapshot serialization/deserialization

**Verification:**
- Snapshots can be created and restored
- Events in snapshots deserialize to DomainEvent
- All snapshot tests pass

**Result:** Snapshot service works with DomainEvent

### Phase 5: Full sync.rs Refactoring (2-3 hours)
**Files to modify:**
- `src/handlers/sync.rs` - THIN ORCHESTRATION
- Create `src/handlers/sync/mod.rs`, `response.rs`
- `src/database/repository/events.rs` - move business logic

**What to do:**
1. Move `apply_events_to_projections()` to repository
2. Delete `ReadContext`, use PermissionModel directly
3. Delete duplicate snapshot logic, use snapshot_service
4. Simplify sync.rs to ~200 lines (orchestration only)
5. Use DomainEvent throughout

**Verification:**
- sync.rs is ~200 lines (92% reduction)
- All tests pass
- No invalid states possible
- Type safety at all boundaries

**Result:** Clean, thin sync.rs with proper event types

## Critical Files

### To Create (Phase 0)
- `src/domain/mod.rs` - module init
- `src/domain/events.rs` - DomainEvent enum (all 12-15 variants)

### To Modify
- `src/database/repository/events.rs` - NEW event methods + conversions
- `src/database/models/mod.rs` - export DomainEvent
- `src/handlers/sync.rs` - use DomainEvent + thin orchestration
- `src/handlers/sync/request.rs` - SyncEventRequest

### To Reference/Use
- `src/services/projection_snapshot_service.rs` - USE it
- `src/permissions/model.rs` - USE PermissionModel API

## Validation Strategy

### Level 1: Type System
- Invalid states unrepresentable (ContactCreated without name impossible)
- Compiler enforces all variants handled in pattern matching
- No serde_json::Value - all fields typed

### Level 2: Serde Deserializer
- UUID parsing with proper errors
- Enum validation (direction: lent|owed)
- Required fields must exist
- Invalid JSON rejected at boundary (400 error)

### Level 3: Handler
- Receives ONLY validated DomainEvent
- No runtime checks needed
- Pattern matching covers all cases

## Timeline Estimate
- Phase 0 (Domain events): 4-5 hours
- Phase 1 (Database integration): 3-4 hours
- Phase 2 (sync.rs event handling): 3-4 hours
- Phase 3 (Event application): 2-3 hours
- Phase 4 (Snapshots): 1-2 hours
- Phase 5 (sync.rs refactoring): 2-3 hours
- **Total: 15-21 hours**

## Testing Strategy

### Phase 0 Verification
- All 44 existing tests still pass
- No new tests needed (just foundation)

### Phase 1 Verification
- Tests: `cargo test --lib`
- Verify: EventRow → DomainEvent → JSON conversions work

### Phase 2 Verification
- Tests: `cargo test --test app_instances_sync_test`
- Manual: Try sending bad JSON - should get 400 error

### Phase 3 Verification
- Tests: `cargo test --test wallet_permissions_stage2a_test`
- Verify: Events apply correctly to projections

### Phase 4 Verification
- Tests: `cargo test` (full suite)
- Verify: Snapshots work with DomainEvent

### Phase 5 Verification
- Tests: `cargo test` (full suite)
- Verify: sync.rs is ~200 lines
- Verify: All 50+ tests pass
- No validate_event() function exists
- No ReadContext struct exists

## Benefits
1. ✅ **Type Safety**: Invalid states unrepresentable
2. ✅ **Validation at Boundary**: Serde rejects invalid JSON early
3. ✅ **Self-Documenting**: Each event type shows exactly what fields it has
4. ✅ **Pattern Matching**: Type-safe handling of all event variants
5. ✅ **Reusable**: DomainEvent used throughout codebase
6. ✅ **Compiler Assistance**: New variants require updating all handlers
7. ✅ **Proper Event Sourcing**: Industry-standard strongly-typed events
8. ✅ **sync.rs 92% smaller**: From 2467 → ~200 lines
9. ✅ **No Duplicate Logic**: Snapshot and permission logic centralized
10. ✅ **Foundation for Future**: Easy to extend with new event types
