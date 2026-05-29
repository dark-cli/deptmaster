---
tags:
  - architecture
  - permission-system
  - refactoring
  - high-priority
---

# Permission System Isolation & Refinement

**Status**: 🔴 In Planning  
**Priority**: MEDIUM (follows Phase 5 user-settings completion)  
**Goal**: Consolidate scattered permission logic into isolated model with clean high-level API

---

## Executive Summary

The permission system logic is currently **scattered and inefficient**:
- **Permission checks** spread across `sync.rs` (108KB), `wallets.rs` (78KB), and `permission_service.rs` (293 lines)
- **Inefficient calculation**: Multiple queries per permission check, hardcoded owner/admin bypass
- **Confusing enforcement**: `map_event_to_permission_action()` function + scattered permission validation
- **No single source of truth**: Permission requirements defined in multiple places

**Goal**: Create a **Permission Model** as the single source of truth that:
- Consolidates all permission logic
- Exposes only high-level functions: `can_perform_action()`, `resolve_permissions()`, etc.
- Eliminates inefficient permission resolution patterns
- Makes permission enforcement transparent to handlers

---

## Current State Analysis

### Where Permission Logic Lives

#### 1. **sync.rs** (108KB - 2,200+ lines)
- **Line 71-106**: `map_event_to_permission_action()` - Maps event types to permission requirements
- **Line 496-508**: Permission event validation logic
- **Line 601-648**: Preflight permission checks (mixed with event validation)
- **Line 611-631**: Scattered `can_perform()` calls throughout event loop
- **Line 2187-2188**: Permission event application

**Problem**: Permission validation is mixed with sync business logic, making both hard to understand.

#### 2. **wallets.rs** (78KB - 1,400+ lines)
- **Line 17-47**: `validate_permission_dependencies()` - Ensures write implies read
- **Line 216-244**: `initialize_wallet_permissions()` - Sets up default groups
- **Line 396, 475, 519, 853, 921**: Scattered role checks (`owner` || `admin`)
- **Line 1045**: `/me/permissions` endpoint mixing API and permission logic

**Problem**: Wallet-specific role checks duplicated in multiple places; no abstraction.

#### 3. **permission_service.rs** (293 lines)
- **Line 23-46**: `can_perform()` - Hardcoded owner/admin bypass + matrix resolution
- **Line 50-83**: `can_perform_action_on_contact_group()` - Contact group-specific
- **Line 95-185**: `resolve_allowed_actions()` - Matrix resolution via multiple queries
- **Line 186-283**: `sync_read_context()` - Read permission caching for sync

**Problem**: Multiple queries per permission check; no optimization for batch operations.

---

## Problems Identified

### 1. **Inefficient Permission Resolution**
```
Current flow:
  for each event in batch:
    if user is owner/admin:
      allow (hardcoded)
    else:
      call can_perform() which:
        - Fetch user groups (query 1)
        - Fetch contact groups (query 2)
        - Query permission matrix (query 3)
        - Total: ~3 queries per event
```

**Issue**: For 100 events, 300 queries. No batching, no caching.

### 2. **Scattered Permission Requirements**
```
Problem:
  - map_event_to_permission_action() in sync.rs
  - validate_permission_dependencies() in wallets.rs
  - Action names hardcoded as strings
  - contact:update vs contact:edit aliases cause confusion

Solution:
  - Define permissions as enums: enum Action { ContactCreate, ContactUpdate, ... }
  - Each event declares required_permission in its definition
  - Single source of truth
```

### 3. **Hardcoded Owner/Admin Bypass**
```rust
// Pattern repeated everywhere:
if user_role == "owner" || user_role == "admin" {
    return Ok(true);  // Hardcoded bypass
}
// ... then check matrix

Problem:
  - Impossible to enforce permissions on admins/owners
  - Can't audit what permissions they actually use
  - Easy to accidentally skip permission checks

Solution:
  - Include owner/admin in permission matrix (system group with all actions)
  - Everyone goes through same can_perform() check
  - Single code path for all users
```

### 4. **Confusing Error Handling**
```
Current:
  - Batch rejected with generic "DEBITUM_INSUFFICIENT_PERMISSION"
  - User doesn't know which event failed
  - Can't recover (must retry entire batch)

Needed:
  - Per-event failure information
  - Which permission was required
  - Which event failed
  - Enables client recovery
```

