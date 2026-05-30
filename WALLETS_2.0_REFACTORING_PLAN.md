# wallets.rs 2.0 Refactoring Plan

## Current Issues

### 1. String-Based Role Comparisons ❌
```rust
// CURRENT (bad)
if wallet_role == "owner" || wallet_role == "admin" { }
if let Some(role) = db.get_wallet_user_role(...) {
    let role_str = role.as_str();
    if role_str == "owner" { }
}

// SHOULD BE (good)
if matches!(wallet_role, WalletRole::Owner | WalletRole::Admin) { }
match wallet_role {
    WalletRole::Owner | WalletRole::Admin => { },
    WalletRole::Member => { },
}
```

### 2. Role Hierarchy as String Array ❌
```rust
// CURRENT (bad)
let role_hierarchy = ["member", "admin", "owner"];
let user_level = role_hierarchy.iter().position(|&r| r == role.as_str())

// SHOULD BE (good)
enum RoleLevel { Member, Admin, Owner }
impl RoleLevel {
    fn from_wallet_role(role: WalletRole) -> Self { ... }
    fn can_perform(&self, required: RoleLevel) -> bool { self >= required }
}
```

### 3. Repeated Permission Checks ❌
- Lines 54-108: `require_wallet_role_at_least()` - role checking logic
- Lines 109-205: `check_permission_matrix()` - permission matrix checking
- Lines 1310-1319: `require_wallet_admin()` - admin check
- Lines 1320-1350: `get_wallet_role()` - role fetching
- All should use **PermissionModel API only**

### 4. Mixed Responsibility Functions
- Manual role string parsing throughout
- Manual permission matrix checks
- Direct database queries instead of using repository API

## Lines of Code Issues

Total: **2423 lines**
- Estimated ~300+ lines of string-based role/permission logic
- ~200+ lines of repeated permission checking
- ~500+ lines could be using PermissionModel API instead

## Refactoring Strategy

### Phase 1: Extract Role/Permission Logic to Helpers
- Create `WalletRoleExt` trait for methods on WalletRole
- Create `RoleHierarchy` struct for role comparisons
- Move all string comparisons to enum-based matching

### Phase 2: Use PermissionModel API
- Replace `check_permission_matrix()` with `PermissionModel::check_permissions()`
- Replace manual role checks with `PermissionModel::resolve_actions()`
- Remove duplicate permission logic

### Phase 3: Refactor Key Endpoints
Key functions to refactor first:
1. `add_user_to_wallet()` - role string comparison (line 539)
2. `update_wallet_user()` - role string comparison (line 873)
3. `get_my_permissions()` - role string comparison (line 1078)
4. `create_user_group()` - permission checks (line 1444)
5. `get_my_wallet_settings()` - role comparison (line 1159)

### Phase 4: Remove Helper Functions
After using PermissionModel API:
- `require_wallet_role_at_least()` - REMOVE (use PermissionModel)
- `check_permission_matrix()` - REMOVE (use PermissionModel)
- `require_wallet_admin()` - REMOVE (replace with pattern match)
- `get_wallet_role()` - KEEP (needed for auth context)

## Key Principles for wallets.rs 2.0

✅ **Pattern Matching Instead of Strings**
```rust
match wallet_role {
    WalletRole::Owner => { /* all permissions */ },
    WalletRole::Admin => { /* admin permissions */ },
    WalletRole::Member => { /* limited permissions */ },
}
```

✅ **Use PermissionModel for All Permission Checks**
```rust
let allowed = perm_model.check_permissions(&ctx, vec![
    (Action::WalletUpdate, Resource::Wallet(wallet_id)),
]).await?;
```

✅ **Type-Safe Role Comparisons**
```rust
// NOT: if role.as_str() == "owner"
// BUT: if matches!(role, WalletRole::Owner)
```

✅ **Single Source of Truth**
- Role definitions: `WalletRole` enum
- Permission logic: `PermissionModel`
- Role hierarchy: Implement as trait on WalletRole

## Expected Results

| Metric | Current | Target |
|--------|---------|--------|
| String role comparisons | 6+ | 0 |
| Manual permission checks | Multiple | 1 (PermissionModel) |
| Helper functions for perms | 4+ | 0 |
| Lines of code | 2423 | ~1800-2000 |
| Type safety | Low | High |
| Maintainability | Low | High |

## Implementation Order

1. Keep sync.rs as golden standard (no strings in logic)
2. Apply same principles to wallets.rs
3. Create trait methods for WalletRole comparisons
4. Systematically replace each endpoint's role checks
5. Remove obsolete helper functions

## Critical Functions List

```
PUBLIC ENDPOINTS:
- create_my_wallet() - line 206
- create_wallet() - line 287  
- list_wallets() - line 343
- get_wallet() - line 375
- update_wallet() - line 416
- delete_wallet() - line 496
- add_user_to_wallet() - line 539 ⚠️ STRING CHECKS
- search_wallet_users() - line 644
- create_wallet_invite() - line 699
- join_wallet_by_code() - line 740
- list_wallet_users() - line 830
- update_wallet_user() - line 873 ⚠️ STRING CHECKS
- remove_user_from_wallet() - line 942
- list_user_wallets() - line 1036
- get_my_permissions() - line 1078 ⚠️ STRING CHECKS
- get_my_wallet_settings() - line 1159 ⚠️ STRING CHECKS
- put_my_wallet_settings() - line 1197

USER GROUPS:
- list_user_groups() - line 1407
- create_user_group() - line 1444 ⚠️ PERMISSION CHECKS
- update_user_group() - line 1503
- delete_user_group() - line 1559
- list_user_group_members() - line 1610
- add_user_group_member() - line 1651
- remove_user_group_member() - line 1709
- set_user_group_members_bulk() - line 1769

CONTACT GROUPS & MATRIX:
- list_contact_groups() - line 1849
- create_contact_group() - line 1886
- update_contact_group() - line 1944
- delete_contact_group() - line 2002
- list_contact_group_members() - line 2060
- add_contact_group_member() - line 2098
- remove_contact_group_member() - line 2162
- set_contact_group_members_bulk() - line 2222
- get_permission_matrix() - line 2283
- set_permission_matrix() - line 2353 ⚠️ PERMISSION MATRIX

⚠️ = Priority for refactoring
```

## Notes

- Preserve all error responses and codes
- Keep backward compatibility with API contracts
- Tests should validate permission behavior, not strings
- Consider deprecation timeline for old patterns
