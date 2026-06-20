# Owner Permission Threat Model & Security Test Results

**Status**: Security testing complete. 4 vulnerabilities identified and documented.

---

## Executive Summary

The owner permission system has **4 critical vulnerabilities** that allow unauthorized modification of owner permissions. 2 attack vectors are already protected. A regression test suite exists at `crates/client/tests/owner_permission_security_test.rs`.

Run tests: `cargo nextest run --test integration owner_permission_security -- --ignored`

---

## Threat Model Overview

**Key Assets to Protect:**

1. **Owner Permission Vector**: `(all_contacts, __owners__)`
   - Must ALWAYS grant all permissions (contact:read/create/write/delete, transaction:read/create/write/delete/close)
   - Must NEVER be modifiable by admins or members
   
2. **Owner Group Membership**: `__owners__` group
   - Only wallet owners should be members
   - Cannot be modified by anyone except system (wallet creation, ownership transfer)
   
3. **System Group Integrity**: `__owners__` group metadata
   - Must remain marked as `is_system = true`
   - Cannot be renamed, deleted, or recreated
   - Must prevent duplicate groups with same name

---

## Vulnerability Assessment

### ✅ PROTECTED (Already Blocked)

#### 1. Rename __owners__ group
- **Attack**: Try to rename `__owners__` to `renamed_owners`
- **Status**: ✅ BLOCKED
- **Protection**: The `reject_system_user_group()` check in `update_wallet_user_group` handler prevents renaming system groups
- **Code**: `crates/server/src/handlers/wallets.rs:1409-1432`

#### 2. Delete __owners__ group
- **Attack**: Try to delete `__owners__` group entirely
- **Status**: ✅ BLOCKED
- **Protection**: The `reject_system_user_group()` check in `delete_wallet_user_group` handler prevents deleting system groups
- **Code**: `crates/server/src/handlers/wallets.rs:1409-1432`

#### 3. Remove owner from __owners__ group
- **Attack**: Try to remove owner from `__owners__` group
- **Status**: ✅ BLOCKED
- **Protection**: The `reject_system_user_group()` check in `remove_wallet_user_group_member` handler prevents modifying system groups
- **Code**: `crates/server/src/handlers/wallets.rs:1409-1432`

---

### ⚠️ VULNERABLE (Need Fixes)

#### 1. Remove all permissions from (all_contacts, __owners__)
- **Attack Vector**: Call `PUT /wallets/{wallet_id}/permission-matrix` with empty allowed/denied arrays for `(all_contacts, __owners__)`
- **Current Behavior**: ❌ SUCCEEDS - Owner loses all permissions
- **Observable Effect**: Owner can no longer read contacts, create transactions, or perform any action
- **Fix Location**: `crates/server/src/handlers/wallets.rs:2421-2533` (put_permission_matrix function)
- **Required Fix**: Add validation to reject modifications to `(all_contacts, __owners__)` permission vector

#### 2. Add permissions to (__owners__, custom_contact_group)
- **Attack Vector**: Call `PUT /wallets/{wallet_id}/permission-matrix` with permissions for `(__owners__, custom_group)` pair
- **Current Behavior**: ❌ SUCCEEDS - Owner gains unexpected permissions
- **Observable Effect**: Creates invalid permission matrix where owner has rights on non-all_contacts groups
- **Fix Location**: `crates/server/src/handlers/wallets.rs:2421-2533` (put_permission_matrix function)
- **Required Fix**: Add validation to reject permission matrix entries where user_group=__owners__ and contact_group!=all_contacts

#### 3. Add wallet owner to non-owners group
- **Attack Vector**: Call `PUT /wallets/{wallet_id}/user-groups/{other_group_id}/members/{owner_username}` 
- **Current Behavior**: ❌ SUCCEEDS - Owner becomes member of arbitrary groups
- **Observable Effect**: Owner's permissions become dependent on both __owners__ and custom groups
- **Fix Location**: `crates/server/src/handlers/wallets.rs:1729-1770` (add_wallet_user_group_member function)
- **Required Fix**: Add validation to reject adding wallet owners to non-__owners__ groups

