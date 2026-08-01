# Permission System Implementation Plan

**Status:** Planning Phase  
**Date:** 2026-07-31  
**Scope:** Code implementation for four-layer permission system

---

## Key Architecture Decisions

### 1. Event-Sourcing: All Layers (Not Just Layer 3)

**Current State:**
- Layer 3 (Contact/Transaction): Event-based via `insert_permission_event_and_apply()`
- Layer 1 (Wallet-wide): Direct DB updates only

**Proposed:**
- ALL layers (1, 2, 2.5, 3): Event-based storage
- Add EventType variants: `WalletPermissionsSet`, `GroupPermissionsSet`, `ContactGroupPermissionsSet`

**Why:**
- Auditability: Full audit trail of permission changes
- Undo support: Consistent with existing undo infrastructure
- Replay: Recovery from crashes, migration verification
- Consistency: Same pattern across all layers

---

### 2. Full Vector / Matrix Replacement (Not Deltas)

**Current Pattern (Already Used in Layer 3):**
```json
PUT /api/wallets/:wallet_id/permission-matrix
{
  "entries": [
    {
      "user_group_id": "uuid",
      "contact_group_id": "uuid",
      "allowed_actions": ["contact:read", "contact:create"],
      "denied_actions": ["contact:delete"]
    }
  ]
}
```

**Apply This Pattern to ALL Layers:**
- Layer 1: Client sends COMPLETE desired state for a member_group
- Layer 2: Client sends COMPLETE desired state for target member_group
- Layer 2.5: Client sends COMPLETE desired state for target contact_group
- Layer 3: Already doing this

**Why:**
- Simplicity: No merge logic, no "what changed" uncertainty
- Reliability: Full picture prevents accidental deletions
- Testing: Easier to verify end state

---

### 3. Database Schema (New Tables)

**Layer 1: Wallet-Level Permissions**
```sql
wallet_permissions (
  id, wallet_id, member_group_id, action, is_deny, created_at, updated_at
)
```

**Layer 2: Member-Group-to-Member-Group**
```sql
member_group_permissions (
  id, wallet_id, source_member_group_id, target_member_group_id, action, is_deny, created_at, updated_at
)
```

**Layer 2.5: Member-Group-to-Contact-Group**
```sql
contact_group_permissions (
  id, wallet_id, source_member_group_id, target_contact_group_id, action, is_deny, created_at, updated_at
)
```

**Layer 3: (Existing, Rename)**
```sql
permission_matrix (was wallet_permission_matrix)
```

---

## API Endpoints

### Layer 1: Wallet-Wide Permissions

```
GET  /api/wallets/:wallet_id/wallet-permissions
PUT  /api/wallets/:wallet_id/wallet-permissions
```

**Request Format (Map-based):**
```json
{
  "entries": [
    {
      "member_group_id": "uuid",
      "permissions": {
        "wallet:info_read": "allow",
        "wallet:info_update": "allow",
        "wallet:members_read": "allow",
        "wallet:members_add": "allow",
        "wallet:members_remove": "allow",
        "wallet:groups_create": "allow",
        "wallet:groups_update": "allow",
        "wallet:groups_delete": "deny",
        "wallet:contact_groups_create": "deny",
        "wallet:contact_groups_update": "unset",
        "wallet:contact_groups_delete": "unset",
        "wallet:metadata_read": "allow",
        "wallet:permissions_edit": "deny",
        "wallet:delete": "unset"
      }
    }
  ]
}
```

### Layer 2: Member-Group-to-Member-Group

```
GET  /api/wallets/:wallet_id/member-groups/:member_group_id/permissions
PUT  /api/wallets/:wallet_id/member-groups/:member_group_id/permissions
```

**Request Format (Map-based):**
```json
{
  "entries": [
    {
      "target_member_group_id": "uuid",
      "permissions": {
        "member_group:members_read": "allow",
        "member_group:members_add": "allow",
        "member_group:members_remove": "allow",
        "member_group:permissions_edit": "unset"
      }
    }
  ]
}
```

### Layer 2.5: Member-Group-to-Contact-Group

```
GET  /api/wallets/:wallet_id/member-groups/:member_group_id/contact-permissions
PUT  /api/wallets/:wallet_id/member-groups/:member_group_id/contact-permissions
```

**Request Format (Map-based):**
```json
{
  "entries": [
    {
      "target_contact_group_id": "uuid",
      "permissions": {
        "contact_group:contacts_read": "allow",
        "contact_group:contacts_add": "allow",
        "contact_group:contacts_remove": "deny"
      }
    }
  ]
}
```

