# Permission System Decoupling: User-Scoped vs Wallet-Scoped Architecture

**Status**: 🔄 In Planning  
**Priority**: Phase 5 (after Phase 4 SQL refactoring)  
**Goal**: Enable user-scoped operations alongside wallet-scoped permission system  
**Scope**: ~4-6 hours of architectural work

---

## Full System Context

### Current Architecture (Wallet-Scoped Only)

**From**: merged-features.md, permission-system-deep-dive.md

The system transitioned from:
- **Before**: Global user_id filtering (bad data isolation)
- **Now**: Wallet-scoped everything (multi-wallet system)

```
Current Model:
┌─────────────────────────────────────────┐
│  WALLET (like Discord server)           │
│  ├── wallet_id, owner_id, name          │
│  │                                      │
│  ├─ Membership: owner, admin, member   │
│  │  └─ wallet_users table               │
│  │                                      │
│  ├─ User Groups (per wallet)            │
│  │  ├─ all_users (system)               │
│  │  ├─ Editors (custom)                 │
│  │  └─ VIP_Managers (custom)            │
│  │                                      │
│  ├─ Contact Groups (per wallet)         │
│  │  ├─ all_contacts (system)            │
│  │  ├─ VIP (custom)                     │
│  │  └─ Family (custom)                  │
│  │                                      │
│  ├─ Permission Matrix                   │
│  │  └─ (user_group × contact_group) → actions
│  │                                      │
│  ├─ Wallet Settings                     │
│  │  └─ user_wallet_settings (per user-wallet pair)
│  │                                      │
│  └─ Data                                │
│     ├─ contacts_projection (wallet_id)  │
│     ├─ transactions_projection (wallet_id)
│     └─ events (wallet_id)               │
└─────────────────────────────────────────┘
```

### The Problem: Everything is Wallet-Scoped

| Operation | Current Model | Problem |
|-----------|--------------|---------|
| Create contact | Requires wallet_id | ✅ Correct |
| View permission matrix | Requires wallet_id | ✅ Correct |
| Store user settings (dark_mode, theme) | Requires wallet_id | ❌ Wrong - per-user, not per-wallet |
| Export/backup user data | Requires wallet_id | ❌ Wrong - user's data, not wallet's |
| User authentication | Requires user_id | ✅ Correct |

### Current Issues in Code

**settings.rs** (lines 36, 98):
```rust
// TODO: This should use authenticated user context, not just first user
let user_id = sqlx::query_scalar::<_, Uuid>(
    "SELECT id FROM users_projection LIMIT 1"  // BUG!
)
```

**users.rs** (line 392):
```rust
// No AuthUser extraction, LIMIT 1 hack for backup
let user_id = sqlx::query_scalar::<_, Uuid>(
    "SELECT id FROM users_projection LIMIT 1"  // BUG!
)
```

**wallets.rs** (create_wallet):
```rust
// TODO: Uses LIMIT 1 instead of extracting AuthUser
let user_id = sqlx::query_scalar::<_, Uuid>(
    "SELECT id FROM users_projection LIMIT 1"  // BUG!
)
```

### Root Cause Analysis

1. **Architectural Assumption**: "All operations need wallet context"
2. **Reality**: Some operations are truly user-scoped (settings, backup)
3. **Symptom**: Forced to use LIMIT 1 hack because no wallet_id available
4. **Impact**: 
   - Wrong user's settings could be returned (non-deterministic)
   - Wrong user gets attribution for wallet creation
   - Security/privacy risk

---

## Proposed Dual-Scope Architecture

### Scope Types

```
SCOPE 1: WALLET-SCOPED
├─ Data: contacts, transactions, events
├─ Operations: CRUD with permission checks
├─ Context: wallet_id + user_id + user_role
├─ Permission System: user_groups × contact_groups matrix
└─ Files: contacts.rs, transactions.rs, sync.rs

SCOPE 2: USER-SCOPED (NEW)
├─ Data: user_settings, user backups, user profile
├─ Operations: User reads/writes own settings
├─ Context: user_id only (NO wallet_id)
├─ Permission System: None (user can only access own data)
└─ Files: settings.rs, users.rs

SCOPE 3: CROSS-WALLET (HYBRID)
├─ Data: wallets (owned by user)
├─ Operations: Create wallet, list wallets
├─ Context: user_id (creator/owner)
├─ Permission System: Auth context only (is user logged in?)
└─ Files: wallets.rs
```

### New Database Tables

