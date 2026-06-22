# Wallet Permissions Redesign - V2 (Vector-Based Model)

**Status:** ✅ Implemented (Phases 1-10 Complete)  
**Date:** 2026-06-22  
**Model:** Three-tier permission system with global + vector + hardcoded owner  
**Last Updated:** 2026-06-22 (Implementation Complete)

---

## Overview

Three distinct permission tiers for wallet operations:

### Tier 1: Global Wallet Management (Stateless)
Actions that apply globally to the entire wallet. No scoping needed.
- `wallet:info_read` - Read wallet name/description
- `wallet:info_update` - Modify wallet name/description  
- `wallet:member_list` - View all members in wallet

**Storage:** `wallet_permission_matrix(user_group_id, action, is_deny)`

**Access Pattern:** Does user's group have this action?

---

### Tier 2: Vector-Based Members Management (Scoped)
Actions scoped between two groups (source → target). Like current `group_permission_matrix` but for member groups instead of contact groups.

#### Actions:
- `wallet:member_add` - Source group can add members to target group
- `wallet:member_remove` - Source group can remove members from target group
- `wallet:member_list` - Source group can view members of target group
- `wallet:set_permission_matrix` - Source group can modify permissions for target group

**Storage:** `wallet_member_permission_matrix(source_group_id, target_group_id, action, is_deny)`

**Access Pattern:** Can user's groups (as source) perform action on specific target group?

**Examples:**
- "admin1" group can add members to "Team1" group
- "admin1" can remove members from "Team1" (but NOT from "Team2")
- "Team1" members cannot add/remove members (no vector permissions)
- "owner" can do anything (hardcoded bypass)

---

### Tier 3: Owner-Only Operations (Hardcoded)
Restricted to wallet owners via `wallet_owners` table. No matrix lookup.

- `wallet:delete` - Soft delete wallet
- `wallet:owner_transfer` - Transfer ownership to another user

**Access Pattern:** Is user in wallet_owners table?

**No exceptions:** Admins, groups, etc. cannot bypass this.

---

## Database Schema

### Table 1: wallet_permission_matrix (Global)
```sql
CREATE TABLE wallet_permission_matrix (
    user_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    action VARCHAR(64) NOT NULL,
    is_deny BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_group_id, action)
);
```

**Actions:** `wallet:info_read`, `wallet:info_update`, `wallet:member_list`

---

### Table 2: wallet_member_permission_matrix (Vector)
```sql
CREATE TABLE wallet_member_permission_matrix (
    source_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    target_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    action VARCHAR(64) NOT NULL,
    is_deny BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source_group_id, target_group_id, action)
);
```

**Actions:** `wallet:member_add`, `wallet:member_remove`, `wallet:member_list`, `wallet:set_permission_matrix`

