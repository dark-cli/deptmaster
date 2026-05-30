# wallets.rs 2.0 Refactoring Plan

**Current state:** wallets.rs (2,423 lines) has mixed concerns, string-based role handling, and duplicate permission logic.

**Goal:** Rebuild wallets.rs 2.0 following sync.rs 2.0 golden standard: type-safe roles, zero string comparisons in logic, clean separation of concerns.

---

## Core Architecture Issues

### 1. String-Based Role Handling (❌ ANTI-PATTERN)
Current approach in wallets.rs:
```rust
// CURRENT (bad) - string hierarchy array
let role_hierarchy = ["member", "admin", "owner"];
let user_level = role_hierarchy.iter().position(|&r| r == role.as_str()).unwrap_or(0);

// CURRENT (bad) - string comparison
if wallet_role == "owner" || wallet_role == "admin" { }

// CURRENT (bad) - string literals passed to database
db.add_wallet_user(wallet_id, user_id, "owner".to_string())
```

**Why it's wrong:**
- No type safety at compile time
- String matches can fail silently ("owwner" is a valid string but wrong role)
- Hierarchy logic repeated across functions
- Inefficient string comparisons vs enum pattern matching

### 2. Duplicate Helper Functions (❌ WASTE)
wallets.rs has 4 helper functions that recreate permission logic:
- `require_wallet_role_at_least()` (54-106 lines) - manual role comparison with hierarchy
- `check_permission_matrix()` (109-138 lines) - wraps PermissionModel but hardcodes Owner/Admin bypass
- `validate_permission_dependencies()` (19-52 lines) - validates action string dependencies
- `get_wallet_role()` - fetches role from database

**Problem:** These duplicate work that should live in:
- PermissionModel (already handles Owner/Admin bypass)
- WalletRole enum (role comparison, hierarchy)
- Database repository layer (role fetching)

### 3. Mixed Responsibilities in Endpoints
Example: `update_wallet_user()` (873-939 lines)
```rust
// This endpoint does:
// 1. UUID parsing (validation)
// 2. Permission checking (business logic)
// 3. Role validation (string array check)
// 4. Event emission (side effect)
// 5. WebSocket broadcast (side effect)
```

**Should be:**
- Validation at boundary (request type deserialization)
- Permission check via PermissionModel API
- Event emission to repository
- Broadcast as final step

### 4. Role as String in Request/Response Types
```rust
#[derive(Deserialize)]
pub struct UpdateWalletUserRequest {
    pub role: String,  // ❌ Should be WalletRole enum
}

#[derive(Serialize)]
pub struct WalletUser {
    pub role: String,  // ❌ Should be WalletRole enum for type safety
}
```

---

## Priority Refactoring Areas

### High Priority (String comparisons)
| Function | Issue | Location |
|----------|-------|----------|
| `require_wallet_role_at_least()` | REMOVE - use PermissionModel or WalletRole.can_perform() | 54-106 |
| `add_user_to_wallet()` | String literal "member" (line 585) | 539-640 |
| `update_wallet_user()` | String array validation (line 897) | 873-939 |
| `get_my_permissions()` | String comparison for Owner/Admin (line 1087) | 1078-1150 |
| `join_wallet_by_code()` | String literal "member" (line 793) | 740-815 |
| `check_permission_matrix()` | REMOVE - PermissionModel handles this | 109-138 |

### Medium Priority (Type safety)
- Change `UpdateWalletUserRequest.role: String` → `WalletRole`
- Change `WalletUser.role: String` → `WalletRole`
- Change all database calls passing `"owner".to_string()` → `WalletRole::Owner.as_str()`

### Low Priority (Code cleanup)
- Remove `validate_permission_dependencies()` - PermissionModel::validate_dependencies() exists
- Simplify WebSocket messages (no behavior change)

---

## Implementation Strategy

### Phase 1: Foundation (Already Done in sync.rs)
✅ WalletContext.user_role: `String` → `WalletRole` enum
✅ WalletRole helper methods: `is_admin_or_higher()`, `can_perform()`, etc.
✅ Removed `require_wallet_role()` from middleware

**Result:** Type-safe role handling at boundary, pattern matching available in handlers.

### Phase 2: Update Request/Response Types
**Files to modify:** wallets.rs request/response structs

**Changes:**
```rust
// Before
#[derive(Deserialize)]
pub struct UpdateWalletUserRequest {
    pub role: String,
}

// After
#[derive(Deserialize)]
pub struct UpdateWalletUserRequest {
    #[serde(deserialize_with = "validate_wallet_role")]
    pub role: WalletRole,
}

fn validate_wallet_role<'de, D>(deserializer: D) -> Result<WalletRole, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    WalletRole::from_str(&s)
        .ok_or_else(|| serde::de::Error::custom("Invalid wallet role"))
}

// Response types
#[derive(Serialize)]
pub struct WalletUser {
    pub role: String, // Keep as string for API compatibility, serialize from enum
}
```

### Phase 3: Refactor Endpoints (6 Priority Functions)
For each endpoint:

1. **Remove permission helper call**
   ```rust
   // Before
   let _role = require_wallet_role_at_least(&state, wallet_uuid, &auth_user, "admin").await?;
   
   // After
   if !wallet_context.user_role.can_perform(WalletRole::Admin) {
       return Err(insufficient_permission_response());
   }
   ```

2. **Use WalletRole enum pattern matching**
   ```rust
   // Before
   let role = "member";
   
   // After
   let role = WalletRole::Member;
   ```

3. **Simplify role validation**
   ```rust
   // Before
   if !["owner", "admin", "member"].contains(&payload.role.as_str()) {
       return Err(...);
   }
   
   // After
   // Validation happens in request deserializer, no check needed
   ```