### 5. **Multiple Queries for Single Permission Check**
```
Current resolve_allowed_actions():
  Query 1: Get user groups
  Query 2: Get contact groups
  Query 3: Check permission matrix
  
Better: Single JOIN query
  SELECT DISTINCT pa.name
  FROM user_groups ug
  JOIN user_group_members ugm ON ugm.user_group_id = ug.id
  JOIN group_permission_matrix m ON m.user_group_id = ug.id
  JOIN contact_groups cg ON cg.id = m.contact_group_id
  JOIN permission_actions pa ON pa.id = m.permission_action_id
  WHERE ug.wallet_id = $1 AND ugm.user_id = $2 AND ...
```

---

## Proposed Architecture

### Permission Model Components

#### 1. **Action Types (Enum-based)**
```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Action {
    // Contact actions
    ContactCreate,
    ContactRead,
    ContactUpdate,
    ContactDelete,
    
    // Transaction actions
    TransactionCreate,
    TransactionRead,
    TransactionUpdate,
    TransactionClose,
    
    // Wallet actions
    WalletRead,
    WalletUpdate,
    WalletAddMember,
    WalletRemoveMember,
    
    // Event actions
    EventsRead,
}

impl Action {
    pub fn as_str(&self) -> &'static str { ... }
    pub fn from_str(s: &str) -> Option<Self> { ... }
}
```

**Benefits**:
- Type-safe, no string errors
- Single source of truth
- Easy to enumerate all permissions
- Self-documenting

#### 2. **Resource Type Definition**
```rust
#[derive(Debug, Clone)]
pub enum Resource {
    Contact(Uuid),
    Transaction(Uuid),
    Wallet(Uuid),
    AllContacts,
    AllTransactions,
}

impl Resource {
    pub fn resource_type(&self) -> ResourceType { ... }
    pub fn id(&self) -> Option<Uuid> { ... }
}
```

#### 3. **Permission Context**
```rust
pub struct PermissionContext {
    wallet_id: Uuid,
    user_id: Uuid,
    user_role: WalletRole,  // enum: Owner, Admin, Member
}

pub enum WalletRole {
    Owner,    // Immovable, all permissions always
    Admin,    // Manages permissions, has all except own
    Member,   // Group-based permissions
}
```

#### 4. **Permission Model (Batch-Only API)**
```rust
pub struct PermissionModel {
    pool: PgPool,
}

impl PermissionModel {
    /// Check permissions for a batch of (action, resource) pairs
    /// Even single checks pass as Vec with one item
    /// 
    /// Returns: Vec<bool> where true = allowed, false = denied
    /// Order matches input checks order
    pub async fn check_permissions(
        &self,
        ctx: &PermissionContext,
        checks: Vec<(Action, Resource)>,
    ) -> Result<Vec<bool>, Error>;
    
    /// Validate permission dependencies
    pub fn validate_dependencies(actions: &[Action]) -> Result<(), String>;
}
```

**Key Design**:
- **Single method**: `check_permissions()` - no per-item API
- **Batch from start**: Forces efficient batch operations
- **Simple list contract**: Input/output aligned by index
- **Even singles use batch**: Single check still passes `vec![(action, resource)]`

### Integration Points

#### Handler Layer (Simple Case)
```rust
// Before: scattered checks
if user_role == "owner" || user_role == "admin" {
    // ... do operation
}

// After: single batch check (even for one item)
let ctx = PermissionContext::new(wallet_id, user_id, user_role);
let allowed = permission_model.check_permissions(&ctx, vec![
    (Action::ContactCreate, Resource::AllContacts)
]).await?;

if allowed[0] {
    // ... do operation
}
```

#### Sync Handler (Batch Case - Most Common)
```rust
// Before: mixed logic + 3 queries per event
for event in events {
    if let Some((action, resource_type, resource_id)) = map_event_to_permission_action(...) {
        if !can_perform(...) {  // 3 queries here
            return Err(insufficient_permission_response());
        }
    }
}
// Total: 300 queries for 100 events

// After: single batch query
let ctx = PermissionContext::new(...);

// Build checks list (1 query for entire batch)
let checks: Vec<_> = events.iter().map(|event| {
    (event.required_action(), event.required_resource())
}).collect();

let allowed = permission_model.check_permissions(&ctx, checks).await?;

// Check results aligned by index
for (i, event) in events.iter().enumerate() {
    if !allowed[i] {
        return Err(PermissionError::Denied(event.id(), event.required_action()));
    }
}
// Total: 1 query for entire batch
```

