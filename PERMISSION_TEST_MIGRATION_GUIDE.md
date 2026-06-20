# Permission Test Migration Guide

## Overview

All permission tests are being migrated from manual API calls to the new command-based format with rwx-inspired permission naming.

## New Permission Format

```
C: r:a c:a w:a d:-
T: r:a c:d w:a d:- x:-
```

**Legend:**
- `C` = Contact permissions
- `T` = Transaction permissions
- `r` = read
- `c` = create
- `w` = write/update
- `d` = delete
- `x` = close (transaction only)
- `:a` = allow
- `:d` = deny
- `:-` = unset

## Migration Pattern

### Before: Manual API Calls
```rust
// Create groups manually
create_wallet_user_group(wallet_id.clone(), "Editors".to_string())?;
let ug_json = list_wallet_user_groups(wallet_id.clone())?;
let ug_id = group_id_by_name(&ug_json, "Editors")?;

// Set permissions as JSON
let entry = serde_json::json!({
    "user_group_id": ug_id,
    "contact_group_id": cg_id,
    "allowed_actions": ["contact:update"],
    "denied_actions": []
});
put_wallet_permission_matrix(wallet_id.clone(), entries.to_string())?;
```

### After: Command Format
```rust
let commands = [
    "owner: user-group create \"Editors\" editors",
    "owner: contact-group create \"TestGroup\" testgroup",
    "owner: group-member add editors user_id",
    
    // Clear permission format
    "owner: permission set editors testgroup \"C: r:- c:- w:a d:-, T: r:- c:- w:- d:- x:-\"",
    
    "member: sync",
];
generator.execute_commands(&commands)?;
```

## Common Permission Patterns

### Read-Only
```
"C: r:a c:- w:- d:-, T: r:a c:- w:- d:- x:-"
```

### Read + Write (No Delete)
```
"C: r:a c:a w:a d:-, T: r:a c:a w:a d:- x:-"
```

### Full Permissions
```
"C: r:a c:a w:a d:a, T: r:a c:a w:a d:a x:a"
```

### Write Only (No Read)
```
"C: r:- c:- w:a d:-, T: r:- c:- w:- d:- x:-"
```

### Deny Pattern (Read + Deny Write)
```
"C: r:a c:- w:d d:-, T: r:a c:- w:d d:- x:-"
```

## Tests Migrated

✅ **permission_edit_without_read_no_dependencies_modern**
- Tests that edit permission can be set without read
- Uses format: `"C: r:- c:- w:a d:-, T: r:- c:- w:- d:- x:-"`

## Tests to Migrate

The following tests from `permissions.rs` should be migrated:

1. `permission_give_take_read_member_sees_then_loses_then_sees`
   - Scenario: Grant read, revoke all, grant read again
   - New format: `"C: r:a c:- w:- d:-, T: r:a c:- w:- d:- x:-"`

2. `permission_grant_create_then_member_can_create`
   - Scenario: Grant full permissions, member creates contact
   - New format: `"C: r:a c:a w:a d:a, T: r:a c:a w:a d:a x:-"`

3. `permission_limits_deny_overrides_allow`
   - Scenario: Test that deny overrides allow
   - New format: `"C: r:a c:d w:- d:-, T: r:a c:d w:- d:- x:-"`

4. Group-based tests (`groups_*`)
   - Same pattern, multiple user/contact groups
   - Example: `"permission set team1 customers \"C: r:a c:- w:a d:-, T: r:a c:- w:- d:- x:-\""`

## Benefits

| Aspect | Before | After |
|--------|--------|-------|
| **Readability** | 20+ lines for setup | 5-6 command lines |
| **Clarity** | Hard to see permission logic | Clear at a glance |
| **Maintainability** | Scattered API calls | Self-documenting commands |
| **Debugging** | Have to trace through JSON | Permission format visible in test |

## Implementation Checklist

- [x] Create EventGenerator-based test template
- [x] Implement permission format parser
- [x] Add user-group/contact-group commands
- [x] Add group-member command
- [x] Add permission set command
- [ ] Migrate permission_give_take_read_member_sees_then_loses_then_sees
- [ ] Migrate permission_grant_create_then_member_can_create
- [ ] Migrate permission_limits_deny_overrides_allow
- [ ] Migrate all group-based tests
- [ ] Migrate permission_enforce tests
- [ ] Delete old test implementations (keep until all migrated)