### Phase 4: Clean Up Helper Functions
**Remove completely:**
- `require_wallet_role_at_least()` - REPLACE with `wallet_context.user_role.can_perform()`
- `check_permission_matrix()` - USE PermissionModel API directly
- `validate_permission_dependencies()` - PermissionModel already has this
- `get_permission_context()` helper - Move logic into endpoints if needed

**Keep:**
- Database operations (get_wallet_user_role) - needed for initial context

---

## Key Principles for wallets.rs 2.0

### ✅ Type-Safe Role Operations
```rust
// Instead of: if wallet_role == "owner"
match wallet_context.user_role {
    WalletRole::Owner => { /* owner logic */ }
    WalletRole::Admin => { /* admin logic */ }
    WalletRole::Member => { /* member logic */ }
}

// Or simpler:
if wallet_context.user_role.is_admin_or_higher() {
    // owner or admin
}
```

### ✅ Validate at Boundary, Use Types Everywhere Else
```rust
// Request enters as JSON -> deserializer validates -> returns WalletRole enum
// Handler receives ONLY valid WalletRole
// No string parsing inside handler logic
```

### ✅ Keep Permission Logic Centralized
- Database layer: Store roles as strings (compatibility), expose as enums
- Handler layer: Use WalletRole enum only, never touch role strings
- Serialize for API responses: `role.as_str()` at response time only

### ✅ No String Literals in Logic
```rust
// ❌ NEVER: "member", "owner", "admin" as string literals in code
// ✅ ALWAYS: WalletRole::Member, WalletRole::Owner, WalletRole::Admin

// ❌ NEVER: role_hierarchy = ["member", "admin", "owner"]
// ✅ ALWAYS: role.can_perform(required_role) method
```

---

## Expected Outcomes

| Metric | Current | Target | Impact |
|--------|---------|--------|--------|
| Lines of code | 2,423 | ~1,800 | 26% reduction via removed helpers |
| String role comparisons | 6+ | 0 | 100% type-safe |
| Helper functions for roles | 4 | 0 | Cleaner, no duplication |
| Endpoints with string validation | 6 | 0 | Validation at boundary only |
| Type safety | Low | High | Compile-time guarantees |
| Maintainability | Low | High | Pattern matching is self-documenting |

---

## Priority Endpoints to Refactor (In Order)

1. **`get_my_permissions()` (1078-1150)**
   - Issue: String comparison `if wallet_context.user_role == "owner"`
   - Action: Replace with `wallet_context.user_role.is_admin_or_higher()`
   - Impact: 3 lines → 1 line

2. **`update_wallet_user()` (873-939)**
   - Issue: String array validation on line 897
   - Action: Move validation to request deserializer
   - Impact: 6 lines → 0 lines (validation at boundary)

3. **`add_user_to_wallet()` (539-640)**
   - Issue: String literal `"member"` on line 585
   - Action: Use `WalletRole::Member.as_str()`
   - Impact: 1 line, but better type safety

4. **`join_wallet_by_code()` (740-815)**
   - Issue: String literal `"member"` on line 793
   - Action: Use `WalletRole::Member.as_str()`
   - Impact: 1 line, consistency

5. **`create_my_wallet()` / `create_wallet()` (206-340)**
   - Issue: String literal `"owner"` on lines 226, 307
   - Action: Use `WalletRole::Owner.as_str()`
   - Impact: Type-safe initialization

6. **`remove_user_from_wallet()` (942-1033)**
   - Issue: String comparison on line 978: `role.as_deref() == Some("owner")`
   - Action: Change to pattern matching on Option<WalletRole>
   - Impact: Better type safety, clearer intent

---

## Files to Modify

### Create (New)
- None - use existing infrastructure

### Modify
- `src/handlers/wallets.rs` - Main refactoring target
- `src/handlers/wallets/mod.rs` - Create if needed for organization
- Request/response types in wallets.rs

### No Changes Needed
- `src/permissions/context.rs` - Already has WalletRole with helper methods
- `src/permissions/model.rs` - Already handles permission logic
- `src/middleware/wallet_context.rs` - Already uses WalletRole enum
- `src/database/repository/` - Already abstracted, no string leakage

---

## Testing Strategy

After refactoring, verify:
1. ✅ All endpoints return same API responses (string roles in JSON)
2. ✅ Permission enforcement unchanged (Owner > Admin > Member)
3. ✅ Role validation at request boundary
4. ✅ No compile-time type errors
5. ✅ All existing tests pass without modification

```bash
# Run tests
cargo test --lib
cargo test --test integration_tests

# Specific wallet tests
cargo test wallet
```

---

## Estimated Effort

| Phase | Task | Time | Difficulty |
|-------|------|------|-----------|
| 1 | Request/response types | 1-2h | Easy |
| 2 | Refactor 6 priority endpoints | 3-4h | Medium |
| 3 | Remove helper functions | 30min | Easy |
| 4 | Testing & verification | 1h | Easy |
| **Total** | **Complete wallets.rs 2.0** | **5-7h** | **Medium** |

---

## Success Criteria

✅ All wallets.rs endpoints compile without errors
✅ No string comparisons in permission logic (`==`, `!=`, pattern match on &str)
✅ All string literals replaced with WalletRole enum
✅ Request validation happens in deserializer only
✅ No calls to `require_wallet_role_at_least()` or `check_permission_matrix()`
✅ All existing tests pass
✅ API responses unchanged (backward compatible)
✅ Code reduced from 2,423 to ~1,800 lines

---

## Next Step

Start Phase 2: Update UpdateWalletUserRequest with custom deserializer validation for WalletRole enum.

