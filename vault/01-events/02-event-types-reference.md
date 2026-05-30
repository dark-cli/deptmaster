# Event Types Reference

**Main question this file answers:** What are all the event types in the system?

---

## All Event Types

The system has three main aggregate types, each with their own event types.

## Contact Events

Events for creating, updating, and deleting contacts.

### ContactCreated
When a new contact is added to the wallet.

```json
{
  "aggregate_type": "contact",
  "event_type": "CREATED",
  "event_data": {
    "name": "Alice",
    "email": "alice@example.com",
    "phone": "555-1234",
    "username": "alice_smith",
    "notes": "College friend"
  }
}
```

**Fields:**
- `name` (required): Contact's name
- `email` (optional): Email address
- `phone` (optional): Phone number
- `username` (optional): Username or handle
- `notes` (optional): Free-form notes

### ContactUpdated
When a contact's details change.

```json
{
  "aggregate_type": "contact",
  "event_type": "UPDATED",
  "event_data": {
    "name": "Alice",
    "email": "alice.new@example.com",
    "phone": "555-5678",
    "username": "alice_v2",
    "notes": "Updated contact info"
  }
}
```

**Fields:** Same as ContactCreated (all fields that can be updated)

### ContactDeleted
When a contact is removed from the wallet.

```json
{
  "aggregate_type": "contact",
  "event_type": "DELETED"
}
```

**Fields:** None (just marks the contact as deleted)

## Transaction Events

Events for creating, updating, and deleting transactions (debts).

### TransactionCreated
When a new transaction (debt) is recorded.

```json
{
  "aggregate_type": "transaction",
  "event_type": "CREATED",
  "event_data": {
    "contact_id": "contact-123",
    "amount": 5000,
    "direction": "owed",
    "description": "Dinner on Friday",
    "date": "2024-06-01"
  }
}
```

**Fields:**
- `contact_id` (required): Which contact this transaction is with
- `amount` (required): Amount in cents (5000 = $50.00)
- `direction` (required): "lent" (they owe you) or "owed" (you owe them)
- `description` (optional): What was the transaction for?
- `date` (required): When did this transaction happen?

### TransactionUpdated
When transaction details change.

```json
{
  "aggregate_type": "transaction",
  "event_type": "UPDATED",
  "event_data": {
    "contact_id": "contact-123",
    "amount": 6000,
    "direction": "owed",
    "description": "Dinner and drinks",
    "date": "2024-06-01"
  }
}
```

**Fields:** Same as TransactionCreated

### TransactionDeleted
When a transaction is removed.

```json
{
  "aggregate_type": "transaction",
  "event_type": "DELETED"
}
```

**Fields:** None

## Permission Events

Events for managing who can access the wallet and what they can do.

### WalletUserAdded
When a user is granted access to the wallet.

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

**Fields:**
- `user_id` (required): Which user gets access
- `role` (required): "owner" (admin with special privileges), "admin" (can do everything), or "viewer" (read-only)

### WalletUserRoleChanged
When a user's access level changes.

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

**Fields:**
- `user_id` (required): Which user's role changed
- `old_role` (required): Their previous role
- `new_role` (required): Their new role

### UserGroupCreated
When a group of users is created.

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

**Fields:**
- `group_id` (required): Unique ID for the group
- `name` (required): Group name
- `system` (required): true if auto-created by system, false if user-created

### UserGroupDeleted
When a group is removed.

```json
{
  "aggregate_type": "permission",
  "event_type": "USER_GROUP_DELETED",
  "event_data": {
    "group_id": "group-789"
  }
}
```

**Fields:**
- `group_id` (required): Which group to delete

### ContactGroupCreated
When a group of contacts is created.

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

**Fields:**
- `group_id` (required): Unique ID
- `name` (required): Group name
- `system` (required): true if auto-created, false if user-created

### ContactGroupUpdated
When a contact group's details change.

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

**Fields:**
- `group_id` (required): Which group
- `name` (required): New name

### ContactGroupMemberAdded
When a contact is added to a group.

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

**Fields:**
- `group_id` (required): Which group
- `contact_id` (required): Which contact to add

### ContactGroupMemberRemoved
When a contact is removed from a group.

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

**Fields:**
- `group_id` (required): Which group
- `contact_id` (required): Which contact to remove

## Special Event: UNDO

Marks another event as "never happened."

```json
{
  "aggregate_type": "contact",  // Can be any aggregate type
  "event_type": "UNDO",
  "event_data": {
    "undone_event_id": 12345
  }
}
```

**What it means:** "Event 12345 is undone. When rebuilding, skip it."

**Example:**
```
Event 100: TransactionCreated { amount: 50 }  ← Original transaction
Event 101: UNDO { undone_event_id: 100 }      ← Undo the transaction

Result: As if event 100 never happened
```

**Important:** UNDO events trigger a **full projection rebuild** because undoing one past event means all future computations might be wrong.

## Summary Table

| Aggregate | Event Types |
|---|---|
| **Contact** | CREATED, UPDATED, DELETED |
| **Transaction** | CREATED, UPDATED, DELETED |
| **Permission** | WALLET_USER_ADDED, WALLET_USER_ROLE_CHANGED, USER_GROUP_CREATED, USER_GROUP_DELETED, CONTACT_GROUP_CREATED, CONTACT_GROUP_UPDATED, CONTACT_GROUP_MEMBER_ADDED, CONTACT_GROUP_MEMBER_REMOVED |
| **Any** | UNDO (can undo any event from any aggregate) |

---

Next: [03-type-driven-handlers.md](03-type-driven-handlers.md) — Understand how handlers process these events