### Layer 3: Contact/Transaction Permissions (Existing, Updated Format)

```
GET  /api/wallets/:wallet_id/permission-matrix
PUT  /api/wallets/:wallet_id/permission-matrix
```

**Request Format (Updated to Map):**
```json
{
  "entries": [
    {
      "user_group_id": "uuid",
      "contact_group_id": "uuid",
      "permissions": {
        "contact:read": "allow",
        "contact:create": "allow",
        "contact:update": "allow",
        "contact:delete": "deny",
        "transaction:read": "allow",
        "transaction:create": "deny",
        "transaction:update": "unset",
        "transaction:delete": "unset",
        "transaction:close": "unset"
      }
    }
  ]
}
```

---

## Authentication & Authorization

### Authentication
All endpoints require JWT token in header:
```
Authorization: Bearer <token>
```

Extract `user_id` from token in middleware.

**ADMIN POLICY - FINAL (Read-Only):**

Admin users from `admin_users` table have **READ-ONLY access** to permission endpoints.

**GET Endpoints (Read Permissions):**
- ✅ `is_admin` can read Layer 1, 2, 2.5, 3 permissions
- ✅ Used for observability, support, troubleshooting
- ✅ Admin page can display wallet permission configuration

**PUT Endpoints (Modify Permissions):**
- ❌ `is_admin` is NOT checked at all
- ❌ Admin cannot modify any permissions
- ✅ Only owner + permission-matrix holders can modify

**Implementation:**
```rust
// GET /api/wallets/:wallet_id/wallet-permissions
if is_admin || is_wallet_owner(...) || has_permission(...) {
  return Ok(Json(fetch_permissions(...)));  // Admin CAN read
}

// PUT /api/wallets/:wallet_id/wallet-permissions
if !is_wallet_owner(..., user_id).await? {
  can_perform(Action::RequiredPermission, ...)?;
}
// is_admin is completely ignored - admin cannot modify
```

### Authorization Pattern (All Layers)

**General Rule:**
```
User can perform action IF:
  is_wallet_owner(wallet_id, user_id) 
  OR 
  can_perform(required_permission)
```

**Implementation:**
```rust
// Owner bypass: if owner, allow everything
if is_wallet_owner(&pool, wallet_id, user_id).await? {
  return Ok(()); // Owner bypass
}

// Non-owner: require specific permission
can_perform(
  &pool,
  &PermissionContext { wallet_id, user_id, user_role },
  Action::SomeAction,  // wallet:permissions_edit, member_group:permissions_set, etc.
  &Resource::...
).await?;

// If can_perform doesn't error, action is allowed
```

---

### Layer 1 (Wallet-wide Permissions) - Modify

**Who Can Modify:** OWNER ONLY

```rust
if !is_wallet_owner(..., user_id).await? {
  return Err(ForbiddenError("Only owner can modify wallet-wide permissions"));
}
// Owner can proceed to modify Layer 1 permissions
```

**What can be modified:**
- Who has `wallet:members_add`, `wallet:members_remove`
- Who has `wallet:groups_create`, `wallet:groups_update`, `wallet:groups_delete`
- Who has `wallet:contact_groups_create`, `wallet:contact_groups_update`, `wallet:contact_groups_delete`
- Who has `wallet:permissions_edit` (the only delegable permission admin role)
- Who has `wallet:metadata_read`, `wallet:info_read`, `wallet:info_update`, `wallet:delete`

**Why owner-only:**
- Layer 1 controls structural access (who can manage groups/members/resources)
- Too administrative to delegate
- Prevents escalation chains
- Owner retains ultimate control

---

### Layer 2 (Member-Group-to-Member-Group Permissions) - Modify

**Who Can Modify:** OWNER ONLY

```rust
if !is_wallet_owner(..., user_id).await? {
  return Err(ForbiddenError("Only owner can modify member-group permissions"));
}
// Owner can proceed to modify Layer 2 permissions
```

**What can be modified:**
- Which member_groups can add/remove members from which other member_groups
- Which member_groups can list members of which other member_groups
- Which member_groups can edit Layer 3 permissions for which other member_groups

**Example:**
- Owner grants "Sellers Admin" group the ability to add members to "Sellers" group
- Owner decides "Finance Lead" can remove members from "Finance" group

