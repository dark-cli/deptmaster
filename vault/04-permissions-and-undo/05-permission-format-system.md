# Permission Format System: rwx-Inspired Notation

**Main question this file answers:** How is the permission system represented in tests and UI?

---

## Overview

The permission system uses a **compact, human-readable notation** inspired by Unix file permissions (rwx). This format clearly shows:
- Which **resource** (Contact or Transaction)
- Which **action** (read, create, write/update, delete, close)
- What **state** (allow, deny, unset)

### Why This Format?

1. **Clarity**: Much more readable than JSON with action names
2. **Brevity**: Fits on a single line in tests
3. **Familiar**: Developers understand rwx-style notation
4. **Complete**: Unlike Unix rwx, we can represent **three states**: allow, deny, unset

---

## Format Specification

### Basic Structure

```
C: r:a c:a w:a d:-, T: r:a c:a w:a d:a x:a
│  │   │   │   │      │  │   │   │   │   │
│  │   │   │   │      │  │   │   │   │   └─ close (transaction only)
│  │   │   │   │      │  │   │   │   └───── delete
│  │   │   │   │      │  │   │   └────────── write/update
│  │   │   │   │      │  │   └───────────── create
│  │   │   │   │      │  └──────────────── read
│  │   │   │   │      └─────────────────── Transaction permissions
│  │   │   │   └────────────────────────── delete
│  │   │   └─────────────────────────────── write/update
│  │   └──────────────────────────────────── create
│  └───────────────────────────────────────── read
└──────────────────────────────────────────── Contact permissions
```

### Permission Letters

| Letter | Action | Notes |
|--------|--------|-------|
| `r` | **read** / view | View contacts or see transaction list |
| `c` | **create** | Add new contacts or transactions |
| `w` | **write** / update | Modify existing contacts or transactions |
| `d` | **delete** | Remove contacts or transactions |
| `x` | **close** | Transaction-specific: mark as settled/closed |

### Permission States

| State | Meaning | Example |
|-------|---------|---------|
| `:a` | **Allow** | `r:a` = read allowed |
| `:d` | **Deny** | `r:d` = read denied |
| `:-` | **Unset** | `r:-` = read permission not configured |

### Resource Sections

- **`C:`** = Contact permissions (required)
- **`T:`** = Transaction permissions (required)

---

## Examples

### Read-Only Access

User can view contacts and transactions, but cannot modify anything:

```
C: r:a c:- w:- d:-, T: r:a c:- w:- d:- x:-
```

### Full Access

User has complete control over contacts and transactions:

```
C: r:a c:a w:a d:a, T: r:a c:a w:a d:a x:a
```

### Edit-Only (No Read)

User can edit contacts without viewing them (write implies read via resolver):

```
C: r:- c:- w:a d:-, T: r:- c:- w:- d:- x:-
```

### Read + Deny Write

User can view contacts but explicitly prevented from editing:

```
C: r:a c:- w:d d:-, T: r:a c:- w:d d:- x:-
```

### Transaction Manager Role

User manages transactions (accountant) but contacts are read-only:

```
C: r:a c:- w:- d:-, T: r:a c:a w:a d:a x:a
```

---

## How This Maps to Actions

The format translates to allowed/denied action lists in the permission matrix:

### Allow Mapping

| Format | Action |
|--------|--------|
| `r:a` in C section | `contact:read` |
| `c:a` in C section | `contact:create` |
| `w:a` in C section | `contact:update` |
| `d:a` in C section | `contact:delete` |
| `r:a` in T section | `transaction:read` |
| `c:a` in T section | `transaction:create` |
| `w:a` in T section | `transaction:update` |
| `d:a` in T section | `transaction:delete` |
| `x:a` in T section | `transaction:close` |

### Deny Mapping

The same letters with `:d` create **denied_actions** instead of allowed ones.

---

## System Design: Permission Resolution

### The Implies() Pattern

Permission resolution uses an **implies()** relationship to prevent requiring explicit read permission for every action:

```rust
write:update    → implies read:read      (can't edit if you can't see)
create:create   → implies read:read      (can't add if you can't see)
delete:delete   → implies read:read      (can't delete if you can't see)
transaction:x   → implies contact:read   (can't close transaction if you can't see contact)
```

This means:
- Setting `w:a` without `r:a` is **valid** — the user gets implicit read access
- The format should show the **explicitly configured** permissions
- The resolver grants implied permissions at runtime

---

## Testing with This Format

### In Integration Tests

Use the CommandRunner format:

```rust
generator.execute_commands(&[
    "owner: permission set editors customers \"C: r:a c:- w:a d:-, T: r:a c:- w:- d:- x:-\"",
    "owner: wait 300",
    "member: sync",
    "member: assert contacts count >= 3",
]).expect("execute commands");
```

### In Direct API Tests

Convert format to JSON:

```rust
let entry = serde_json::json!({
    "user_group_id": group_id,
    "contact_group_id": contact_group_id,
    "allowed_actions": ["contact:read", "contact:update", "transaction:read"],
    "denied_actions": ["contact:create"]
});
```

---

## UI/Server Implementation Notes

### Current State

- **Backend**: Permission matrix stores raw action lists (`contact:read`, etc.)
- **Client Tests**: Use CommandRunner with rwx format (internally converts to action lists)
- **Server API**: Returns action names, not the compact format

### Future: UI Naming Changes (Pending)

Once implemented, the UI will display permissions using the rwx notation:
- Labels in permission dialogs: `Read`, `Create`, `Update`, `Delete` (or `r`, `c`, `w`, `d`)
- Color coding: 
  - **Green**: Allow
  - **Red**: Deny
  - **Grey/Dash**: Unset

---

## Benefits of This System

| Aspect | Benefit |
|--------|---------|
| **Readability** | See full permission matrix in one line |
| **Testability** | Easy to write permission scenarios |
| **Maintainability** | Self-documenting test code |
| **Debugging** | Quick visual inspection of permission combinations |
| **Validation** | Format parser catches typos in tests |

---

## Limitations & Constraints

1. **Order matters**: Spaces matter in format (one space between items)
2. **Both sections required**: Must always specify `C:` and `T:` sections
3. **No implicit unset**: Must explicitly use `:-` for unset permissions
4. **No grouping**: Cannot bundle permissions (e.g., no `"rw"` shorthand)

---

## Related Documents

- [[02-permission-events.md]] - How permission events are structured
- [[03-permission-sync-flow.md]] - How permissions sync between client and server
- [[04-permission-matrix-cache.md]] - How the client caches and applies permissions
