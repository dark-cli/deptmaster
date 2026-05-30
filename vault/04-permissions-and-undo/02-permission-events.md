# Permission Events

**Main question this file answers:** How does the permission system work?

---

## What Are Permission Events?

Permission events are events that manage **who has access to what**.

Instead of having a separate "permissions_projection" table, permission events update **operational tables**:
- `wallet_users` — Who has access to the wallet
- `user_groups` — Groups of users
- `contact_groups` — Groups of contacts

## Permission Event Types

Permission events all have `aggregate_type = "permission"`.

### WalletUserAdded
Grant a user access to the wallet.

```json
{
  "aggregate_type": "permission",
  "event_type": "WALLET_USER_ADDED",
  "event_data": {
    "user_id": "user-456",
    "role": "admin"
  }
}
```

**Result:** INSERT into wallet_users

```sql
INSERT INTO wallet_users (wallet_id, user_id, role) VALUES (..., 'user-456', 'admin')
```

### WalletUserRoleChanged
Change a user's role.

```json
{
  "aggregate_type": "permission",
  "event_type": "WALLET_USER_ROLE_CHANGED",
  "event_data": {
    "user_id": "user-456",
    "old_role": "admin",
    "new_role": "viewer"
  }
}
```

**Result:** UPDATE wallet_users

```sql
UPDATE wallet_users SET role = 'viewer' WHERE user_id = 'user-456'
```

### UserGroupCreated
Create a group of users.

```json
{
  "aggregate_type": "permission",
  "event_type": "USER_GROUP_CREATED",
  "event_data": {
    "group_id": "group-789",
    "name": "Managers",
    "system": false
  }
}
```

**Result:** INSERT into user_groups

### UserGroupDeleted
Delete a user group.

```json
{
  "aggregate_type": "permission",
  "event_type": "USER_GROUP_DELETED",
  "event_data": {
    "group_id": "group-789"
  }
}
```

**Result:** DELETE from user_groups

### ContactGroupCreated
Create a group of contacts.

```json
{
  "aggregate_type": "permission",
  "event_type": "CONTACT_GROUP_CREATED",
  "event_data": {
    "group_id": "cgroup-111",
    "name": "Close Friends",
    "system": false
  }
}
```

**Result:** INSERT into contact_groups

### ContactGroupUpdated
Update a contact group's name.

```json
{
  "aggregate_type": "permission",
  "event_type": "CONTACT_GROUP_UPDATED",
  "event_data": {
    "group_id": "cgroup-111",
    "name": "Best Friends"
  }
}
```

**Result:** UPDATE contact_groups

### ContactGroupMemberAdded
Add a contact to a group.

```json
{
  "aggregate_type": "permission",
  "event_type": "CONTACT_GROUP_MEMBER_ADDED",
  "event_data": {
    "group_id": "cgroup-111",
    "contact_id": "contact-123"
  }
}
```

**Result:** INSERT into contact_group_members

### ContactGroupMemberRemoved
Remove a contact from a group.

```json
{
  "aggregate_type": "permission",
  "event_type": "CONTACT_GROUP_MEMBER_REMOVED",
  "event_data": {
    "group_id": "cgroup-111",
    "contact_id": "contact-123"
  }
}
```

**Result:** DELETE from contact_group_members

## Permission Events vs. Projections

Permission events **don't have their own projection table** because they directly update operational tables.

| Event Type | Table It Updates |
|---|---|
| ContactCreated, Updated, Deleted | contacts_projection |
| TransactionCreated, Updated | transactions_projection |
| WalletUserAdded, RoleChanged | wallet_users |
| UserGroupCreated, Deleted | user_groups |
| ContactGroupCreated, Updated | contact_groups |
| ContactGroupMemberAdded, Removed | contact_group_members |

But they **work the same way**:
- Event arrives → Handler processes it → Table updated

## Permission Event Roles

When granting wallet access, you specify a role:

### Owner
- Special role (only one owner per wallet)
- Can do everything (full access)
- Can't be removed (only owner can remove other users)
- Typically the wallet creator

