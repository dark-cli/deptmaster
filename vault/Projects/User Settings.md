# User Settings: Authentication Context & Scope Decoupling

**Status**: 🔄 In Planning  
**Priority**: Phase 5 (follows Phase 4 SQL refactoring)  
**Goal**: Eliminate `SELECT LIMIT 1` hack and implement proper user-scoped operations

---

## Problem Statement

### Critical Issues (From todos.md)

**HIGH PRIORITY - Authentication & Authorization Fixes**:
1. **Fix settings.rs & users.rs handlers missing AuthUser extraction** (CODE TODO)
   - File: `backend/rust-api/src/handlers/settings.rs` (line 36, 98)
   - File: `backend/rust-api/src/handlers/users.rs` (line 392)
   - Issue: Uses `SELECT id FROM users_projection LIMIT 1` instead of extracting user from auth
   - Fix: Extract AuthUser from middleware, use authenticated user_id
   - Test: Verify handlers operate on correct authenticated user
   - **This plan addresses this issue directly**

2. **Fix create_wallet handler missing AuthUser extraction** (CODE TODO)
   - File: `backend/rust-api/src/handlers/wallets.rs` (create_wallet)
   - Same issue: Should attribute wallet to authenticated user, not first user
   - Fix: Extract AuthUser, use auth_user.user_id as created_by
   - **Separate from this plan but same pattern**

### Current Issues

1. **Authentication Context Missing**: settings.rs and users.rs use this hack:
   ```sql
   SELECT id FROM users_projection LIMIT 1
   ```
   This returns ANY user instead of the authenticated user (non-deterministic, security risk).

2. **Auth Context Available But Unused**: 
   - `AuthUser` middleware (auth.rs) successfully extracts user_id and email from JWT
   - However, settings.rs and users.rs don't extract `AuthUser` from request extensions
   - Result: No way to know which user is making the request

3. **Tight Permission Coupling**:
   - Permission system is wallet-scoped only (user_groups, contact_groups have wallet_id)
   - Prevents user-level operations without wallet context
   - Settings stored per wallet instead of per user

4. **Data Isolation Risk**:
   - `user_wallet_settings` stores wallet-specific defaults (correct)
   - But user-level settings (dark_mode, theme) should never be wallet-dependent
   - Current LIMIT 1 hack means settings retrieved for wrong user

### Root Cause

The permission system was designed entirely around wallets (Discord-style):
- Every user_group is scoped to a wallet_id
- Every contact_group is scoped to a wallet_id
- Permission matrix is (user_group × contact_group) within a wallet

This is correct for permission enforcement, but creates a false constraint for user-level operations.

---

## Current Architecture (Wallet-Scoped)

### Existing Permission System

**From**: `vault/permission-system-deep-dive.md`

```
permission_actions (global)
├── id, name (contact:create, transaction:read, etc.)

user_groups (WALLET-SCOPED)
├── id, wallet_id, name, is_system
└── user_group_members → users_projection

contact_groups (WALLET-SCOPED)
├── id, wallet_id, name, type, is_system
└── contact_group_members → contacts_projection

group_permission_matrix (WALLET-SCOPED)
└── (user_group, contact_group, action) tuples

user_wallet_settings (WALLET-SCOPED)
└── wallet_id, user_id, default_contact_group_ids, default_transaction_group_ids
```

**Key Flow**:
1. Auth middleware extracts `AuthUser` from JWT (user_id, email)
2. Wallet context middleware extracts wallet_id from path/header/query
3. Permission service resolves allowed actions via wallet-scoped groups
4. Handlers enforce permission checks before allowing operations

**This is perfect for wallet operations** (wallets.rs, contacts.rs, transactions.rs)

### Existing Auth System

**From**: `vault/auth.md`

```
Authorization Header
    ↓
JWT Decode & Validate
    ↓
User Existence Check (users_projection or admin_users)
    ↓
AuthUser Injection (user_id, email) → extensions
    ↓
Handler extracts Extension<AuthUser>
```

**Currently Used By**:
- ✅ change_password handler (users.rs:212)
- ✅ All handlers that need user identity