**Constraint:** source_group_id ≠ target_group_id (can't give group permissions on itself)

---

### Table 3: wallet_owners (Hardcoded)
Already exists. Used for owner bypass check.

```sql
CREATE TABLE wallet_owners (
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    PRIMARY KEY (wallet_id, user_id)
);
```

---

## Permission Resolution Algorithm

### Query 1: Check if user is wallet owner
```rust
SELECT EXISTS(
  SELECT 1 FROM wallet_owners 
  WHERE wallet_id = $wallet_id AND user_id = $user_id
)
```
**Result:** If TRUE → grant ALL permissions (owner bypass)

---

### Query 2: Check global permission (Tier 1)
```rust
// For actions: info_read, info_update, member_list

SELECT COALESCE(
  (
    SELECT is_deny 
    FROM wallet_permission_matrix 
    WHERE user_group_id IN (user's groups) 
    AND action = $action 
    ORDER BY is_deny DESC  -- Deny wins
    LIMIT 1
  ), 
  false  -- Default: allow if not found
) as is_deny
```

**Decision Logic:**
- If any group has `is_deny=true` → DENY
- If any group has `is_deny=false` → ALLOW
- If no group has permission → ALLOW (default)

---

### Query 3: Check vector permission (Tier 2)
```rust
// For actions: member_add, member_remove, member_list, set_permission_matrix
// Action scoped to specific target_group_id

SELECT COALESCE(
  (
    SELECT is_deny 
    FROM wallet_member_permission_matrix 
    WHERE source_group_id IN (user's groups) 
    AND target_group_id = $target_group_id
    AND action = $action 
    ORDER BY is_deny DESC  -- Deny wins
    LIMIT 1
  ), 
  false  -- Default: deny if not found
) as is_deny
```

**Decision Logic:**
- If any source group (user is member of) has explicit permission → use it
- Deny-wins rule applies
- Default: DENY (no implicit access to specific groups)

---

## API Endpoints

### Global Permissions (Tier 1)

**GET** `/api/wallets/:wallet_id/wallet-permissions`
```json
[
  {
    "user_group_id": "uuid",
    "action": "wallet:info_read",
    "is_deny": false
  }
]
```

**PUT** `/api/wallets/:wallet_id/wallet-permissions`
```json
{
  "entries": [
    {
      "user_group_id": "uuid",
      "action": "wallet:info_read",
      "is_deny": false
    }
  ]
}
```

---

### Vector Permissions (Tier 2)

**GET** `/api/wallets/:wallet_id/member-permissions`
```json
[
  {
    "source_group_id": "admin1-uuid",
    "target_group_id": "team1-uuid",
    "action": "wallet:member_add",
    "is_deny": false
  }
]
```

**PUT** `/api/wallets/:wallet_id/member-permissions`
```json
{
  "entries": [
    {
      "source_group_id": "admin1-uuid",
      "target_group_id": "team1-uuid",
      "action": "wallet:member_add",
      "is_deny": false
    }
  ]
}
```

---

## Handler Enforcement Points

### 1. Reading Wallet Info
```rust
// GET /api/wallets/:wallet_id
can_perform(user, Action::WalletInfoRead, Resource::Wallet(wallet_id))
// Tier 1: Global permission check
```

### 2. Updating Wallet Info
```rust
// PUT /api/wallets/:wallet_id
can_perform(user, Action::WalletInfoUpdate, Resource::Wallet(wallet_id))
// Tier 1: Global permission check
```

### 3. Listing Wallet Members
```rust
// GET /api/wallets/:wallet_id/users
can_perform(user, Action::WalletMemberList, Resource::Wallet(wallet_id))
// Tier 1: Global permission check
```

### 4. Adding User to Wallet
```rust
// POST /api/wallets/:wallet_id/users
// First: can user add members globally? (Tier 1)
can_perform(user, Action::WalletMemberAdd, Resource::Wallet(wallet_id))
// Then: can user add members to this specific group? (Tier 2)
can_perform(user, Action::WalletMemberAdd, Resource::WalletGroup(target_group_id))
// Both must be true
```

### 5. Removing User from Wallet
```rust
// DELETE /api/wallets/:wallet_id/users/:user_id
// Tier 1 + Tier 2 same pattern
can_perform(user, Action::WalletMemberRemove, Resource::Wallet(wallet_id))
can_perform(user, Action::WalletMemberRemove, Resource::WalletGroup(target_group_id))
```

### 6. Deleting Wallet
```rust
// DELETE /api/wallets/:wallet_id
// Owner only - no matrix check
if !is_wallet_owner(user_id, wallet_id) {
  return 403 FORBIDDEN
}
```

### 7. Transferring Ownership
```rust
// POST /api/wallets/:wallet_id/owner/transfer
// Owner only - no matrix check
if !is_wallet_owner(user_id, wallet_id) {
  return 403 FORBIDDEN
}
```

### 8. Setting Permission Matrix
```rust
// PUT /api/wallets/:wallet_id/wallet-permissions
// PUT /api/wallets/:wallet_id/member-permissions
// Tier 1: User can modify wallet global permissions
can_perform(user, Action::WalletInfoUpdate, Resource::Wallet(wallet_id))
// Tier 2: User can modify permissions for specific target groups
can_perform(user, Action::WalletSetPermissionMatrix, Resource::WalletGroup(target_group_id))
// For each group being modified, both must pass
```

---

## Breakdown by Operation

| Operation | Required Permission | Check Type | Scope |
|-----------|-------------------|-----------|-------|
| Read wallet name | wallet:info_read | Tier 1 | Global |
| Update wallet name | wallet:info_update | Tier 1 | Global |
| List all members | wallet:member_list | Tier 1 | Global |
| Add member to group X | wallet:member_add + member_add to X | Tier 1 + Tier 2 | Group X |
| Remove member from group X | wallet:member_remove + member_remove from X | Tier 1 + Tier 2 | Group X |
| View members of group X | wallet:member_list + member_list for X | Tier 1 + Tier 2 | Group X |
| Edit wallet permissions | wallet:info_update | Tier 1 | Global |
| Edit group X permissions | wallet:set_permission_matrix to X | Tier 2 | Group X |
| Delete wallet | (owner only) | Owner | N/A |
| Transfer ownership | (owner only) | Owner | N/A |

---

## UI Implementation Strategy

### Tab 1: "Wallet Settings"
- Global permissions (Tier 1)
- Shows groups and their wallet-level actions
- Grant/revoke info_read, info_update, member_list
- Only for admin users

### Tab 2: "Group Managers"
- Vector permissions (Tier 2)
- Matrix of source groups × target groups × actions
- For each (source, target) pair, show which actions are allowed
- Click to edit: which source groups can add/remove members from target group
- Only accessible to groups that have wallet:set_permission_matrix on that group

### Tab 3: "Member Groups"
(Already exists) - Shows member groups and their members

---

## Migration Strategy

### Phase 1: Database
- Add `wallet_member_permission_matrix` table
- Backfill with safe defaults (no vector permissions initially)
- Keep `wallet_permission_matrix` for global permissions

### Phase 2: Domain
- Add new Action variants for vector permissions
- Update resolver to handle two different matrix types
- Update Resource enum to include WalletGroup variant

### Phase 3: Server
- Update permission resolver for Tier 2 checks
- Update handlers to enforce both Tier 1 and Tier 2
- Add new API endpoints for vector permissions
- Register routes in main.rs

### Phase 4: Client
- Add Rust API functions for vector permissions
- Add Dart wrappers in api.dart
- CommandRunner support for vector permission tests

### Phase 5: UI
- Add vector permissions tab to manage_wallet_screen
- Show source → target grid
- Edit dialog for each vector pair
- Graceful fallback if endpoint not available

### Phase 6: Tests
- Integration tests for Tier 1 (global) enforcement
- Integration tests for Tier 2 (vector) enforcement
- Test deny-wins rule
- Test owner bypass
- Test cross-group restrictions

---

## Key Invariants

✅ **Owner always has all permissions** - Hardcoded via wallet_owners table

✅ **Vector permissions default to DENY** - A group has no implicit access to any target group

✅ **Global permissions default to ALLOW** - A group can read wallet info by default

✅ **Deny wins** - If in both allow and deny groups, denied

✅ **No self-permissions** - Source group cannot have permissions on itself (database constraint)

✅ **Only owners can delete or transfer** - Hardcoded, no exceptions

✅ **Groups are immutable** - Cannot rename/delete system groups (all_users, __owners__)

---

## Examples

### Scenario 1: Admin Group Managing Team Group
```
Initial state:
- Group "admin1" (members: alice, bob)
- Group "team1" (members: charlie, david)
- No vector permissions set

Actions:
1. Owner grants wallet:member_add to admin1 (Tier 1)
2. Owner grants vector permission: admin1 can add/remove members to/from team1
3. Alice (in admin1) tries to add eve to team1:
   - Check Tier 1: Does alice (via admin1) have wallet:member_add? YES
   - Check Tier 2: Does admin1 have member_add permission on team1? YES
   - Result: ALLOWED

Result: alice can add members to team1, but not to other groups
```

### Scenario 2: Restricting Team Leads
```
Setup:
- Group "team1" (members: charlie, david)
- Grant team1 global wallet:member_list (can view all wallet members)
- Grant team1 vector wallet:member_list on team1 only (can view team members)

Result:
- team1 can list all wallet members (Tier 1)
- team1 cannot add/remove members (no vector permissions)
- team1 cannot modify any other groups
```

### Scenario 3: Owner-Only Deletion
```
Setup:
- alice is owner
- bob is admin with wallet:info_update

Actions:
1. bob tries to delete wallet
   - Check owner: is bob in wallet_owners? NO
   - Result: FORBIDDEN (403)
2. alice tries to delete wallet
   - Check owner: is alice in wallet_owners? YES
   - Result: ALLOWED

Result: Only owner can delete, regardless of admin status
```

---

## Security Properties

| Threat | Mitigation |
|--------|-----------|
| Privilege escalation via groups | Groups are immutable; members controlled separately |
| User gaining permissions via group cycles | Vector permissions are (source, target, action); no transitive grants |
| Circumventing owner-only operations | Hardcoded check via wallet_owners; no matrix lookup |
| Implicit trust in roles | All permissions explicit via matrix; no role-based fallback |
| Denial-of-service via permission explosions | Vector matrix is bounded: O(groups²); global matrix is O(groups) |
| Deny being overridden | Deny-wins rule: sorted by is_deny DESC ensures deny is checked first |

---

## Implementation Status: ✅ Complete

### Phase 1: Database Layer ✅
- ✅ Migration 037: `wallet_member_permission_matrix` table
- ✅ Schema with source_group_id, target_group_id, action, is_deny
- ✅ Constraint: source ≠ target
- ✅ Indexes for query performance

### Phase 2: Domain Layer ✅
- ✅ Action::WalletSetPermissionMatrix variant
- ✅ Resource::WalletGroup(Uuid) variant
- ✅ Updated Action::as_str(), from_str(), all(), implies()
- ✅ Updated Resource::id() and Display trait

### Phase 3: Permission Resolution ✅
- ✅ resolve_wallet_member_permissions() function
- ✅ Vector permission matrix lookup
- ✅ Deny-wins semantics (allowed - denied)
- ✅ Integration with resolve_actions()

### Phase 4: Handler Enforcement ✅
- ✅ add_user_group_member: checks Resource::WalletGroup
- ✅ remove_user_group_member: checks Resource::WalletGroup
- ✅ get_member_permissions handler (GET endpoint)
- ✅ set_member_permissions handler (PUT endpoint)
- ✅ MemberPermissionEntry + SetMemberPermissionsRequest types

### Phase 5: API Endpoints ✅
- ✅ GET /api/wallets/:wallet_id/member-permissions
- ✅ PUT /api/wallets/:wallet_id/member-permissions
- ✅ Routes registered in main.rs
- ✅ Handlers exported in handlers/mod.rs

### Phase 6: Rust Client API ✅
- ✅ get_member_permissions_api() function
- ✅ set_member_permissions_api() function
- ✅ Public exports in api/mod.rs
- ✅ Graceful error handling

### Phase 7: Client Library Functions ✅
- ✅ get_member_permissions() - public Dart interface
- ✅ set_member_permissions() - public Dart interface
- ✅ Cache invalidation on permission changes
- ✅ Vault resync triggers

### Phase 8: Flutter UI ✅
- ✅ 6th tab in manage_wallet_screen.dart: "Member Perms"
- ✅ _MemberPermissionsTab with source→target grid layout
- ✅ _MemberPermissionsDialog for editing permissions
- ✅ Visual UI: source group → target group matrix
- ✅ Chip-based allow/deny visualization
- ✅ API.getMemberPermissions() + setMemberPermissions() wrappers

### Phase 9: Integration Tests ✅
- ✅ member_permission_enforcement.rs test file
- ✅ CommandRunner support: `member-permission grant|revoke source target action`
- ✅ Test scenarios: grant, revoke, deny-wins, owner bypass
- ✅ Setup helpers for multi-group wallet

### Phase 10: Documentation & Vault ✅
- ✅ This file updated with implementation status
- ✅ Example scenarios documented (Scenario 1-3)
- ✅ Security properties table completed
- ✅ All phases marked complete

---

## Files Changed

**Backend (Rust):**
- `crates/server/migrations/037_wallet_member_permission_matrix.sql` - Database schema
- `crates/core/domain/src/permission.rs` - Action & Resource enums
- `crates/server/src/permissions/resolver.rs` - Permission resolution logic
- `crates/server/src/database/repository/wallets.rs` - Database queries
- `crates/server/src/handlers/wallets.rs` - API handlers
- `crates/server/src/main.rs` - Route registration
- `crates/server/src/handlers/mod.rs` - Handler exports

**Client (Rust):**
- `crates/client/src/api/wallets.rs` - API functions
- `crates/client/src/api/mod.rs` - API exports
- `crates/client/src/lib.rs` - Public client functions
- `crates/client/tests/common/command_runner.rs` - Test commands
- `crates/client/tests/member_permission_enforcement.rs` - Integration tests

**Mobile (Dart/Flutter):**
- `mobile/lib/screens/manage_wallet_screen.dart` - UI tabs & state
- `mobile/lib/api.dart` - API wrappers

---

## How It Works: Quick Reference

1. **User tries to add a member to a group:**
   - Handler checks `Resource::WalletGroup(target_group_id)`
   - Resolver queries `wallet_member_permission_matrix` for source groups
   - Applies deny-wins rule
   - Returns set of allowed actions
   - Handler checks if `wallet:member_add` is in allowed set

2. **Owner always bypasses:**
   - Hardcoded check via `wallet_owners` table
   - Happens BEFORE permission resolver
   - No matrix lookup needed

3. **No implicit permissions:**
   - Default: group has no permissions on any target group
   - Must explicitly grant via matrix
   - Deny explicitly revokes

---

## Deployment Notes

- ✅ Backward compatible: Old wallets keep working (default deny)
- ✅ No data migration needed (table is new, orthogonal to existing schema)
- ✅ Gradual adoption: UI and tests present, can enable/disable via feature flags if needed
- ✅ All 10 phases implemented and tested
