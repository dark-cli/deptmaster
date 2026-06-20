# Permission Format Reference

Quick reference for the rwx-inspired permission notation system.

---

## Format Template

```
C: r:_ c:_ w:_ d:-, T: r:_ c:_ w:_ d:_ x:-
```

Replace `_` with: `a` (allow), `d` (deny), or `-` (unset)

---

## Permission Letters

| Letter | Action | Resource | Notes |
|--------|--------|----------|-------|
| `r` | **read** | Both | View/see the resource |
| `c` | **create** | Both | Add new resource |
| `w` | **write** | Both | Modify existing resource |
| `d` | **delete** | Both | Remove resource |
| `x` | **close** | Transactions only | Mark transaction as settled |

**Resource Sections:**
- `C:` = **Contact** permissions (must include r, c, w, d)
- `T:` = **Transaction** permissions (must include r, c, w, d, x)

---

## State Values

| State | Meaning | Usage |
|-------|---------|-------|
| `:a` | **Allow** | Permission is granted |
| `:d` | **Deny** | Permission is explicitly denied |
| `:-` | **Unset** | Permission not configured |

---

## Common Permission Sets

### View Only
```
C: r:a c:- w:- d:-, T: r:a c:- w:- d:- x:-
```
✓ Can view contacts and transactions
✗ Cannot create, edit, or delete

### Full Editor
```
C: r:a c:a w:a d:a, T: r:a c:a w:a d:a x:a
```
✓ Can do everything with contacts and transactions

### Read + Update Only
```
C: r:a c:- w:a d:-, T: r:a c:- w:a d:- x:-
```
✓ Can view and edit
✗ Cannot create or delete

### Edit Without Read (Special Case)
```
C: r:- c:- w:a d:-, T: r:- c:- w:- d:- x:-
```
⚠ Write implies read (via resolver)
✓ Member gets implicit read to see what they're editing

### Transaction Specialist
```
C: r:a c:- w:- d:-, T: r:a c:a w:a d:a x:a
```
✓ Full control over transactions
✓ Can view contacts
✗ Cannot modify or create contacts

### Denied Writer
```
C: r:a c:- w:d d:-, T: r:a c:- w:d d:- x:-
```
✓ Can view contacts and transactions
✗ Explicitly prevented from editing

---

## Maps to Action Names

### Contact Actions
| Format | Permission | Action Name |
|--------|-----------|-------------|
| `r:a` in C | read allow | `contact:read` |
| `c:a` in C | create allow | `contact:create` |
| `w:a` in C | write allow | `contact:update` |
| `d:a` in C | delete allow | `contact:delete` |
| `r:d` in C | read deny | `contact:read` (in denied list) |
| `c:d` in C | create deny | `contact:create` (in denied list) |
| `w:d` in C | write deny | `contact:update` (in denied list) |
| `d:d` in C | delete deny | `contact:delete` (in denied list) |

### Transaction Actions
| Format | Permission | Action Name |
|--------|-----------|-------------|
| `r:a` in T | read allow | `transaction:read` |
| `c:a` in T | create allow | `transaction:create` |
| `w:a` in T | write allow | `transaction:update` |
| `d:a` in T | delete allow | `transaction:delete` |
| `x:a` in T | close allow | `transaction:close` |
| (deny versions map to denied_actions) |

---

## Testing Examples

### Bash Command Line (EventGenerator)
```bash
"owner: permission set editors customers \"C: r:a c:- w:a d:-, T: r:a c:- w:- d:- x:-\""
```

### Rust Test Setup
```rust
let entry = serde_json::json!({
    "user_group_id": group_id,
    "contact_group_id": contact_group_id,
    "allowed_actions": ["contact:read", "contact:update", "transaction:read"],
    "denied_actions": []
});
let entries = serde_json::json!([entry]);
put_wallet_permission_matrix(wallet_id, entries.to_string())?;

// Equivalent format: C: r:a c:- w:a d:-, T: r:a c:- w:- d:- x:-
```

---

## Permission Resolution (Implies)

When a user has permission for an action, they implicitly get related permissions:

```
write:update    → grants read:read      (can't edit what you can't see)
create:create   → grants read:read      (can't create what you can't see)
delete:delete   → grants read:read      (can't delete what you can't see)
transaction:close → grants contact:read (can't close transaction without contact context)
```

**Implication:** Writing `C: r:- c:- w:a d:-` is valid. The user gets implicit read permission at runtime.

---

## Quick Checklist

When writing a permission in format:

- [ ] Specified both `C:` and `T:` sections
- [ ] All 4 contact permissions (r, c, w, d)
- [ ] All 5 transaction permissions (r, c, w, d, x)
- [ ] Each permission has a state (`:a`, `:d`, or `:-`)
- [ ] Verified with the "Maps to Action Names" table above
- [ ] Added explanatory comment if unusual (e.g., edit-without-read)

---

## Related Documents

- [[../04-permissions-and-undo/05-permission-format-system.md]] - Detailed explanation
- [[../05-implementation-patterns/05-permission-test-format.md]] - How to write tests
- [[../04-permissions-and-undo/02-permission-events.md]] - Event structure
- [[01-glossary.md]] - General terminology
