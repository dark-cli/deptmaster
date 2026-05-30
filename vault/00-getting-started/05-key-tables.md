# Key Tables

**Main question this file answers:** What database tables exist and what do they store?

---

## Overview

The debt tracker uses these main tables:

| Table | Purpose | Type |
|---|---|---|
| `events` | Complete history of all events | Immutable log |
| `contacts_projection` | Current state of all contacts | Projection |
| `transactions_projection` | Current state of all transactions | Projection |
| `wallet_users` | Permission matrix (who can see what) | Operational |
| `user_groups` | Groups of users (for permissions) | Operational |
| `contact_groups` | Groups of contacts | Operational |
| `snapshots` | Checkpoints for fast rebuilds | Cache |

## Events Table

**Purpose:** Complete, immutable history of everything that happened.

```sql
CREATE TABLE events (
  id BIGSERIAL PRIMARY KEY,
  wallet_id UUID NOT NULL,
  aggregate_type TEXT NOT NULL,      -- "contact", "transaction", "permission"
  event_type TEXT NOT NULL,          -- "CREATED", "UPDATED", "DELETED", "UNDO"
  aggregate_id UUID NOT NULL,        -- ID of what changed
  event_data JSONB NOT NULL,         -- All details of the event
  version INT NOT NULL,              -- For idempotency
  created_at TIMESTAMP NOT NULL,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

**Key properties:**
- Never deleted (immutable)
- Always appended to (new events arrive in order)
- Complete history (you can replay any wallet from event 1)
- Stores JSON (flexible for different event types)

**Examples of event_data:**
```json
// ContactCreated
{"name": "Alice", "email": "alice@example.com", "phone": "555-1234"}

// TransactionCreated
{"contact_id": "bob-123", "amount": 5000, "direction": "owed"}

// WalletUserAdded
{"user_id": "user-456", "role": "admin"}

// UNDO
{"undone_event_id": 12345}
```

## Projection Tables

### contacts_projection
**Purpose:** Current state of all contacts (rebuilt from ContactCreated/ContactUpdated/ContactDeleted events).

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

**When to use it:** Answer questions like "who are all the contacts in my wallet?" or "what is Alice's email?"

### transactions_projection
**Purpose:** Current state of all transactions (rebuilt from TransactionCreated/TransactionUpdated events).

```sql
CREATE TABLE transactions_projection (
  id UUID PRIMARY KEY,
  wallet_id UUID NOT NULL,
  contact_id UUID NOT NULL,        -- Which contact
  amount BIGINT NOT NULL,           -- In cents
  direction TEXT NOT NULL,          -- "lent" or "owed"
  description TEXT,
  date DATE NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id),
  FOREIGN KEY (contact_id) REFERENCES contacts_projection(id)
);
```

**When to use it:** Answer questions like "how much does Alice owe Bob?" or "what transactions are unsettled?"

## Operational Tables

These are updated by permission events, not projections.

### wallet_users
**Purpose:** Who has access to this wallet and what can they do?

```sql
CREATE TABLE wallet_users (
  wallet_id UUID NOT NULL,
  user_id UUID NOT NULL,
  role TEXT NOT NULL,               -- "owner", "admin", "viewer"
  created_at TIMESTAMP NOT NULL,
  
  PRIMARY KEY (wallet_id, user_id),
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

**Key insight:** Updated by `WalletUserAdded` and `WalletUserRoleChanged` events.

### user_groups
**Purpose:** Groups of users (for managing permissions together).

```sql
CREATE TABLE user_groups (
  id UUID PRIMARY KEY,
  wallet_id UUID NOT NULL,
  name TEXT NOT NULL,
  system BOOLEAN DEFAULT FALSE,     -- TRUE for auto-created groups
  created_at TIMESTAMP NOT NULL,
  
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

**Key insight:** Updated by `UserGroupCreated` and `UserGroupDeleted` events.

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

**Key insight:** Updated by contact group events.

## Snapshots Table

**Purpose:** Checkpoints to speed up rebuilds without reprocessing all events.

```sql
CREATE TABLE snapshots (
  wallet_id UUID NOT NULL,
  aggregate_type TEXT NOT NULL,    -- "contact", "transaction", "permission"
  last_event_id BIGINT NOT NULL,   -- "snapshot taken after event N"
  state JSONB NOT NULL,            -- Entire projection state at this point
  created_at TIMESTAMP NOT NULL,
  
  PRIMARY KEY (wallet_id, aggregate_type),
  FOREIGN KEY (wallet_id) REFERENCES wallets(id)
);
```

**Example snapshot:**
```json
{
  "wallet_id": "wallet-123",
  "aggregate_type": "contact",
  "last_event_id": 50000,
  "state": {
    "contacts_projection": [
      {"id": "alice-1", "name": "Alice", "email": "alice@example.com"},
      {"id": "bob-2", "name": "Bob", "email": "bob@example.com"}
    ]
  },
  "created_at": "2024-06-01T10:00:00Z"
}
```

**Key insight:** When rebuilding a wallet:
1. Find latest snapshot: "state at event 50,000"
2. Restore projection tables from it
3. Only process events 50,001 onward
4. Much faster and uses less memory

## Data Flow Summary

```
API receives event
      ↓
INSERT into events table
      ↓
Apply event using type-driven handler
      ↓
UPDATE projection tables (contacts_projection, transactions_projection)
    OR
UPDATE operational tables (wallet_users, user_groups)
      ↓
Every 1000 events:
   CREATE snapshot (save current state)
      ↓
Return current state to user
```

## Reading Order

1. You've read **Getting Started** — you understand what tables exist and why
2. Next read **Chapter 01: Events** — understand event types and how they're defined
3. Then read **Chapter 02: Projections** — understand how projections are built
4. Then read **Chapter 03: Snapshots** — understand optimization
5. Then read **Chapter 04: Permissions and UNDO** — understand special cases

---

Next: [../01-events/01-what-are-events.md](../01-events/01-what-are-events.md) — Understand how events work in detail