**user_settings** (USER-SCOPED)
```sql
CREATE TABLE user_settings (
    user_id UUID PRIMARY KEY REFERENCES users_projection(id) ON DELETE CASCADE,
    dark_mode BOOLEAN DEFAULT true,
    default_direction VARCHAR(32) DEFAULT 'give',
    flip_colors BOOLEAN DEFAULT false,
    due_date_enabled BOOLEAN DEFAULT false,
    default_due_date_days INT DEFAULT 30,
    default_due_date_switch BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**user_wallets** (CROSS-WALLET, optional if needed)
```sql
-- Already exists as wallet_users with role tracking
-- Tracks: user → wallet membership + role
CREATE TABLE wallet_users (
    wallet_id UUID REFERENCES wallets(id),
    user_id UUID REFERENCES users_projection(id),
    role VARCHAR(32) CHECK (role IN ('owner', 'admin', 'member')),
    PRIMARY KEY (wallet_id, user_id)
);
```

### Request Flow Comparison

#### WALLET-SCOPED (contacts.rs - NO CHANGES)
```
GET /api/wallets/:wallet_id/contacts
    ↓
Auth Middleware → AuthUser (user_id from JWT)
    ↓
Wallet Context Middleware → WalletContext (wallet_id from path)
    ↓
Verify: User is member of wallet (check wallet_users)
    ↓
Permission Service: Resolve (user_group × contact_group) matrix
    ↓
Handler: ALLOW/DENY based on permissions
```

#### USER-SCOPED (settings.rs - REFACTORED)
```
GET /api/settings
    ↓
Auth Middleware → AuthUser (user_id from JWT)
    ↓
Handler (get_settings): Extract AuthUser
    ↓
Repository: Query user_settings WHERE user_id = auth_user.user_id
    ↓
Return: User's own settings (no permission matrix, no wallet)
```

#### CROSS-WALLET (wallets.rs - PARTIALLY REFACTORED)
```
POST /api/wallets (create)
    ↓
Auth Middleware → AuthUser (user_id from JWT)
    ↓
Handler (create_wallet): Extract AuthUser
    ↓
Set: created_by = auth_user.user_id (not LIMIT 1!)
    ↓
Create wallet and add user as owner
```

---

## Database Schema Implications

### What Changes

| Table | Current | Proposed | Reason |
|-------|---------|----------|--------|
| `user_settings` | Doesn't exist | NEW | Store user preferences (not wallet-scoped) |
| `wallet_users` | UNCHANGED | UNCHANGED | Already tracks wallet membership |
| `user_wallet_settings` | Wallet-scoped | RENAMED to `wallet_user_settings` | Clarify it's wallet-scoped |
| `user_groups` | Wallet-scoped | UNCHANGED | Still used for wallet permissions |
| `contact_groups` | Wallet-scoped | UNCHANGED | Still used for wallet permissions |
| `contacts_projection` | Wallet-scoped | UNCHANGED | Still scoped to wallet |
| `transactions_projection` | Wallet-scoped | UNCHANGED | Still scoped to wallet |
| `events` | Wallet-scoped | UNCHANGED | Still scoped to wallet |

### What Doesn't Change

- Permission matrix (still wallet-scoped)
- User groups (still wallet-scoped)
- Contact groups (still wallet-scoped)
- All wallet operations (still wallet-scoped)

---

## Code Organization Changes

### New Repository Module

```
src/database/repository/user_settings.rs (NEW)
├── get_user_settings_impl(user_id) → UserSettings
├── upsert_user_settings_impl(user_id, settings) → ()
├── update_user_setting_impl(user_id, key, value) → ()
└── delete_user_settings_impl(user_id) → bool
```

### Updated Handlers

```
src/handlers/
├── settings.rs (REFACTORED)
│   ├── get_settings: Extract AuthUser, use user_settings repo
│   └── update_setting: Extract AuthUser, use user_settings repo
│
├── users.rs (REFACTORED)
│   ├── backup: Extract AuthUser, remove LIMIT 1
│   └── Other handlers: Add AuthUser extraction
│
└── wallets.rs (REFACTORED)
    └── create_wallet: Extract AuthUser, use auth_user.user_id as created_by
```

### Unchanged Components

```
src/handlers/
├── contacts.rs (UNCHANGED - wallet-scoped)
├── transactions.rs (UNCHANGED - wallet-scoped)
└── sync.rs (UNCHANGED - wallet-scoped)

src/services/
└── permission_service.rs (UNCHANGED - wallet-scoped)