**Why owner-only:**
- Layer 2 controls group management authority (who manages whom)
- Too administrative to delegate
- Prevents escalation (group can't grant powers to itself or others)
- Owner retains ultimate control

---

### Layer 2.5 (Contact-Group Permissions) - Modify

**Who Can Modify:** OWNER ONLY

```rust
if !is_wallet_owner(..., user_id).await? {
  return Err(ForbiddenError("Only owner can modify contact-group permissions"));
}
// Owner can proceed to modify Layer 2.5 permissions
```

**What can be modified:**
- Which member_groups can add/remove contacts from which contact_groups
- Which member_groups can view which contact_groups

**Example:**
- Owner grants "Sellers Team" the ability to manage contacts in "Prospects" contact_group
- Owner grants "Finance" the ability to manage "Customers" contact_group

**Why owner-only:**
- Layer 2.5 controls contact group access (who manages which contacts)
- Administrative concern, not operational
- Prevents escalation (group can't grant powers to itself)
- Owner retains ultimate control

---

### Layer 3 (Contact/Transaction Permission Matrix) - Modify

**Who Can Modify:** 
1. **Owner** (hardcoded bypass)
2. OR anyone with **`wallet:permissions_edit`** (global Layer 3 admin for all member_groups)
3. OR anyone with **`member_group:permissions_edit`** scoped to the specific member_group being modified (granular delegation)

```rust
if !is_wallet_owner(..., user_id).await? {
  // Non-owner: check either global or scoped permission edit permission
  
  // Try global permission: can edit Layer 3 for ANY member_group
  let has_global = can_perform(
    &pool,
    &PermissionContext { wallet_id, user_id, user_role: WalletRole::Member },
    Action::WalletPermissionsEdit,
    &Resource::Wallet(wallet_id)
  ).await?;
  
  if !has_global {
    // Try scoped permission: can edit Layer 3 for THIS specific member_group only
    let has_scoped = can_perform(
      &pool,
      &PermissionContext { wallet_id, user_id, user_role: WalletRole::Member },
      Action::MemberGroupPermissionsEdit,
      &Resource::WalletGroup(user_group_id)  // Scoped to specific group
    ).await?;
    
    if !has_scoped {
      return Err("Insufficient permission to modify Layer 3 for this group");
    }
  }
}
```

**What can be modified:**
- Who can read/create/update/delete contacts (C: r c w d)
- Who can read/create/update/delete/close transactions (T: r c w d x)
- For any member_group → contact_group pair

**Why delegable (unlike Layers 1/2/2.5):**
- Layer 3 controls operational data access (who works with what data)
- Not structural/administrative
- Safe to delegate to finance managers, team leads, operational staff
- Less risky than delegating who manages groups/permissions

**⚠️ WARNING:**
- `wallet:permissions_edit` is the ONLY delegable permission management role
- Holder can control all contact/transaction access for everyone
- ONLY owner should grant this permission
- Cannot grant/revoke other Layer 1/2/2.5 permissions

---

### Important Notes

**Owner Bypass (Only Exception):**
- ✅ Wallet owner bypasses ALL permission checks
- ✅ Applied before permission matrix check
- ✅ Hardcoded in handlers

**Permission Checks (Everyone Else):**
- ✅ Always require explicit permission (if not owner)
- ✅ Applied consistently across all layers
- ✅ No special cases (admin is treated as regular member)

**System Admin Role (Read-Only for Observability):**
- **READ access:** ✅ Admin can view all permission configurations (Layer 1/2/2.5/3)
- **WRITE access:** ❌ Admin cannot modify any permissions (no bypass)
- **Use case:** Support team can diagnose issues, monitor wallet setup
- **Safety:** Admin cannot accidentally or maliciously change permissions

---

## Critical Fixes Required

### Fix 1: Remove Admin Bypass from Permission Handlers

**Current (WRONG):**
```rust
async fn require_wallet_admin(...) {
  if auth_user.is_admin {  // ← REMOVE: admin should not bypass wallet perms
    return Ok(());
  }
  if is_wallet_owner(...) {
    return Ok(());
  }
  return Err(...);
}
```

**Corrected:**
```rust
async fn require_wallet_owner_or_permission(..., required_action: Action) {
  // ONLY owner bypass - admin is ignored
  if is_wallet_owner(...).await? {
    return Ok(());  // Owner bypass only
  }
  // Everyone else (including admins) must have permission
  can_perform(&pool, &context, required_action, &resource).await?;
}
```

**Affected Endpoints:**
- `PUT /api/wallets/:wallet_id/wallet-permissions`
- `PUT /api/wallets/:wallet_id/permission-matrix`
- `PUT /api/wallets/:wallet_id/member-groups/:member_group_id/permissions`
- `PUT /api/wallets/:wallet_id/member-groups/:member_group_id/contact-permissions`

**Note:** Admin role policy still being clarified. For now, treat admins the same as regular members for wallet operations.

---

## Implementation Phases

### Phase 1: Domain Updates
1. Add new Action enum variants
2. Add new EventType variants
3. Create database migrations
4. **Fix:** Remove `is_admin` bypass from all permission handlers

### Phase 2: Layer 1 Implementation
1. Update `set_wallet_permissions` handler
2. Add event-sourcing via `insert_permission_event_and_apply()`
3. Update permission resolver

### Phase 3: Layer 2 Implementation
1. Create new endpoints for member-group permissions
2. Add scoped authorization checks
3. Add event-sourcing

### Phase 4: Layer 2.5 Implementation
1. Create new endpoints for contact-group permissions
2. Add scoped authorization checks
3. Add event-sourcing

### Phase 5: Testing & Client Updates
1. Integration tests for all layers
2. Update Rust client
3. Update Flutter UI

---

## Key Code Locations to Modify

**Permission Actions:** `crates/core/domain/src/permission.rs`
- Add Layer 1/2/2.5 actions to enum
- Update `as_str()` and `from_str()`

**Handlers:** `crates/server/src/handlers/wallets.rs`
- Update `set_wallet_permissions()`
- Add new Layer 2/2.5 handlers
- Add GET endpoints

**Resolver:** `crates/server/src/permissions/resolver.rs`
- Add resolution logic for Layer 1/2/2.5
- Support scoped permission checking

**Database:** `crates/server/src/database/repository/permissions.rs`
- Add queries for new tables
- Add event insertion helpers

**Events:** `crates/core/domain/src/event.rs`
- Add new EventType variants
- Update event handler

---

## Unified Format Across All Layers

**All layers use the same pattern: `action: state` map**

```json
{
  "permissions": {
    "action_name": "allow" | "deny" | "unset"
  }
}
```

This ensures:
- ✅ Consistency across all 4 layers
- ✅ No duplicate actions (each action has exactly one state)
- ✅ Easier validation (action can't be in both allow and deny)
- ✅ Clearer intent (one action → one state)

---

## Request/Response Examples

### Layer 1 PUT Request
```json
PUT /api/wallets/wallet-123/wallet-permissions
{
  "entries": [
    {
      "member_group_id": "sales-team",
      "permissions": {
        "wallet:info_read": "allow",
        "wallet:members_add": "allow",
        "wallet:members_remove": "deny",
        "wallet:groups_create": "unset",
        "wallet:permissions_edit": "deny"
      }
    },
    {
      "member_group_id": "finance-team",
      "permissions": {
        "wallet:info_read": "allow",
        "wallet:members_read": "allow",
        "wallet:permissions_edit": "allow"
      }
    }
  ]
}

Response:
{
  "status": "ok",
  "event_id": "event-uuid",
  "message": "Permissions updated"
}
```

### Layer 2 PUT Request
```json
PUT /api/wallets/wallet-123/member-groups/sales-admin/permissions
{
  "entries": [
    {
      "target_member_group_id": "sales-team",
      "permissions": {
        "member_group:members_read": "allow",
        "member_group:members_add": "allow",
        "member_group:members_remove": "allow",
        "member_group:permissions_edit": "deny"
      }
    }
  ]
}

Response:
{
  "status": "ok",
  "event_id": "event-uuid"
}
```

### Layer 3 PUT Request (Permission Matrix with Map Format)

```json
PUT /api/wallets/wallet-123/permission-matrix
{
  "entries": [
    {
      "user_group_id": "sales-team",
      "contact_group_id": "prospects",
      "permissions": {
        "contact:read": "allow",
        "contact:create": "allow",
        "contact:update": "allow",
        "contact:delete": "deny",
        "transaction:read": "allow",
        "transaction:create": "allow",
        "transaction:update": "deny",
        "transaction:delete": "deny",
        "transaction:close": "unset"
      }
    },
    {
      "user_group_id": "finance-team",
      "contact_group_id": "customers",
      "permissions": {
        "contact:read": "allow",
        "contact:create": "deny",
        "contact:update": "deny",
        "contact:delete": "deny",
        "transaction:read": "allow",
        "transaction:create": "allow",
        "transaction:update": "allow",
        "transaction:delete": "deny",
        "transaction:close": "allow"
      }
    }
  ]
}

Response:
{
  "status": "ok",
  "event_id": "event-uuid",
  "message": "Permission matrix updated"
}
```

---

## Testing Strategy

### Unit Tests
- Serialization/deserialization of PermissionState enum
- Action name parsing and validation
- Event type mapping

### Integration Tests
- Full workflow: create group → set permissions → verify resolution
- Deny-wins rule verification
- Scoped permissions (admin can only modify assigned groups)
- Event replay and crash recovery

### End-to-End Tests
- API request validation (bad UUIDs, invalid actions)
- Authorization failures
- Full permission matrix with all 4 layers

---

## Success Criteria

✅ All 4 layers implemented with full vector replacement  
✅ Event-based storage for all layers  
✅ Authorization checks prevent unauthorized modifications  
✅ Scoped permissions work correctly  
✅ 90%+ test coverage  
✅ Zero permission bypass vulnerabilities  
✅ Client can sync all layers  
✅ Admin role NOT used in permission handlers

---

## Permission Modification Authority (Who Can Change What)

### Who Modifies Each Layer

| Layer | Who Can Modify | Delegable? | Why |
|-------|----------------|-----------|-----|
| **Layer 1** (wallet-wide perms) | Owner ONLY | ❌ NO | Too structural/administrative |
| **Layer 2** (group-to-group perms) | Owner ONLY | ❌ NO | Too administrative (group management) |
| **Layer 2.5** (contact-group perms) | Owner ONLY | ❌ NO | Too administrative (resource management) |
| **Layer 3** (data access perms) | Owner + `wallet:permissions_edit` (global) OR `member_group:permissions_edit` (scoped) | ✅ YES | Operational (who works with what data) |

---

## Permission Power Levels (Security Tiers)

### Tier 1: Operational Permissions (Safe to Delegate)
- `wallet:members_add`, `wallet:members_remove` — Add/remove people
- `wallet:groups_create`, `wallet:groups_update`, `wallet:groups_delete` — Manage groups
- `wallet:contact_groups_create`, etc. — Manage contact groups
- `wallet:info_read`, `wallet:metadata_read` — View wallet info

**Who can grant:** Owner only  
**Can be delegated to:** No one (owner controls)  
**Risk:** Low (only owner decides who does what)

---

### Tier 2: Delegable Layer 3 Permission Management Roles

**Option A: Global (`wallet:permissions_edit`)**
- **`wallet:permissions_edit`** — Control Layer 3 for ALL member_groups
- **Who can grant:** Owner only  
- **Can be delegated to:** Yes, to one highly trusted operator (finance manager, compliance officer)  
- **Risk:** VERY HIGH - Controls all data access for all users on all groups  
- **Mitigation:** Owner must verify trustworthiness; grant only to most senior operators

**Option B: Scoped (`member_group:permissions_edit`)**
- **`member_group:permissions_edit`** — Control Layer 3 for ONE specific member_group (scoped)
- **Who can grant:** Owner only  
- **Can be delegated to:** Yes, to team leads or managers (safer than global)  
- **Risk:** MEDIUM - Controls data access for one team only  
- **Mitigation:** Safer delegation; owner can grant per-team without full wallet-wide access

**Key Difference:**
- `wallet:permissions_edit`: "Can modify Layer 3 for ANY member_group" (dangerous)
- `member_group:permissions_edit`: "Can modify Layer 3 only for MY team" (safer)

---

### Tier 3: Owner (Ultimate Authority)
- Owner bypass → Can modify ANY layer
- Can grant `wallet:permissions_edit` (global Layer 3 admin) or `member_group:permissions_edit` (scoped to specific team)
- Can grant/revoke ALL Layer 1/2/2.5 permissions (structural)
- Cannot be revoked (except by removing from wallet_owners)

**Only:** Wallet creator, other owners

---

## Summary

```
Layer 1/2/2.5 Modifications:
  Only Owner (NON-DELEGABLE)
    ↓
    Can set structural permissions
    (wallets, groups, contact groups)

Layer 3 Modifications:
  Owner 
    OR wallet:permissions_edit holder (global Layer 3 admin for ANY group)
    OR member_group:permissions_edit holder (scoped to ONE group)
    ↓
    Can control who reads/writes data
    (CAN delegate: globally or per-team)
```

---

## Future Task: Clarify Admin Role Policy

**Status:** TBD  
**Scope:** Define what admin users should/should not be able to do

**Questions to Answer:**
1. Should admins have read-only access to wallets/permissions?
2. Should admins be able to recover from permission mistakes?
3. Should admins audit permission changes?
4. Can admins bypass owner restrictions?
5. Do admins need their own permission matrix?

**Once Clarified:**
- Document admin policy
- Implement admin-specific authorization rules
- Add admin-specific endpoints (if needed)
- Update handlers with admin checks

**For Now:** Admin is ignored in permission handlers. Treat admin users same as regular members.
