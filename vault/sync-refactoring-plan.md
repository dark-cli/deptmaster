---
tags:
  - sync
  - refactoring
  - architecture
---

# Sync Refactoring Plan (Hybrid Approach)

**Decision**: Option C - Hybrid approach (fix bugs + incremental refactoring, not full rewrite)

**Rationale**: sync.rs is working and tested, but hard to maintain. Fix critical bugs first, then split incrementally while keeping behavior constant. Only rewrite modules if/when needed.

---

## Phase 1: Critical Bug Fixes (Week 1)

### 1.1 Fix Hash Performance (Incremental Calculation)
**Current Problem**: `get_sync_hash()` loads ALL events from DB every request
- 100K events = 100MB+ memory + network transfer
- Mobile calls frequently before pull → would collapse in production

**Solution**: Hash = previous_hash + hash(new_events_since_last_hash)

**Implementation**:
```sql
-- Add sync_hash_cache table
CREATE TABLE sync_hash_cache (
  wallet_id UUID PRIMARY KEY,
  hash TEXT NOT NULL,
  last_event_id UUID,
  last_event_timestamp TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- On GET /api/sync/hash:
-- 1. Get cached hash + last_timestamp
-- 2. Fetch only events since last_timestamp
-- 3. Calculate new_hash = combine(old_hash, hash(new_events))
-- 4. Return new_hash

-- On POST /api/sync/events:
-- 1. Store events
-- 2. Update sync_hash_cache with new hash + timestamp
```

**Effort**: ~1-2 hours  
**Risk**: Low (isolated change)  
**Tests**: Verify hash matches full recalc for first request, then matches incremental for subsequent requests

---

### 1.2 Fix Error Handling (Per-Event Feedback)
**Current Problem**: Batch rejected with generic "DEBITUM_INSUFFICIENT_PERMISSION", user doesn't know which event failed

**Solution**: Return detailed `failed_events` list with reasons

**Implementation**:
```rust
// Current response:
{ "error": "DEBITUM_INSUFFICIENT_PERMISSION" }

// New response:
{
  "error": "DEBITUM_SYNC_PERMISSION_DENIED",
  "failed_events": [
    {
      "event_id": "uuid-3",
      "aggregate_type": "contact",
      "required_permission": "contact:create",
      "reason": "User lacks permission"
    }
  ],
  "accepted_count": 0,
  "total_count": 3
}
```

**File**: `backend/rust-api/src/handlers/sync.rs` - `post_sync_events()` error response  
**Effort**: ~30-60 minutes  
**Risk**: Low (just better error detail)  
**Tests**: Verify error response includes failed event details

---

## Phase 2: Modularization (Week 2-3)

### 2.1 Extract Traits
Define clear contracts before refactoring:

```rust
// Define what each module will provide
pub trait EventValidator: Send + Sync {
    async fn validate(&self, event: &Event) -> Result<ValidationResult>;
}

pub trait EventApplier: Send + Sync {
    async fn apply(&mut self, event: &Event) -> Result<()>;
}

pub trait PermissionChecker: Send + Sync {
    async fn check(&self, user: &User, action: &str) -> Result<bool>;
}
```

**File**: `backend/rust-api/src/handlers/sync/traits.rs` (new)  
**Effort**: ~1 hour  
**Risk**: None (just type definitions)

---

### 2.2 Split sync.rs into Modules

**Current**: `src/handlers/sync.rs` (2400 lines, monolithic)

**Target**: 
```
src/handlers/sync/
  ├── mod.rs                    (re-exports, router)
  ├── traits.rs                 (event validator, applier, permission checker)
  ├── pull.rs                   (GET /api/sync/events, get_sync_hash)
  ├── push.rs                   (POST /api/sync/events)
  ├── validator.rs              (validate_event, structure checks, idempotency)
  ├── applier.rs                (apply_events_to_projections)
  ├── permission.rs             (permission checks)
  ├── snapshot.rs               (snapshot management)
  ├── group.rs                  (contact group sync)
  └── utils.rs                  (helpers: calculate_total_debt, event_read_allowed)
```

**Steps**:
1. Create `sync/` directory
2. Move functions into respective files (no logic changes)
3. Extract helper functions into utils.rs
4. Update imports in sync/mod.rs
5. Run tests after each move (verify no behavior change)

**File organization**:
- **pull.rs** (250 lines) — get_sync_hash, get_sync_events
- **push.rs** (350 lines) — post_sync_events core logic
- **validator.rs** (200 lines) — validate_event, permission checks
- **applier.rs** (300 lines) — apply_events_to_projections, apply_permission_event
- **permission.rs** (150 lines) — permission service calls, checks
- **snapshot.rs** (200 lines) — create_snapshot_json, restore_projections_from_snapshot
- **group.rs** (100 lines) — apply_contact_group_ids_from_event_data
- **utils.rs** (150 lines) — calculate_total_debt, event_read_allowed, helpers

**Effort**: ~6-8 hours (careful refactoring, testing after each move)  
**Risk**: Medium (modularization can introduce subtle bugs), mitigated by tests  
**Tests**: Run entire test suite after each module split, verify 0 test failures

---

### 2.3 Extract Traits Implementation (Defer)

**Don't do this yet.** Keep current functions as-is. Traits are just interface definitions.

Once split is complete and working, THEN consider:
- Making applier implement `EventApplier` trait
- Making validator implement `EventValidator` trait
- This can be done module-by-module

---

## Phase 3: Optimization & Cleanup (Future)

### 3.1 Refactor Individual Modules
Once modules are separated, you can refactor them independently:

```rust
// Example: Refactor push.rs with trait-based design
pub struct SyncPusher {
    validators: Vec<Box<dyn EventValidator>>,
    applier: Box<dyn EventApplier>,
}

impl SyncPusher {
    pub async fn push(&self, events: Vec<Event>) -> Result<SyncPushResponse> {
        // Validate all
        for validator in &self.validators {
            validator.validate(event).await?;
        }
        // Apply all
        for event in &events {
            self.applier.apply(event).await?;
        }
        Ok(response)
    }
}
```

**When to do**: After Phase 2 is complete and working  
**Risk**: Lower (isolated module, can revert easily)

---

### 3.2 Optimize Algorithms
Once code is readable:
- Implement incremental hash caching
- Batch permission checks (instead of per-event)
- Use snapshots for large event logs

---

## Timeline & Effort

| Phase | Task | Effort | Risk | Week |
|-------|------|--------|------|------|
| 1 | Hash performance | 1-2h | Low | W1 |
| 1 | Error handling | 1h | Low | W1 |
| 2 | Extract traits | 1h | None | W2 |
| 2 | Split sync.rs | 6-8h | Medium | W2-W3 |
| 3 | Refactor modules | 4-6h per module | Low | W4+ |

**Total for Phase 1-2**: ~10-12 hours = 1-2 weeks  
**Phase 3**: Ongoing as needed

---

## Success Criteria

**Phase 1**: All tests pass, no behavior change, performance improved for hash calculation
**Phase 2**: All tests pass, no behavior change, code is organized and readable
**Phase 3**: Traits implemented, modules refactored, easier to extend

---

## Risk Mitigation

1. **Run tests after every change** (not at the end)
2. **Small commits** (each module split = one commit)
3. **Code review** (at least one other person checks each commit)
4. **Revert plan** (if something breaks, revert that one commit)
5. **Keep current sync.rs backup** until Phase 2 is 100% done

---

## Related Notes
- [[sync-handler-deep-dive.md]] — Current implementation details
- [[todos.md]] — Updated with phased tasks