src/middleware/
├── auth.rs (UNCHANGED - injects AuthUser)
└── wallet_context.rs (UNCHANGED - injects WalletContext)
```

---

## Implementation Strategy

### Phase 1: Create User-Settings Infrastructure (1 hour)

1. **Database Migration**
   - Create `user_settings` table
   - Define schema and defaults

2. **Models**
   - `src/database/models/user_settings.rs`
   - UserSettings struct with all fields

3. **Repository**
   - `src/database/repository/user_settings.rs`
   - CRUD methods for user_settings
   - DatabaseRepository trait extensions in mod.rs

### Phase 2: Refactor Settings Handler (30 min)

1. **settings.rs - get_settings**
   - ADD: Extract `Extension<AuthUser>`
   - REMOVE: `SELECT LIMIT 1` hack
   - CHANGE: Query by `auth_user.user_id`

2. **settings.rs - update_setting**
   - ADD: Extract `Extension<AuthUser>`
   - REMOVE: `SELECT LIMIT 1` hack
   - CHANGE: Query by `auth_user.user_id`

### Phase 3: Refactor Users Handler (30 min)

1. **users.rs - backup**
   - ADD: Extract `Extension<AuthUser>`
   - REMOVE: `SELECT LIMIT 1` hack
   - CHANGE: Use `auth_user.user_id`

2. **users.rs - Other handlers**
   - Audit: Check all handlers for auth context
   - ADD: Extract `Extension<AuthUser>` where needed

### Phase 4: Fix Wallets Handler (15 min)

1. **wallets.rs - create_wallet**
   - ADD: Extract `Extension<AuthUser>`
   - REMOVE: `SELECT LIMIT 1` hack
   - CHANGE: Set `created_by = Some(auth_user.user_id)`

### Phase 5: Verification (30 min)

1. **Confirm No Regressions**
   - contacts.rs: UNCHANGED
   - transactions.rs: UNCHANGED
   - permission_service.rs: UNCHANGED
   - sync.rs: UNCHANGED

2. **Test Coverage**
   - User settings persist
   - Settings isolated per user
   - Wallets created_by correct user
   - Permission matrix still working
   - LIMIT 1 hacks eliminated

---

## Architectural Principles

### 1. Scope Isolation

```
User-Scoped Operations
├─ No wallet_id required
├─ No permission checks
├─ User can only access own data
└─ Fast path: single row lookup

Wallet-Scoped Operations
├─ wallet_id required
├─ Permission matrix enforced
├─ User must be member of wallet
└─ Slower path: permission resolution
```

### 2. Single Responsibility

- **Permission System**: Handles wallet-scoped access control
- **User Settings**: Handles user-level preferences
- **Auth Middleware**: Provides AuthUser context

Each component does one thing well.

### 3. Backwards Compatibility

- All wallet operations unchanged
- Permission matrix unchanged
- User groups unchanged
- Contact groups unchanged

New functionality is purely additive.

### 4. Security Boundaries

```
BOUNDARY 1: Auth Middleware
├─ Only authenticated users proceed
└─ Non-auth routes bypass this

BOUNDARY 2: Wallet Context Middleware
├─ Only wallet-scoped routes use this
└─ User-scoped routes skip this

