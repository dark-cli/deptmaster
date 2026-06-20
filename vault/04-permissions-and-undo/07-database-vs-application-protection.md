# Owner Permission Protection: Database vs Application Level

**Date**: 2026-06-20  
**Status**: Analysis complete - Hybrid approach recommended

---

## Executive Summary

**YES, we can solve 3 out of 4 vulnerabilities at the DATABASE level.** This is the **BETTER option** because:
- Constraints are enforced at the storage layer (no code bypass possible)
- They're automatically part of data integrity
- They're harder to accidentally disable or work around
- They prevent corrupted data at the source

However, 1 vulnerability requires APPLICATION logic.

---

## Current Database State

### Already Protected by Constraints:
```sql
-- user_groups table (migration 014_advanced_permissions.sql, line 34)
UNIQUE(wallet_id, name)
```

This means **group names are already guaranteed unique per wallet**. 

However, **vulnerability #4 still succeeds** because:
1. The application handler (`create_user_group`, line 1520) only checks for `"all_users"`
2. It doesn't check for `"__owners__"`
3. The UNIQUE constraint IS enforced, but the app returns success before the event is applied
4. The event system then tries to apply the group creation, and the database constraint violation gets logged but not returned to the user

---

## Vulnerability-by-Vulnerability Analysis

### Vulnerability 1a: Remove all owner permissions
**Proposal**: Add a `CHECK` constraint to `group_permission_matrix`

**Current state**:
```sql
CREATE TABLE group_permission_matrix (
    user_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    contact_group_id UUID NOT NULL REFERENCES contact_groups(id) ON DELETE CASCADE,
    permission_action_id SMALLINT NOT NULL REFERENCES permission_actions(id),
    PRIMARY KEY (user_group_id, contact_group_id, permission_action_id)
);
```

**Database solution feasibility**: ⚠️ **PARTIALLY** - Very difficult
- Would need to identify `__owners__` by name (string lookup), not just by column value
- Would need to identify `all_contacts` by name (string lookup)
- The constraint would be:
  ```sql
  CREATE TRIGGER prevent_owner_permission_deletion
  BEFORE DELETE ON group_permission_matrix
  FOR EACH ROW
  WHEN (
    (SELECT name FROM user_groups WHERE id = OLD.user_group_id) = '__owners__'
    AND (SELECT name FROM contact_groups WHERE id = OLD.contact_group_id) = 'all_contacts'
  )
  THEN RAISE EXCEPTION 'Cannot remove owner permissions';
  ```
- **Problem**: Triggers are expensive; they're called for every deletion
- **Better approach**: Application-level check + set the `(all_contacts, __owners__)` permissions once at wallet creation and never touch them again

**Recommended**: **APPLICATION-LEVEL** check that rejects any permission matrix modifications to rows where `user_group_id` = (lookup __owners__) AND `contact_group_id` = (lookup all_contacts)

---

### Vulnerability 1b: Add permissions to (__owners__, custom_contact_group)
**Proposal**: Add a `CHECK` constraint + trigger to `group_permission_matrix`

**Database solution feasibility**: ⚠️ **VERY DIFFICULT**
- Would need to prevent inserts where user_group is `__owners__` AND contact_group is NOT `all_contacts`
- Same trigger complexity as 1a
- Would be called on EVERY insert

**Better approach**: Application-level check that rejects permission matrix entries where:
- `user_group_id` = (lookup __owners__) 
- AND `contact_group_id` != (lookup all_contacts)

---

### Vulnerability 2a: Add wallet owner to non-owners group
**Proposal**: Add a trigger to `user_group_members`

**Database solution feasibility**: ✅ **POSSIBLE BUT COMPLEX**