### Admin
- Can do everything (read, write, invite others)
- Can be removed/downgraded

### Viewer
- Read-only access
- Can't create or modify anything
- Can only view existing data

## Permission Event Rebuilds

When permission events are rebuilt (due to UNDO or recovery):

```rust
AggregateType::Permission => {
    // Clear user memberships
    sqlx::query("DELETE FROM user_group_members WHERE wallet_id = $1")
        .bind(wallet_id)
        .execute(pool)
        .await?;
    
    // Clear user groups
    sqlx::query("DELETE FROM user_groups WHERE wallet_id = $1 AND system = false")
        .bind(wallet_id)
        .execute(pool)
        .await?;
    
    // Clear contact groups and members
    sqlx::query("DELETE FROM contact_group_members WHERE group_id IN (
        SELECT id FROM contact_groups WHERE wallet_id = $1 AND system = false
    )")
    .bind(wallet_id)
    .execute(pool)
    .await?;
    
    sqlx::query("DELETE FROM contact_groups WHERE wallet_id = $1 AND system = false")
        .bind(wallet_id)
        .execute(pool)
        .await?;
    
    // Clear wallet users (keep owner)
    sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND role != 'owner'")
        .bind(wallet_id)
        .execute(pool)
        .await?;
}
```

**Why keep owners?** The owner is special and shouldn't be removable by events. This preserves the owner role across rebuilds.

## System vs. User-Created Groups

Groups can be marked as `system = true` (auto-created) or `system = false` (user-created).

During rebuilds:
- System groups: preserved (don't delete)
- User-created groups: deleted and rebuilt from events

```rust
// Clear user-created groups only
sqlx::query("DELETE FROM user_groups WHERE wallet_id = $1 AND system = false")
    .bind(wallet_id)
    .execute(pool)
    .await?;

// Reprocess events to rebuild them
```

This prevents losing system-generated groups during rebuilds.

## Permission Consistency

**Question:** Are permission tables kept in sync with permission events?

**Answer:** Yes, like projections.

During normal operation:
- Permission event arrives
- Handler updates wallet_users/user_groups/contact_groups immediately
- They stay in sync

During rebuild:
- Clear permission tables (except owner and system groups)
- Reprocess permission events
- Tables are rebuilt from scratch

## Permission Event Snapshot

Permission snapshots work like contact/transaction snapshots:

```json
{
  "wallet_id": "wallet-123",
  "aggregate_type": "permission",
  "last_event_id": 50000,
  "state": {
    "wallet_users": [...],
    "user_groups": [...],
    "contact_groups": [...]
  }
}
```

Stored in the same snapshots table, updated every 1,000 events.

## Examples: Permission Event Flow

### Scenario 1: Adding a User to Wallet

```
POST /sync with WalletUserAdded { user_id: alice, role: admin }
         ↓
INSERT into events
         ↓
Handler processes event
         ↓
INSERT into wallet_users (wallet_id, user_id, role) 
VALUES (..., alice, admin)
         ↓
Result: Alice can now access the wallet with admin role
```

### Scenario 2: Creating a Contact Group

```
POST /sync with ContactGroupCreated { group_id: group-1, name: "Friends" }
         ↓
INSERT into events
         ↓
Handler processes event
         ↓
INSERT into contact_groups (id, name, system)
VALUES (group-1, Friends, false)
         ↓
Result: Contact group exists, ready to add members
```

### Scenario 3: Removing and Reinviting User

```
Events:
1. WalletUserAdded { user_id: alice, role: admin }  (Event 100)
2. UNDO { undone_event_id: 100 }  (Event 101)
3. WalletUserAdded { user_id: alice, role: viewer }  (Event 102)
         ↓
Full rebuild triggered (UNDO present)
         ↓
Process events:
  Event 100: Skip (undone)
  Event 101: Skip (it's the UNDO)
  Event 102: INSERT alice as viewer
         ↓
Result: Alice is reinvited with viewer role (downgraded from admin)
```

---

Next: [03-permission-sync-flow.md](03-permission-sync-flow.md) — Understand how permission events flow through the system
