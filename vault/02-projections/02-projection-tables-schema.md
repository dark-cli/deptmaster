# Projection Tables Schema

**Main question this file answers:** Which tables are projections and what do they contain?

---

## Projection Tables

The system has two main projection tables:

1. **contacts_projection** — Current state of contacts
2. **transactions_projection** — Current state of transactions

Permission tables (wallet_users, user_groups, contact_groups) are not projections—they're operational tables. But they work the same way (events update them).

## contacts_projection

**Purpose:** Answer "who are all my contacts?"

```sql
CREATE TABLE contacts_projection (
  id UUID PRIMARY KEY,
  wallet_id UUID NOT NULL,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  notes TEXT,
  username TEXT,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

**Fields:**
- `id`: Unique contact ID
- `wallet_id`: Which wallet owns this contact
- `name`: Contact's name (required)
- `email`: Email address (optional)
- `phone`: Phone number (optional)
- `notes`: Free-form notes (optional)
- `username`: Username/handle (optional)
- `created_at`: When the contact was added
- `updated_at`: When last modified

**Example rows:**
```
id               | wallet_id            | name    | email              | phone
alice-123        | wallet-1             | Alice   | alice@example.com  | 555-1234
bob-456          | wallet-1             | Bob     | bob@example.com    | NULL
charlie-789      | wallet-2             | Charlie | charlie@test.com   | 555-5678
```

**Rebuilt by:** ContactCreated, ContactUpdated, ContactDeleted events

## transactions_projection

**Purpose:** Answer "how much do we owe each other?"

```sql
CREATE TABLE transactions_projection (
  id UUID PRIMARY KEY,
  wallet_id UUID NOT NULL,
  contact_id UUID NOT NULL,
  amount BIGINT NOT NULL,
  direction TEXT NOT NULL,
  description TEXT,
  date DATE NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id),
  FOREIGN KEY (contact_id) REFERENCES contacts_projection(id)
);
```

**Fields:**
- `id`: Unique transaction ID
- `wallet_id`: Which wallet
- `contact_id`: Which contact is involved
- `amount`: In cents (5000 = $50.00)
- `direction`: "lent" (they owe you) or "owed" (you owe them)
- `description`: What was this for? (optional)
- `date`: When did this transaction happen?
- `created_at`: When the transaction was recorded
- `updated_at`: When last modified

**Example rows:**
```
id            | contact_id | amount | direction | description      | date
tx-100        | alice-123  | 5000   | owed      | Dinner on Friday | 2024-06-01
tx-101        | bob-456    | 3000   | lent      | Concert tickets  | 2024-06-02
tx-102        | alice-123  | 2000   | lent      | Gas money        | 2024-06-03
```

**Rebuilt by:** TransactionCreated, TransactionUpdated, TransactionDeleted events

## Operational Tables (Permission-Related)

These aren't projections (don't have event-based rebuilds), but they work the same way (events update them):

### wallet_users

**Purpose:** Who has access to this wallet?

```sql
CREATE TABLE wallet_users (
  wallet_id UUID NOT NULL,
  user_id UUID NOT NULL,
  role TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL,
  
  PRIMARY KEY (wallet_id, user_id),
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

**Roles:**
- `owner` — Special role, has all permissions, can't be removed
- `admin` — Full access, can invite other users
- `viewer` — Read-only access

**Example rows:**
```
wallet_id      | user_id    | role
wallet-1       | user-1     | owner
wallet-1       | user-2     | admin
wallet-1       | user-3     | viewer
```

**Updated by:** WalletUserAdded, WalletUserRoleChanged events

### user_groups

**Purpose:** Groups of users (for managing permissions together).

```sql
CREATE TABLE user_groups (
  id UUID PRIMARY KEY,
  wallet_id UUID NOT NULL,
  name TEXT NOT NULL,
  system BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

**Fields:**
- `id`: Unique group ID
- `wallet_id`: Which wallet owns this group
- `name`: Group name
- `system`: true if auto-created by system (e.g., "All Users"), false if user-created

**Example rows:**
```
id        | name       | system
group-1   | Managers   | false
group-2   | All Users  | true
```

**Updated by:** UserGroupCreated, UserGroupDeleted events

### contact_groups

**Purpose:** Groups of contacts (for organizing contacts).

```sql
CREATE TABLE contact_groups (
  id UUID PRIMARY KEY,
  wallet_id UUID NOT NULL,
  name TEXT NOT NULL,
  system BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

Same structure as user_groups.

**Updated by:** ContactGroupCreated, ContactGroupUpdated, ContactGroupDeleted events

## Summary

| Table | Type | Purpose | Rebuilt By |
|---|---|---|---|
| `contacts_projection` | Projection | Current contacts | ContactCreated/Updated/Deleted |
| `transactions_projection` | Projection | Current transactions | TransactionCreated/Updated |
| `wallet_users` | Operational | Access control | WalletUserAdded/RoleChanged |
| `user_groups` | Operational | User groups | UserGroupCreated/Deleted |
| `contact_groups` | Operational | Contact groups | ContactGroupCreated/Updated/Deleted |

---

Next: [03-projection-rebuilds.md](03-projection-rebuilds.md) — Understand when and why projections rebuild
