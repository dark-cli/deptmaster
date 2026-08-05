# Owner Permissions: Hardcoded Bypass Model

**Status**: Current implementation  
**Date**: 2026-08-05  
**Rationale**: Simplified owner model using hardcoded bypass instead of permission matrix

---

## Overview

Wallet owners have **unrestricted access to all operations** via a hardcoded bypass check in the permission resolver. They do NOT use the permission matrix system.

## Implementation

### Hardcoded Bypass in Resolver

In `crates/server/src/permissions/resolver.rs`:

```rust
pub async fn can_perform(
    pool: &PgPool,
    ctx: &PermissionContext,
    action: Action,
    resource: &Resource,
) -> Result<bool, DbError> {
    // Owners bypass all permission checks
    if is_wallet_owner(pool, ctx.wallet_id, ctx.user_id).await? {
        return Ok(true);
    }

    // Non-owners check permission matrix
    let allowed = resolve_actions(pool, ctx, resource).await?;
    Ok(allowed.iter().any(|a| a.implies(action)))
}
```

### Owner Identification

Owners are determined by `wallet_owners` table lookup:

```rust
async fn is_wallet_owner(
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
) -> Result<bool, DbError> {
    sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM wallet_owners WHERE wallet_id = $1 AND user_id = $2)"
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(pool)
    .await
}
```

## Why This Model

### Simplicity
- Owners don't need to configure/understand permission matrix
- One check per operation: "is this user an owner?"
- Clearer security model: owners = full access, period

### Performance
- Single database query to check ownership
- No permission matrix lookups for owners
- Direct bypass without resolver overhead

### Clarity
- No confusion about owner permissions (they're absolute)
- No "does __owners__ group apply?" questions
- Security model is obvious: owners have full control

## What This Means for the UI

**Permission Rules Screen:**
- Should NOT show `__owners__` group (it's not used)
- `__owners__` group creation removed from wallet initialization
- Only non-owners' permissions are configured in matrix

**Wallet Permissions Screen:**
- Owners always have full delegable permissions (hardcoded)
- Non-owners' permissions shown/configurable
- No need to configure owner permissions

## Related Permissions

- **Wallet-level permissions**: Only non-owners check matrix
- **Member/Contact group permissions**: Only non-owners check matrix
- **Layer 1-3 resolver**: All call `can_perform()` which checks `is_wallet_owner()` first

## Removed Redundant Code

**Commit 296f12a** removed:
- `__owners__` system group creation during wallet initialization
- Adding owner to `__owners__` group
- Granting full permissions to `__owners__` group via permission matrix
- Related documentation claiming owners use permission matrix

## Security Properties

✅ Owners always have unrestricted access  
✅ Simple, auditable implementation  
✅ No permission matrix misconfiguration can restrict owners  
✅ Admin role is separate (admins are NOT automatically owners)