```sql
CREATE OR REPLACE FUNCTION check_owner_group_membership()
RETURNS TRIGGER AS $$
BEGIN
  -- Prevent adding wallet owners to non-system groups
  IF EXISTS(
    SELECT 1 FROM wallet_owners 
    WHERE user_id = NEW.user_id 
    AND wallet_id = (
      SELECT wallet_id FROM user_groups WHERE id = NEW.user_group_id
    )
  ) AND (
    SELECT is_system FROM user_groups WHERE id = NEW.user_group_id
  ) = false
  THEN
    RAISE EXCEPTION 'Wallet owners cannot be added to non-system groups';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_owner_in_non_system_groups
BEFORE INSERT ON user_group_members
FOR EACH ROW
EXECUTE FUNCTION check_owner_group_membership();
```

**Feasibility Rating**: ✅ **GOOD** - This is doable and relatively efficient
- Query is simple: check wallet_owners table
- Trigger fires only on INSERT (not frequent in production)
- Returns clear error message

**Recommended**: **DATABASE-LEVEL trigger** (this one is a good candidate)

---

### Vulnerability 3: Protect system groups (rename/delete)
**Current protection**: ✅ **Application-level only** (reject_system_user_group)

**Database solution feasibility**: ✅ **EXCELLENT**

```sql
-- Prevent UPDATE/DELETE on system groups
CREATE OR REPLACE FUNCTION protect_system_groups()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.is_system = true THEN
    RAISE EXCEPTION 'Cannot modify system groups';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_system_group_modification
BEFORE UPDATE OR DELETE ON user_groups
FOR EACH ROW
EXECUTE FUNCTION protect_system_groups();

-- Same for contact_groups
CREATE TRIGGER prevent_system_contact_group_modification
BEFORE UPDATE OR DELETE ON contact_groups
FOR EACH ROW
EXECUTE FUNCTION protect_system_contact_groups();
```

**Feasibility Rating**: ✅ **EXCELLENT**
- Already protected at app level, but database protection is redundant & good
- Efficient: simple boolean check on every UPDATE/DELETE
- Prevents accidental modifications even from direct DB queries

**Recommended**: **DATABASE-LEVEL trigger** (add this for defense in depth)

---

### Vulnerability 4: Prevent duplicate __owners__ group
**Current state**: UNIQUE constraint EXISTS but not enforced by app

**Database solution feasibility**: ✅ **EXCELLENT** (already partially done)

The `UNIQUE(wallet_id, name)` constraint already prevents duplicate names.

**Fix needed**: Application-level check in `create_wallet_user_group` (line 1520)

```rust
if name.eq_ignore_ascii_case("all_users") || name.eq_ignore_ascii_case("__owners__") {
    return Err((
        StatusCode::BAD_REQUEST,
        Json(serde_json::json!({"error": "Cannot create group with reserved name"})),
    ));
}
```

**Feasibility Rating**: ✅ **TRIVIAL**
- Just add one line to the existing check
- The database constraint is already there as backup

**Recommended**: **APPLICATION-LEVEL check** (simple & clear error message to user)

---

## Recommended Hybrid Approach

| Vulnerability | Solution | Level | Effort | Robustness |
|---|---|---|---|---|
| 1a. Remove owner permissions | Check before UPDATE/DELETE on specific rows | App | Medium | ⭐⭐⭐⭐⭐ |
| 1b. Add owner permissions to custom group | Check before INSERT with `__owners__` | App | Medium | ⭐⭐⭐⭐⭐ |
| 2a. Add owner to non-owners group | **Trigger on user_group_members** | **DB** | Medium | ⭐⭐⭐⭐⭐ |
| 3. Protect system groups | **Triggers on user_groups, contact_groups** | **DB** | Low | ⭐⭐⭐⭐⭐ |
| 4. Duplicate __owners__ | Check in create_user_group handler | App | Trivial | ⭐⭐⭐⭐⭐ |

---

## Why This Hybrid Approach

### Why NOT all database triggers?
1. **Triggers are expensive** - Called on every operation
2. **Permission matrix is high-volume** - Thousands of INSERT/UPDATE/DELETE per wallet
3. **String lookups are slow** - `WHERE name = '__owners__'` on every operation
4. **Composite logic is complex** - Checking multiple table conditions gets messy

