# Idempotency & Reliability Improvement Plan

## Current Issues
1. ❌ No idempotency keys - duplicate requests can create duplicate data
2. ❌ No version tracking in projections - can't detect conflicts
3. ❌ Direct projection updates - not idempotent
4. ✅ Event sourcing exists (append-only)
5. ✅ Soft deletes exist (is_deleted flag)

## Solution: Enhanced PostgreSQL Event Sourcing

### Phase 1: Add Idempotency Keys

**Migration: Add idempotency_key to events table**
```sql
ALTER TABLE events 
ADD COLUMN idempotency_key VARCHAR(255) UNIQUE;

CREATE INDEX idx_events_idempotency ON events(idempotency_key) WHERE idempotency_key IS NOT NULL;
```

**How it works:**
- Client sends `Idempotency-Key` header (UUID)
- Server checks if key exists → return existing result
- If new → process and store key
- Prevents duplicate operations

### Phase 2: Add Version Tracking to Projections

**Migration: Add version column**
```sql
ALTER TABLE contacts_projection 
ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

ALTER TABLE transactions_projection 
ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

CREATE INDEX idx_contacts_version ON contacts_projection(id, version);
CREATE INDEX idx_transactions_version ON transactions_projection(id, version);
```

**How it works:**
- Each update increments version
- Client sends expected version in update request
- Server checks version matches → process
- If mismatch → return conflict error
- Client resolves conflict

### Phase 3: Make Projection Updates Idempotent

**Use INSERT ... ON CONFLICT with version check:**
```sql
INSERT INTO contacts_projection (...)
VALUES (...)
ON CONFLICT (id) 
DO UPDATE SET 
    ...,
    version = contacts_projection.version + 1,
    updated_at = NOW()
WHERE contacts_projection.version = $expected_version
RETURNING version;
```

### Phase 4: Sync Protocol Improvements

**Option A: Event-based sync (Recommended)**
- Client tracks `last_synced_event_id`
- Server returns events since that ID
- Client replays events locally
- Idempotent by event_id

**Option B: Version-based sync**
- Client tracks entity versions
- Server returns entities with versions > client's
- Client merges based on version
- Conflict resolution: last-write-wins or merge

## Alternative: Use EventStore (Open Source)

**EventStore** is a dedicated event store with:
- ✅ Built-in idempotency
- ✅ Optimistic concurrency (version tracking)
- ✅ Append-only by design
- ✅ Built-in projections
- ✅ Multi-device sync support
- ✅ PostgreSQL compatible (can use as read model)

**Pros:**
- Battle-tested for event sourcing
- Handles all your requirements out of the box
- Great performance
- Good documentation

**Cons:**
- Another service to run
- Learning curve
- Migration effort

## Recommendation

**Short term (1-2 weeks):**
1. Add idempotency keys to events
2. Add version tracking to projections
3. Implement optimistic locking
4. Fix sync protocol

**Long term (if still having issues):**
- Consider EventStore for dedicated event store
- Keep PostgreSQL for projections/read models
- Use EventStore's sync capabilities

## Implementation Priority

1. **Idempotency keys** (Critical - prevents duplicates)
2. **Version tracking** (Critical - prevents conflicts)
3. **Optimistic locking** (Critical - safe updates)
4. **Sync protocol** (Important - reliable sync)
5. **EventStore migration** (If needed - last resort)