**NOT Currently Used By** (BUGS):
- ❌ get_settings (settings.rs:33) - TODO comment line 36
- ❌ update_setting (settings.rs:93) - TODO comment line 98
- ❌ backup (users.rs:392) - No extraction, uses LIMIT 1 hack

---

## Proposed Architecture (Dual-Scope)

### Key Principle

**Two separate permission scopes, not one**:

```
WALLET-SCOPED OPERATIONS          USER-SCOPED OPERATIONS
(wallets.rs, contacts.rs)        (users.rs, settings.rs)
        ↓                                 ↓
  Uses: user_groups          Uses: no groups needed
        contact_groups        wallet_context: OPTIONAL
        permission_matrix     auth_context: REQUIRED
        wallet_context
        auth_context
```

### New User-Scoped Settings Table

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

**Why separate?**
- Settings are inherently user-scoped (not per-wallet)
- A user's theme preference doesn't change between wallets
- User backup should work regardless of which wallet is active
- Fixes: User A's backup won't return User B's data (LIMIT 1 bug eliminated)

### Database Schema Changes

1. **`user_wallet_settings`** (UNCHANGED - wallet-scoped defaults)
   - Stores: wallet_id, user_id, default_contact_group_ids, default_transaction_group_ids
   - Purpose: When creating contacts/transactions, which groups should they be in by default?
   - Scoping: Per wallet (each wallet can have different defaults)

2. **`user_settings`** (NEW - user-scoped preferences)
   - Stores: user_id, dark_mode, default_direction, flip_colors, due_date_enabled, etc.
   - Purpose: User's global app preferences
   - Scoping: Per user (not per wallet)

### Code Organization

```
src/database/
├── repository/
│   ├── permissions.rs (UNCHANGED - wallet-scoped only)
│   ├── user_settings.rs (NEW - user-scoped settings CRUD)
│   └── mod.rs (add UserSettings trait methods)
├── models/
│   ├── permission.rs (UNCHANGED)
│   └── user_settings.rs (NEW model struct)

src/handlers/
├── wallets.rs (PARTIALLY UPDATED - fix create_wallet AuthUser)
├── contacts.rs (UNCHANGED - uses wallet context + permission matrix)
├── transactions.rs (UNCHANGED - uses wallet context + permission matrix)
├── settings.rs (REFACTORED - extract AuthUser, use user_settings repo)
└── users.rs (REFACTORED - extract AuthUser, remove LIMIT 1 hack)

src/middleware/
├── auth.rs (UNCHANGED - still injects AuthUser)
└── wallet_context.rs (UNCHANGED - still injects WalletContext)
```

### Request Flow Comparison

#### Wallet-Scoped (contacts.rs) - NO CHANGES
```
HTTP Request
    ↓ Auth Middleware
    ├→ Extract JWT → AuthUser
    ↓
    ├→ Wallet Context Middleware
    ├→ Extract wallet_id → WalletContext
    ├→ Verify user is member of wallet
    ↓
    ├→ Handler (create_contact)
    ├→ Permission Service
    ├→ Query user_groups + contact_groups from wallet
    ├→ Resolve permission_matrix
    ├→ ALLOW/DENY
```

#### User-Scoped (settings.rs) - REFACTORED
```
HTTP Request
    ↓ Auth Middleware
    ├→ Extract JWT → AuthUser (user_id, email)
    ↓
    ├→ Handler (get_settings)
    ├→ Extract AuthUser from extensions
    ├→ Use auth_user.user_id directly (NO wallet context needed)
    ├→ Query user_settings table
    ├→ Return user's preferences
```

---

## Implementation Plan

### Phase 1: Create User-Scoped Settings (1 hour)

**1.1 Database Migration**
- File: `migrations/XXX_create_user_settings_table.sql`
- Creates: user_settings table with all preference columns
- Includes: Default values matching current user_wallet_settings logic

**1.2 Model Definition**
- File: `src/database/models/user_settings.rs`
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserSettings {
    pub user_id: Uuid,
    pub dark_mode: bool,
    pub default_direction: String,
    pub flip_colors: bool,
    pub due_date_enabled: bool,
    pub default_due_date_days: i32,
    pub default_due_date_switch: bool,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}