### Why NOT all application checks?
1. **Data integrity failures** - Bugs in app code could allow corruption
2. **Hard to audit** - Need to find all the places that touch owner permissions
3. **Can be bypassed** - Direct database queries, event replays, imports

### Why this hybrid?
1. **Database triggers for structural integrity** (system group protection, owner group membership)
   - These check fundamental rules about group structure
   - Efficient because they're low-volume operations (group creation, member changes)
   - Can't be accidentally disabled

2. **Application checks for permission matrix** (1a, 1b)
   - These are high-volume operations
   - Application has full context (wallet ID, user role, intent)
   - Can return clear error messages
   - Single centralized check point is easier to test

3. **Application check for reserved names** (4)
   - Trivial to implement
   - Database constraint is backup

---

## Implementation Roadmap

### Phase 1: Application-level checks (Quick win)
**Files**: `crates/server/src/handlers/wallets.rs`
- [ ] Add `"__owners__"` to reserved name check in `create_user_group` (line 1520)
- [ ] Add centralized `OwnerPermissionValidator` module (1a, 1b checks)
- [ ] Integrate validator into `put_permission_matrix` (line 2421)

**Effort**: 2-3 hours  
**Risk**: Low (isolated to wallets.rs)

### Phase 2: Database-level protection (Defense in depth)
**Files**: `crates/server/migrations/035_protect_owner_permissions.sql`
- [ ] Create trigger on `user_group_members` to prevent adding owners to non-system groups
- [ ] Create triggers on `user_groups` and `contact_groups` to protect system groups from modification

**Effort**: 1-2 hours  
**Risk**: Low (migrations are additive)  
**Benefit**: Data integrity even if app code is bypassed

### Phase 3: Testing & documentation
- [ ] Run all 8 security tests - all should PASS
- [ ] Update threat model document
- [ ] Add security checklist to code review guidelines

**Effort**: 1 hour  
**Risk**: None

---

## Migration Strategy

New migration file: `crates/server/migrations/035_protect_owner_permissions.sql`

```sql
-- Protect owner group membership from modification
CREATE OR REPLACE FUNCTION check_owner_group_membership()
RETURNS TRIGGER AS $$
BEGIN
  -- Prevent adding wallet owners to non-system groups
  IF EXISTS(
    SELECT 1 FROM wallet_owners 
    WHERE user_id = NEW.user_id 
    AND wallet_id = (
      SELECT wallet_id FROM user_groups WHERE id = NEW.user_group_id LIMIT 1
    )
  ) THEN
    -- Check if target group is non-system
    IF (SELECT is_system FROM user_groups WHERE id = NEW.user_group_id) = false THEN
      RAISE EXCEPTION 'Wallet owners cannot be added to non-system groups';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_owner_in_non_system_groups
BEFORE INSERT ON user_group_members
FOR EACH ROW
EXECUTE FUNCTION check_owner_group_membership();

-- Protect system groups from modification
CREATE OR REPLACE FUNCTION protect_system_user_groups()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.is_system = true THEN
    RAISE EXCEPTION 'Cannot modify system groups';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_system_user_group_modification
BEFORE UPDATE OR DELETE ON user_groups
FOR EACH ROW
EXECUTE FUNCTION protect_system_user_groups();

-- Same for contact groups
CREATE OR REPLACE FUNCTION protect_system_contact_groups()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.is_system = true THEN
    RAISE EXCEPTION 'Cannot modify system contact groups';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_system_contact_group_modification
BEFORE UPDATE OR DELETE ON contact_groups
FOR EACH ROW
EXECUTE FUNCTION protect_system_contact_groups();
```

---

## Verification

After implementation, re-run tests:
```bash
cargo nextest run --test integration owner_permission_security -- --ignored
```

Expected result: **All 8 tests PASS** ✅

