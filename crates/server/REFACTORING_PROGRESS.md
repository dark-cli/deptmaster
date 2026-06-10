# sync.rs Refactoring Progress

## Executive Summary
Establishing type-driven validation and domain event foundation for sync.rs refactoring (2467 → ~200 lines target).

## Completed Phases

### ✅ Phase 0: Strongly-Typed Domain Events Foundation
**Status:** COMPLETE - All 44 tests passing

Created `src/domain/events.rs` with:
- DomainEvent enum: 25 strongly-typed variants
- Contact events: ContactCreated, ContactUpdated, ContactDeleted, ContactUndone
- Transaction events: TransactionCreated, TransactionUpdated, TransactionDeleted, TransactionUndone  
- Permission events: 17 permission-specific variants (WALLET_USER_*, USER_GROUP_*, CONTACT_GROUP_*, PERMISSION_MATRIX_SET)
- Type-safe fields: Each variant has only required/optional fields (e.g., ContactCreated must have `name: String`, but optional `username`, `phone`, `email`, `notes`)
- Accessor methods: `id()`, `aggregate_id()`, `wallet_id()`, `user_id()`, `created_at()`, `version()`
- Discriminator methods: `aggregate_type()`, `event_type()`

### ✅ Phase 1: Database Integration
**Status:** COMPLETE - All 44 tests passing

Integrated DomainEvent with database layer:
- `to_event()`: DomainEvent → Event (for DB storage)
- `from_event()`: Event → DomainEvent (for reading from DB)
- Exported Event struct from `src/database/models/mod.rs`
- Seamless conversion between typed events and generic Event struct

## Pending Phases

### ⏳ Phase 2: Type-Driven Validation (Foundation Ready)
**Scope:** Create SyncEventRequest with custom serde deserializers

Implementation strategy:
```rust
// Custom deserializers validate at boundary:
// - deserialize_uuid_string: validate UUID format
// - deserialize_aggregate_type: validate against ["contact", "transaction", "permission"]
// - deserialize_event_type: validate against valid types for that aggregate_type
// - validate_timestamp: parse RFC3339 format

// SyncEventRequest.to_domain_event() converts request + context → DomainEvent
```

Benefits:
- Invalid data rejected at deserialization (HTTP boundary)
- Validation no longer needed in handler logic
- No invalid states in sync.rs business logic

### ⏳ Phase 3: Repository Layer Event Application
**Scope:** Move 744-line `apply_events_to_projections()` to database layer

Files involved:
- `src/handlers/sync.rs`: apply_events_to_projections (744 lines) → DELETE
- `src/database/repository/events.rs`: NEW - event application logic
- `src/database/repository/mod.rs`: Add trait methods

Current approach in sync.rs:
```
apply_events_to_projections(state, events, user_id, wallet_id, undone_event_ids)
  ├── Collect UNDO events (undone_event_ids)
  └── Apply events (contact, transaction, permission)
      ├── apply_single_event_to_projections()
      ├── apply_contact_created()
      ├── apply_contact_updated()
      ├── apply_permission_event()
      └── ...
```

### ⏳ Phase 4: Snapshot Service Integration
**Scope:** Update snapshot service to work with DomainEvent

Files involved:
- `src/services/projection_snapshot_service.rs`: Update to use DomainEvent
- `src/handlers/sync.rs`: Use snapshot service instead of duplicating logic

Current duplication:
- sync.rs has snapshot restoration logic
- sync.rs has snapshot creation logic
→ Should use projection_snapshot_service API

### ⏳ Phase 5: Thin Orchestration Layer
**Scope:** Refactor sync.rs from 2467 → ~200 lines

Target structure:
```rust
pub async fn post_sync_events(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
    Json(events): Json<Vec<SyncEventRequest>>, // ALREADY VALIDATED
) -> Result<Json<SyncEventsResponse>, Error> {
    // 1. Convert to DomainEvent using to_domain_event()
    let domain_events: Vec<DomainEvent> = events.iter()
        .map(|e| e.to_domain_event(wallet_id, user_id))
        .collect::<Result<_, _>>()?;
    
    // 2. Check permissions using PermissionModel::check_permissions()
    let perms = permission_model.check_permissions(&ctx, vec![
        (Action::ContactCreate, Resource::AllContacts),
        // ...
    ]).await?;
    
    // 3. Apply events using repository
    db.apply_events_to_projections(wallet_id, domain_events).await?;
    
    // 4. Create snapshot if needed using projection_snapshot_service
    if should_create_snapshot(event_count) {
        projection_snapshot_service::save_snapshot(...).await?;
    }
    
    // 5. Return response
    Ok(Json(response))
}
```

Expected result:
- sync.rs: 2467 → ~200 lines (92% reduction)
- Business logic: moved to repository layer
- Snapshot logic: delegated to service
- Permission logic: using PermissionModel API
- Validation: in serde deserializers (sync/request.rs)

## Key Design Decisions

1. **Type Safety Over Runtime Checks**: Invalid states unrepresentable
2. **Validation at Boundary**: Serde deserializers reject bad data before handler
3. **Business Logic in Repository**: Where it belongs (testable, reusable)
4. **Thin HTTP Layer**: sync.rs becomes orchestration only
5. **Reuse Existing Services**: PermissionModel, snapshot_service (don't duplicate)

## Testing Progress
- Current: 44 tests passing
- Regression risk: LOW (foundation layers complete, no breaking changes)
- Integration risk: MEDIUM (phases 3-5 touch core event logic)

## Estimated Effort Remaining
- Phase 2: 2-3 hours (type validation, conversion)
- Phase 3: 5-6 hours (move 744 lines, understand all branches)
- Phase 4: 1-2 hours (integrate snapshot service)
- Phase 5: 2-3 hours (refactor sync.rs, update tests)
- **Total: 10-14 hours** (phases 3-5 are the critical path)

## Next Steps
1. ✅ Phase 0-1: Foundation complete
2. Phase 2: Implement SyncEventRequest validators
3. Phase 3: Move event application to repository
4. Phase 4: Update snapshot service integration
5. Phase 5: Complete sync.rs refactoring
6. Final testing: Run all 44 tests + any new integration tests