```

**1.3 Repository Methods**
- File: `src/database/repository/user_settings.rs`
- Methods:
  - `get_user_settings_impl(user_id) → Option<UserSettings>`
  - `upsert_user_settings_impl(user_id, settings) → ()`
  - `update_user_setting_impl(user_id, key, value) → ()`

**1.4 Trait Methods**
- File: `src/database/repository/mod.rs`
- Add trait signatures for above methods
- Add implementations that delegate to _impl methods

### Phase 2: Refactor settings.rs (30 min)

**2.1 Update get_settings Handler**
```rust
pub async fn get_settings(
    Extension(auth_user): Extension<AuthUser>,  // ADD THIS
    State(state): State<AppState>,
) -> Result<Json<SettingsResponse>, ...> {
    let db = Database::new((*state.db_pool).clone());
    
    // REMOVE: SELECT LIMIT 1 hack (line 37)
    // USE: auth_user.user_id directly
    
    let settings = db.get_user_settings(auth_user.user_id)
        .await
        .unwrap_or_default();  // Return defaults if not found
    
    // ... existing response mapping ...
}
```

**2.2 Update update_setting Handler** (line 93)
- Extract `AuthUser` instead of selecting first user
- Use `auth_user.user_id` for all operations
- Remove TODO comment (line 98)

**2.3 Initialize Defaults**
- When user first logs in, create default user_settings row
- Can be done in login handler or lazy-loaded on first GET

### Phase 3: Refactor users.rs (30 min)

**3.1 Update backup Handler** (line 392)
```rust
pub async fn backup(
    Extension(auth_user): Extension<AuthUser>,  // ADD THIS
    State(state): State<AppState>,
) -> Result<...> {
    let db = Database::new((*state.db_pool).clone());
    
    // REMOVE: SELECT LIMIT 1 hack
    // USE: auth_user.user_id directly
    
    let user_id = auth_user.user_id;
    
    // Query contacts by user_id (no wallet needed)
    let contacts = db.get_contacts_for_user(user_id).await?;
    
    // Query transactions by user_id (no wallet needed)
    let transactions = db.get_transactions_for_user(user_id).await?;
    
    // ... existing backup JSON generation ...
}
```

**3.2 Verify Other Handlers**
- Check all users.rs handlers for auth context
- Add `Extension<AuthUser>` to any handler needing user_id

### Phase 4: Fix create_wallet Handler (15 min)

**Related Issue**: create_wallet also uses LIMIT 1 hack (todo.md line 78)

```rust
pub async fn create_wallet(
    Extension(auth_user): Extension<AuthUser>,  // ADD THIS
    State(state): State<AppState>,
    Json(payload): Json<CreateWalletRequest>,
) -> Result<...> {
    let db = Database::new((*state.db_pool).clone());
    
    // REMOVE: SELECT LIMIT 1 hack for user_id
    // USE: auth_user.user_id directly as created_by
    
    let wallet_id = Uuid::new_v4();
    db.create_wallet(
        wallet_id,
        payload.name,
        payload.description,
        Some(auth_user.user_id),  // Fix: use authenticated user
    )
    .await?;
    
    // ... rest of wallet creation ...
}
```

### Phase 5: Verification (15 min)

**5.1 Confirm Wallet Operations Unchanged**
- wallets.rs: Only create_wallet modified (added AuthUser)
- contacts.rs: No changes
- transactions.rs: No changes
- permission_service.rs: No changes

**5.2 Test User-Scoped Operations**
```bash
cargo test --test settings_test
cargo test --test users_test
cargo test --test wallet_management_test  # regression check
```

**5.3 Verify Auth Context**
- Handlers extract AuthUser correctly
- User_id from AuthUser matches authenticated user
- No "SELECT LIMIT 1" queries remain
- Wallets created_by correctly attributed to user

---

## Key Changes Summary

### What Changes
| File | Change | Reason |
|------|--------|--------|
| migrations/XXX_create_user_settings_table.sql | NEW | Store user-scoped preferences |
| src/database/models/user_settings.rs | NEW | Define UserSettings struct |
| src/database/repository/user_settings.rs | NEW | CRUD methods for user settings |
| src/database/repository/mod.rs | MODIFIED | Add UserSettings trait methods |
| src/handlers/settings.rs | REFACTORED | Extract AuthUser, use user_settings repo |
| src/handlers/users.rs | REFACTORED | Extract AuthUser, remove LIMIT 1 hack |
| src/handlers/wallets.rs | REFACTORED | Fix create_wallet AuthUser extraction |

### What Doesn't Change
| Component | Why |
|-----------|-----|
| permission_service.rs | Still handles wallet-scoped permissions |
| wallet_context.rs | Still extracts wallet context for wallet operations |
| contacts.rs | Still uses permission matrix for access control |
| transactions.rs | Still uses permission matrix for access control |
| auth.rs | Still injects AuthUser (already working) |

---

## Benefits

1. ✅ **Eliminates SQL Hack**: No more `SELECT LIMIT 1` (fixes todo.md HIGH PRIORITY)
2. ✅ **Proper Auth Context**: Uses actual authenticated user (fixes 3 CODE TODOs)
3. ✅ **User-Level Isolation**: Settings truly per-user, not per-wallet
4. ✅ **Cleaner Architecture**: Separates wallet-scoped from user-scoped concerns
5. ✅ **Data Security**: Prevents cross-user data leaks from LIMIT 1 bug
6. ✅ **Zero Regression Risk**: Only adds new operations, doesn't change wallet system
7. ✅ **Foundation for Features**: Enables future user-level features (notifications, preferences, etc.)

---

## Architectural Decisions

### Why Two Separate Systems?

The permission system (wallet-scoped groups) is OPTIMAL for:
- Controlling who can see/edit which contacts
- Controlling who can create/close which transactions
- Multi-user collaboration within a wallet

But it's OVERKILL for:
- User theme preferences
- User backup/export
- User-level feature settings

By keeping them separate, we:
1. Don't force wallet context where it's not needed
2. Allow user operations to work offline/independently
3. Keep the permission system focused on its core use case

### User Settings as First-Class Data

Rather than storing settings in:
- Cache (lost on logout)
- Environment (not per-user)
- Cookies (limited size)
- Wallet tables (wrong scope)

We store in dedicated `user_settings` table because:
- Persistent across sessions
- Per-user isolation
- Database consistency
- Easy to query/update
- Scales with user count

---

## Testing Strategy

### Unit Tests
- UserSettings repository CRUD operations
- AuthUser extraction in handlers

### Integration Tests
- User settings persist across sessions
- Settings isolated per user
- Wallet operations unchanged
- Permission matrix still working
- LIMIT 1 hack eliminated

### Edge Cases
- User deletes account → settings deleted (CASCADE)
- Settings defaults applied correctly
- Auth context missing → 401 Unauthorized
- Wallet context optional for user routes
- Different users get their own settings (isolation)

---

## Timeline

| Phase | Duration | Deliverable | Fixes |
|-------|----------|-------------|-------|
| 1: Infrastructure | 1 hour | user_settings table + repo | - |
| 2: settings.rs | 30 min | Fix get_settings + update_setting | TODO: line 36, 98 |
| 3: users.rs | 30 min | Fix backup + other handlers | TODO: line 392 |
| 4: wallets.rs | 15 min | Fix create_wallet | TODO: line 78 |
| 5: Verification | 15 min | Tests passing + no regressions | - |
| **Total** | **~2.5 hours** | **Phase 5 complete** | **4 CODE TODOs fixed** |

---

## References

- **Permission System Deep Dive**: vault/permission-system-deep-dive.md
- **Auth System**: vault/auth.md
- **TODOs List**: vault/todos.md (HIGH PRIORITY section, lines 77-82)
- **Current Code**: src/handlers/{settings,users,wallets}.rs
- **Related**: Phase 4 (SQL refactoring) completed

---

## Next Steps

1. ✅ Approve architecture (this document)
2. ⬜ Create migration + models
3. ⬜ Implement repository
4. ⬜ Refactor handlers (settings.rs, users.rs, wallets.rs)
5. ⬜ Test + verify