#### 4. Create duplicate __owners__ group (Name Spoofing)
- **Attack Vector**: Call `POST /wallets/{wallet_id}/user-groups` with name="__owners__"
- **Current Behavior**: ❌ SUCCEEDS - Creates second group with system group name
- **Observable Effect**: Creates confusion; could be used in conjunction with other attacks
- **Fix Location**: `crates/server/src/handlers/wallets.rs:1468-1510` (create_wallet_user_group function)
- **Required Fix**: Add uniqueness constraint or validation to prevent user groups named "__owners__"

---

## Implementation Strategy

### Single Centralized Enforcement Point

Instead of scattered if-checks in 10 different places, implement a dedicated validation module:

**Proposed Structure:**
```
crates/server/src/
├── permissions/
│   ├── mod.rs
│   └── owner_protection.rs        ← NEW: Centralized validation
└── handlers/
    └── wallets.rs                 ← Call into owner_protection
```

**Key Principle**: All paths that could affect owner permissions funnel through ONE validation function that:
1. Detects if operation involves owner/ownership transfer
2. Prevents unauthorized modification of protected vectors
3. Returns clear error messages
4. Is exhaustively tested

### Attack Vectors to Validate

```rust
/// Centralized owner permission validation
mod owner_protection {
    pub fn validate_permission_matrix_modification(
        wallet_id: Uuid,
        user_group_id: Uuid,
        contact_group_id: Uuid,
        // ... other params
    ) -> Result<(), OwnerProtectionError> {
        // Rule 1: Reject modifications to (all_contacts, __owners__)
        // Rule 2: Reject modifications to (__owners__, non-all_contacts)
        // Rule 3: Log security events
    }

    pub fn validate_user_group_membership_change(
        wallet_id: Uuid,
        user_group_id: Uuid,
        user_id: Uuid,
        operation: MembershipOp,  // Add | Remove
    ) -> Result<(), OwnerProtectionError> {
        // Rule 4: Reject adding owners to non-__owners__ groups
        // Rule 5: Reject removing owners from __owners__ group (already protected)
    }

    pub fn validate_user_group_creation(
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), OwnerProtectionError> {
        // Rule 6: Reject groups named "__owners__" (unless system creation)
        // Rule 7: Prevent other system group name spoofing
    }
}
```

---

## Test Coverage

**Test File**: `crates/client/tests/owner_permission_security_test.rs`

**Test Results** (as of 2026-06-20):
- Total tests: 8
- Protected: 4 ✅
- Vulnerable: 4 ⚠️

**Run All Tests**:
```bash
cargo nextest run --test integration owner_permission_security -- --ignored
```

**Run Individual Attack**:
```bash
cargo nextest run --test integration attack_vector_1a -- --ignored
```

---

## Critical Implementation Notes

### 1. Wallet Owner Identification
- Use `wallet_owners` table to identify wallet owners
- Query: `SELECT user_id FROM wallet_owners WHERE wallet_id = $1`

### 2. __owners__ Group Identification
- User group with `wallet_id = ?` AND `name = '__owners__'` AND `is_system = true`
- All validation MUST check `is_system = true` to prevent spoofing with duplicate names

### 3. all_contacts Group Identification
- Contact group with `wallet_id = ?` AND `name = 'all_contacts'` AND `is_system = true`
- The ONLY valid contact group for owner permissions

### 4. Error Responses
- Should return clear, non-revealing error messages
- Log security events (who tried to do what)
- Consider rate-limiting failed attempts

### 5. Consistency During Replay
- Event applier must also validate these rules
- Incoming events that violate rules should be rejected or corrected during replay
- No silent failures on corrupt/legacy event data

---

## Related Documents

- [[../04-permissions-and-undo/05-permission-format-system.md]] - Permission format specification
- [[../04-permissions-and-undo/02-permission-events.md]] - Permission event types
- [[../05-implementation-patterns/05-permission-test-format.md]] - How to write permission tests