---

## Implementation Plan

### Phase 1: Foundation (2-3 hours)
**Goal**: Create clean permission model structure without breaking existing code

1. **Create Permission Enums**
   - File: `src/permissions/action.rs` - Action, WalletRole enums
   - File: `src/permissions/resource.rs` - Resource enum
   - File: `src/permissions/context.rs` - PermissionContext

2. **Create Permission Model**
   - File: `src/permissions/model.rs` - PermissionModel struct with batch-only API
   - Implement: `check_permissions()` (batch), `validate_dependencies()`
   - Single query per batch, not per item
   - No changes to database, just optimized query logic

3. **Module Organization**
   ```
   src/
   └── permissions/
       ├── mod.rs           (exports, public API)
       ├── action.rs        (Action enum)
       ├── resource.rs      (Resource enum)
       ├── context.rs       (PermissionContext)
       ├── model.rs         (PermissionModel - main check_permissions() API)
       ├── resolver.rs      (Internal: permission resolution logic)
       └── queries.rs       (SQL queries: single JOIN, not 3-5 separate)
   ```

### Phase 2: Gradual Migration (3-4 hours)
**Goal**: Migrate handlers one by one to use new Permission Model

1. **Start with Settings Handlers**
   - `src/handlers/settings.rs` - Get/update user settings (simpler, no complex permissions)
   - Verify new API works

2. **Migrate Wallet Handlers**
   - `src/handlers/wallets.rs` - Replace role checks with Permission Model
   - Remove `validate_permission_dependencies()` - use Permission Model instead
   - Update `initialize_wallet_permissions()` to use model

3. **Migrate Sync Handler**
   - `src/handlers/sync.rs` - Replace permission checks with model
   - Remove `map_event_to_permission_action()` - use event traits instead
   - Batch permission checks for 100+ events

4. **Run Tests After Each Migrate**
   - Verify existing behavior unchanged
   - No new functionality, just refactored API

### Phase 3: Advanced Optimization (1-2 hours, OPTIONAL)
**Goal**: Further optimize permission resolution with single SQL JOIN

1. **Single SQL Query Optimization** (INCLUDED IN PHASE 1 as part of check_permissions)
   - **Current approach** (3-5 separate queries per check):
     1. `resolve_user_groups()` - Gets user's groups
     2. `resolve_contact_groups_for_resource()` - Gets contact groups (2-3 sub-queries)
     3. `resolve_allowed_actions()` - Queries permission matrix
   
   - **Optimized approach** (single JOIN query):
     ```sql
     SELECT DISTINCT pa.name
     FROM user_groups ug
     JOIN user_group_members ugm ON ugm.user_group_id = ug.id
     JOIN group_permission_matrix m ON m.user_group_id = ug.id
     JOIN contact_groups cg ON cg.id = m.contact_group_id
     JOIN contact_group_members cgm ON cgm.contact_group_id = cg.id 
       OR cg.name = 'all_contacts'
     JOIN permission_actions pa ON pa.id = m.permission_action_id
     WHERE ug.wallet_id = $1 
       AND ugm.user_id = $2
       AND (cgm.contact_id = $3 OR cg.name = 'all_contacts')
     ```
   
   - **Benefit**: Single database round-trip instead of 3-5
   - **Cost**: Complex JOIN, must test correctness
   - **File**: `src/permissions/queries.rs` - SQL as constant strings
   - **Testing**: Verify single query returns same results as current approach

2. **Caching Strategy** (optional, Phase 3 only if needed)
   - Cache user groups per wallet per user
   - Cache permission matrix per wallet
   - Invalidate on permission changes
   - Only implement if profiling shows cache benefit after Phase 1-2

### Phase 4: Event Trait Declarations (2-3 hours, FUTURE)
**Goal**: Move permission requirements into event definitions

```rust
pub trait Event {
    fn required_action(&self) -> Action;
    fn required_resource(&self) -> Resource;
    fn aggregate_type(&self) -> &str;
}

impl Event for ContactCreatedEvent {
    fn required_action(&self) -> Action { Action::ContactCreate }
    fn required_resource(&self) -> Resource { Resource::AllContacts }
    // ...
}
```