BOUNDARY 3: Permission Service
├─ Only wallet-scoped operations go through
└─ User-scoped operations don't check permissions
```

---

## Testing Strategy

### Unit Tests
- UserSettings CRUD operations
- AuthUser extraction in handlers
- Model serialization/deserialization

### Integration Tests
- User settings persist across sessions
- Settings isolated between users
- Wallet creation attributes to correct user
- Permission matrix still enforces access
- No data leakage between scopes

### Edge Cases
- User deletes account → settings deleted (CASCADE)
- Settings defaults applied correctly
- Auth context missing → 401 Unauthorized
- Two users accessing same wallet → permission checks enforced
- User accessing different wallets → isolated operations

---

## Benefits

1. ✅ **Eliminates LIMIT 1 Hacks**: Proper authentication
2. ✅ **User-Level Data Isolation**: Settings truly per-user
3. ✅ **Cleaner Architecture**: Separates concerns (wallet vs user)
4. ✅ **Zero Permission System Changes**: Existing permissions untouched
5. ✅ **Security Improvement**: Removes non-deterministic data access
6. ✅ **Foundation for Features**: Enables user preferences, backups, profiles
7. ✅ **Backwards Compatible**: No breaking changes to wallet operations

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Forget AuthUser extraction somewhere | Code review, grep for LIMIT 1, tests |
| Permission checks applied to user-scoped | Never apply permission_service to user_settings |
| User-settings table permissions wrong | Verify with `\dt` and `\d user_settings` |
| Wallets.rs breaks | Keep contact.rs/transaction.rs tests passing |
| Data isolation regression | Write explicit isolation tests |

---

## Timeline

| Phase | Duration | Deliverable | Fixes |
|-------|----------|-------------|-------|
| 1: Infrastructure | 1 hour | user_settings + repo | - |
| 2: settings.rs | 30 min | get/update handlers | TODO: line 36, 98 |
| 3: users.rs | 30 min | backup + others | TODO: line 392 |
| 4: wallets.rs | 15 min | create_wallet | TODO: create_wallet |
| 5: Verification | 30 min | Tests + regression | - |
| **Total** | **~2.5-3 hours** | **Phase 5 complete** | **4 CODE TODOs fixed** |

---

## References

- **Architecture**: vault/architecture.md
- **Decisions**: vault/decisions.md
- **Permission System**: vault/permission-system-deep-dive.md
- **Auth System**: vault/auth.md
- **Merged Features**: vault/merged-features.md
- **TODOs**: vault/todos.md (HIGH PRIORITY section)

---

## Related Issues

This plan addresses:
- 🔴 HIGH PRIORITY (from todos.md): Authentication & Authorization Fixes
  - [ ] Fix settings.rs handlers missing AuthUser extraction
  - [ ] Fix users.rs handlers missing AuthUser extraction
  - [ ] Fix wallets.rs create_wallet missing AuthUser extraction

---

## Extended Scope: All Permission-Related TODOs

Beyond the authentication context fixes, the full permission system decoupling includes:

### Phase 6: Auth Route Separation (1-2 hours)
**From todos.md line 417**

Separate admin/user auth into distinct route groups and middleware:
- Create `admin_routes` (admin_auth_middleware only)
- Create `user_routes` (user_auth_middleware only)
- Create `shared_routes` (auth_middleware for both)
- Add `is_admin` field to AuthUser struct
- Add handler-level role checks to `/api/admin/*` endpoints
- Test: Verify admin tokens can't access user routes and vice versa

**Files affected**:
- src/main.rs - Route configuration
- src/middleware/auth.rs - Separate middleware functions
- src/handlers/admin.rs - Add is_admin checks
- Update handler signatures

### Phase 7: Event Trait-Based Permissions (2-3 hours)
**From todos.md line 434**

Refactor events to use trait-based permission declarations:

```rust
pub trait Event {
    fn required_permission(&self) -> Option<PermissionAction>;
    fn aggregate_type(&self) -> AggregateType;
    fn resource_type(&self) -> ResourceType;
}
```

**Benefits**:
- Single source of truth for permissions
- Impossible to create event without declaring permission
- Self-documenting
- Enables removing hardcoded owner/admin bypass

**Implementation**:
- Define Event trait in src/database/models/event.rs
- Implement for CONTACT_CREATED, TRANSACTION_UPDATED, etc.
- Remove scattered match statements
- Remove hardcoded owner/admin bypass (always check permission matrix)
- Update sync handler to use trait methods

**Files affected**:
- src/database/models/event.rs - Define trait
- src/handlers/sync.rs - Use trait methods instead of match
- src/services/permission_service.rs - Always check, no hardcoded bypass

### Phase 8: Permission System Optimizations (2-3 hours)
**From todos.md line 450-478**

#### 8.1: Consolidate Permission Aliases
**Line 450**: Consolidate contact:update and contact:edit aliases
- Use single canonical action name (contact:update)
- Remove all contact:edit references
- Update permission matrix, handlers, permission service
- Update tests

#### 8.2: Define Wallet Role Semantics
**Line 456**: Document and enforce wallet role semantics
```
OWNER: Immovable role, cannot be removed, has all permissions, bypasses nothing
ADMIN: Manages permissions BUT cannot modify own permissions (prevent escalation)
MEMBER: Group-based permissions via permission matrix
```
- Enforce: Admin cannot change own permissions
- Enforce: Owner cannot be removed
- Test: Role semantics

#### 8.3: Optimize Permission Matrix Resolution
**Line 471**: Single SQL query instead of multiple queries
- Current: Fetch user_groups + contact_groups separately, then query matrix
- Better: Single JOIN query resolving everything
- Benefit: Reduced database round-trips

#### 8.4: Optimize events:read Permission
**Line 464**: Fine-grained events:read enforcement
- Current: Not enforced (all users can GET /api/sync/events)
- Better: Send full events to permitted users, projections only to non-permitted
- Implementation: Check events:read permission before returning events

#### 8.5: Normalize Owner/Admin Bypass
**Line 478**: Remove hardcoded owner/admin bypass logic
- Paired with Phase 7 (Event trait-based permissions)
- After Event trait: ALWAYS call can_perform(), no exceptions
- Owner/Admin still have all permissions in matrix
- Benefit: Unified permission model, single source of truth

**Files affected**:
- src/services/permission_service.rs - Optimize, normalize
- src/handlers/sync.rs - Use traits, no hardcoded bypass
- src/database/repository/permissions.rs - Single query optimization
- migrations/ - Add role semantics constraints

### Phase 9: Users Architecture Refactoring (Future)
**From todos.md line 242** - Deferred (separate work)

Event-sourced per-user data isolation:
- Create USER_CREATED, USER_UPDATED, USER_DELETED events
- Separate events table per user (or partition by user_id)
- Complete user data isolation
- Filter all queries by authenticated user_id
- Add permission checks for cross-user operations
- Note: Larger architectural change, depends on phases 1-8

---

## Complete Implementation Timeline

| Phase | Duration | Deliverable | Priority |
|-------|----------|-------------|----------|
| 1: User-Settings Infrastructure | 1 hour | user_settings table + repo | 🔴 HIGH |
| 2: settings.rs Refactoring | 30 min | Extract AuthUser | 🔴 HIGH |
| 3: users.rs Refactoring | 30 min | Extract AuthUser | 🔴 HIGH |
| 4: wallets.rs Refactoring | 15 min | Extract AuthUser | 🔴 HIGH |
| 5: Verification | 30 min | Tests + regression | 🔴 HIGH |
| 6: Auth Route Separation | 1-2 hours | Admin/user routes | 🟡 MEDIUM |
| 7: Event Trait-Based Perms | 2-3 hours | Permission traits | 🟡 MEDIUM |
| 8: Permission Optimizations | 2-3 hours | Aliases, semantics, queries | 🟡 MEDIUM |
| 9: Users Architecture | 4-6 hours | Event-sourced users | 🟢 LOW |
| **Total** | **~12-18 hours** | **Full decoupling** | **Mixed** |

**Recommended approach**:
- Do Phases 1-5 now (2.5-3 hours) - Fixes HIGH PRIORITY TODOs
- Do Phases 6-8 in Phase 5B (5-8 hours) - Improves permission system
- Do Phase 9 later (separate initiative) - Architectural work

---

## All TODOs Addressed

### HIGH PRIORITY (todos.md 🔴)
- ✅ Phase 2: Fix settings.rs handlers missing AuthUser extraction (line 36, 98)
- ✅ Phase 3: Fix users.rs handlers missing AuthUser extraction (line 392)
- ✅ Phase 4: Fix create_wallet handler missing AuthUser extraction (line 78)
- ⬜ (Separate): Enforce TLS encryption for database (line 84)
- ⬜ (Separate): Enforce HTTPS for client-to-backend (line 225)

### MEDIUM PRIORITY (todos.md 🟡)
- ✅ Phase 6: Separate admin/user auth into distinct route groups (line 417)
- ✅ Phase 7: Refactor events to use trait-based permission declarations (line 434)
- ✅ Phase 8.1: Consolidate contact:update and contact:edit aliases (line 450)
- ✅ Phase 8.2: Define clear wallet role semantics (line 456)
- ✅ Phase 8.3: Optimize permission matrix resolution to single SQL query (line 471)
- ✅ Phase 8.4: Optimize events:read permission enforcement (line 464)
- ✅ Phase 8.5: Normalize hardcoded owner/admin bypass (line 478)

### LOW PRIORITY (todos.md 🟢)
- ✅ Phase 9: Convert users to event-sourced system with per-user tables (line 242)
- ⬜ (Separate): Sync Hash Performance - incremental calculation (line 251)
- ⬜ (Separate): Sync Permission Failure Recovery (line 275)

---

## Implementation Recommendation

**Tier 1 (Fix Critical Auth Bugs - Do First)**
- Phases 1-5: ~2.5-3 hours
- Fixes HIGH PRIORITY TODOs
- Enables proper authentication context

**Tier 2 (Improve Permission System - Do After Tier 1)**
- Phases 6-8: ~5-8 hours
- Implements permission system improvements from todos.md
- Better architecture and performance

**Tier 3 (Long-term Architecture - Do Later)**
- Phase 9: ~4-6 hours
- Event-sourced user isolation
- Requires phases 1-8 complete first

## Next Steps

1. ✅ Approve architecture (this document)
2. ⬜ **Start Tier 1** (Phases 1-5) - Critical auth fixes
3. ⬜ Plan Tier 2 (Phases 6-8) - Permission improvements
4. ⬜ Plan Tier 3 (Phase 9) - User architecture refactoring