**Benefits**:
- No more `map_event_to_permission_action()` function
- Permission requirement defined in event struct
- Impossible to create event without declaring permission
- Self-documenting

---

## Database Schema Changes

**None required for Phase 1-3**

The new Permission Model wraps existing tables:
- `user_groups`
- `contact_groups`
- `group_permission_matrix`
- `permission_actions`

Future optimization (Phase 3) might add caching tables:
- `permission_cache(wallet_id, user_id, user_role, action_hash, last_updated)`
- Invalidated on permission changes

---

## Benefits

### Architectural Clarity
- Single place to understand permission logic
- Clean high-level API for handlers
- Self-contained permission module

### Performance
- Batch operations instead of per-event queries
- Caching reduces redundant lookups
- Single SQL query instead of 3 for matrix resolution
- 100 events: 300 queries → ~10 queries

### Maintainability
- Permission logic isolated, easier to modify
- High-level API hides complexity
- Type-safe (enums instead of strings)
- Testable in isolation

### Security
- All permission checks go through same code path
- No forgotten checks scattered in handlers
- Audit trail of permission usage
- Can enforce permissions on owner/admin if needed

---

## Verification Strategy

### Unit Tests
```rust
#[test]
async fn test_owner_has_all_permissions() { }

#[test]
async fn test_member_only_has_assigned_permissions() { }

#[test]
async fn test_permission_dependencies_validated() { }

#[test]
async fn test_batch_operations_same_as_individual() { }
```

### Integration Tests
```rust
#[tokio::test]
async fn test_permission_model_with_real_database() { }

#[tokio::test]
async fn test_sync_handler_uses_permission_model() { }

#[tokio::test]
async fn test_wallet_handlers_use_permission_model() { }
```

### Performance Benchmarks
```
Before: 100 events = 300 queries, 2.5s
After:  100 events = ~10 queries, 0.1s
```

---

## Timeline

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| 1: Foundation + SQL Optimization | 2-4h | Permission model + single JOIN query |
| 2: Gradual Migration | 3-4h | Handlers migrated, tests passing |
| 3: Optional Caching | 0-2h | Cache layer if profiling shows benefit |
| 4: Event Traits | 2-3h | Event-based permission declarations (FUTURE) |
| **Total** | **7-13h** | **Complete permission isolation + optimized queries** |

**Phase 1 includes**:
- ✅ Batch-only API design
- ✅ Single JOIN query (3-5 queries → 1 query)
- ✅ Enums for type safety
- ✅ Permission module structure

---

## Open Questions

1. **Should owner/admin still bypass all checks?**
   - Current: Hardcoded bypass
   - Option A: Keep bypass (current behavior)
   - Option B: Remove bypass, include in permission matrix (stricter)
   - Recommendation: Option A for now (Phase 1-3), revisit in Phase 4

2. **What about dynamic groups (overdue, we_owe, they_owe)?**
   - Currently placeholders
   - Permission Model will support them (groups are just IDs)
   - Implementation: Future feature, not blocking Phase 1-3

3. **Should permissions be audited?**
   - Track which permissions each user actually uses
   - Useful for security review
   - Implementation: Future optimization

---

## Related TODOs

From `vault/todos.md`:
- Line 434-448: Event trait-based permission declarations
- Line 450-454: Consolidate action aliases (contact:update vs contact:edit)
- Line 456-462: Define wallet role semantics
- Line 471-476: Single SQL query optimization
- Line 478-484: Normalize owner/admin bypass to permission matrix
- Line 302-350: Sync handler refactoring (phased approach)

---

## Next Steps

1. ✅ **Review this plan** with team
2. ⬜ **Approve scope** for Phase 1 (foundation only)
3. ⬜ **Implement Phase 1** - Create permission model structure
4. ⬜ **Run tests** - Verify no regressions
5. ⬜ **Commit Phase 1** 
6. ⬜ **Proceed with Phase 2-4** in subsequent sessions

---

## Success Criteria

- ✅ Permission Model compiles without errors
- ✅ All existing tests pass without modification
- ✅ New API is simpler than current scattered logic
- ✅ Handlers using new API are easier to understand
- ✅ No performance degradation (same or faster)
- ✅ Permission logic is now in single isolated module
