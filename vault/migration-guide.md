---
tags:
  - database
  - migrations
  - architecture
---

# Database Migration Guide

**What**: Database schema evolution (version control for your database)  
**Why**: Everyone has the same schema. Deploying is predictable. Rolling back is safe.

---

## Current Migrations (001-021): Organized by Phase

### PHASE 1: Core Schema Foundation

#### 001_initial_schema.sql
**Purpose**: Create the foundational tables for event sourcing + projections  
**Creates**:
- `events` — Immutable append-only log of all changes
- `users_projection` — User state (read model)
- `contacts_projection` — Contact state (read model)
- `transactions_projection` — Transaction state (read model)

**Schema Pattern**:
```
events table (write-only):
  - event_id (UUID, unique)
  - aggregate_type ("contact", "transaction", "user")
  - event_type ("CREATED", "UPDATED", "DELETED")
  - event_data (JSONB — the actual data)
  - created_at (timestamp)

projections (read-optimized):
  - id (UUID)
  - name, email, phone, etc. (denormalized columns)
  - last_event_id (track state)
```

**Key Insight**: Separates writes (immutable events) from reads (queryable projections)

---

#### 002_remove_transaction_settled.sql
**Purpose**: Fix initial schema design mistake  
**Removes**:
- `is_settled` column from transactions_projection
- `settled_at` column from transactions_projection

**Why**: Realized we track net balance per contact, not settlement status of individual transactions  
**Type**: Schema correction (not a bug, just a better design)

---

### PHASE 2: Sync Infrastructure (CRITICAL)

#### 007_add_idempotency_and_versions.sql
**Purpose**: Enable duplicate prevention + conflict detection  
**Adds**:
```sql
ALTER TABLE events ADD COLUMN idempotency_key VARCHAR(255) UNIQUE;
-- Prevents: POST same event twice (network retry) → duplicate insertion
-- Uses: Client sends same idempotency_key for retries

ALTER TABLE contacts_projection ADD COLUMN version INTEGER DEFAULT 1;
ALTER TABLE transactions_projection ADD COLUMN version INTEGER DEFAULT 1;
-- Detects: Client A and B both update contact, creating conflict
-- Uses: Version = generation number, increment on update
```

**Critical Because**:
- Without idempotency_key: network retry = duplicate transaction
- Without version: concurrent updates = data loss

**Example**:
```
Client A:    POST contact with id=abc, idempotency_key=xyz
             ↓ Network fails
             Retries with same xyz
             Server: "xyz already applied, skip"
             ✓ No duplicate

Without:
Client A:    POST contact
             ↓ Network fails
             Retries (new idempotency_key or none)
             Server: "New request, creates duplicate contact"
             ✗ Data corruption
```

---

#### 008_add_projection_snapshots.sql
**Purpose**: Performance optimization for state rebuilding  
**Creates**:
```sql
CREATE TABLE projection_snapshots (
    snapshot_index BIGINT,        -- Sequence (0, 1, 2...)
    last_event_id BIGINT,         -- Up to which event
    contacts_snapshot JSONB,      -- Full contacts state at this point
    transactions_snapshot JSONB,  -- Full transactions state at this point
);
```

**Why**:
- Rebuilding from 100K events = slow
- Instead: load snapshot at event 80K (contains 80K events worth of state)
- Apply only 20K new events on top
- Result: O(new_events) instead of O(all_events)

**Example**:
```
Without snapshots:
  Rebuild: Load all 100K events → process → rebuild state
  Time: 50 seconds

With snapshots:
  Rebuild: Load snapshot at 80K (pre-computed state) → process 20K new events
  Time: 2 seconds
```

---

### PHASE 3: Features

#### 003_add_due_date.sql
**Purpose**: Add due date tracking to transactions  
**Adds**:
```sql
ALTER TABLE transactions_projection ADD COLUMN due_date DATE;
CREATE INDEX idx_transactions_due_date ON transactions_projection(due_date);
```

**Use**: "Show me transactions due by tomorrow"

---

#### 004_user_settings.sql
**Purpose**: Store user preferences on server  
**Creates**:
```sql
CREATE TABLE user_settings (
    user_id UUID,
    setting_key VARCHAR(100),      -- "theme", "timezone", "language"
    setting_value TEXT,            -- "dark", "UTC", "en"
);
```

**Use**: Settings sync between devices (web app shows dark theme, mobile shows dark theme)

---

#### 005_create_default_user.sql
**Purpose**: Bootstrap with initial admin user  
**Action**:
```sql
IF no users exist THEN
    INSERT INTO users_projection (
        email = 'admin@debitum.local',
        password_hash = '<bcrypt hash>',
    )
END
```

**Use**: First deployment can log in without manual DB manipulation

---

#### 006_add_username_to_contacts.sql
**Purpose**: Add username field to contacts (for messaging apps, etc.)  
**Adds**:
```sql
ALTER TABLE contacts_projection ADD COLUMN username VARCHAR(100);
CREATE INDEX idx_contacts_username ON contacts_projection(username);
```

**Use**: "Find contact by username" searches

---

### PHASE 4: Security & Audit

#### 009_add_login_logs.sql
**Purpose**: Track all login attempts (successful and failed)  
**Creates**:
```sql
CREATE TABLE login_logs (
    user_id UUID,
    login_at TIMESTAMP,
    ip_address VARCHAR(45),        -- IPv4 or IPv6
    success BOOLEAN,
    failure_reason TEXT,           -- "invalid_password", "user_not_found"
);
```

**Use**:
- Detect brute force attacks: "50 failed logins from same IP in 5 minutes"
- Audit: "When did user X last log in?"
- Security: "Where are my users logging in from?"

---

#### 010_add_admin_users.sql
**Purpose**: Separate admin authentication from regular users  
**Creates**:
```sql
CREATE TABLE admin_users (
    id UUID PRIMARY KEY,
    username VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255),
    is_active BOOLEAN,
);
```

**Why**: 
- Regular users: managed via events (sync-able, versioned)
- Admin users: separate table (no versioning, direct manipulation)
- Prevents: Admin user conflicts when two admins edit something

---

### PHASE 5: Multi-Wallet System

#### 011_create_wallets.sql
**Purpose**: Create wallet concept (top-level data container)  
**Creates**:
```sql
CREATE TABLE wallets (
    id UUID PRIMARY KEY,
    name VARCHAR(255),
    created_at TIMESTAMP,
);
```

**Why**: Each wallet is isolated. User A's data ≠ User B's data.

---

#### 012_add_wallet_id_to_tables.sql
**Purpose**: Add wallet_id to all data tables for isolation  
**Alters**:
```sql
ALTER TABLE events ADD COLUMN wallet_id UUID;
ALTER TABLE contacts_projection ADD COLUMN wallet_id UUID;
ALTER TABLE transactions_projection ADD COLUMN wallet_id UUID;
ALTER TABLE user_settings ADD COLUMN wallet_id UUID;
```

**Result**: All data now scoped to wallet
```sql
-- Before: SELECT * FROM contacts → All contacts globally
-- After:  SELECT * FROM contacts WHERE wallet_id = ? → Only this wallet's contacts
```

---

#### 013_projection_snapshots_wallet_unique.sql
**Purpose**: Update snapshots to be wallet-scoped  
**Alters**:
```sql
ALTER TABLE projection_snapshots ADD COLUMN wallet_id UUID;
CREATE UNIQUE INDEX idx_snapshots_wallet ON projection_snapshots(wallet_id, snapshot_index);
```

**Result**: Each wallet has its own snapshots (isolated performance)

---

### PHASE 6: Advanced Permissions System

#### 014_advanced_permissions.sql
**Purpose**: Create permission infrastructure  
**Creates**:
```sql
CREATE TABLE user_groups (
    id UUID,
    wallet_id UUID,
    name VARCHAR(255),             -- "Editors", "VIP_Managers"
);

CREATE TABLE contact_groups (
    id UUID,
    wallet_id UUID,
    name VARCHAR(255),             -- "VIP", "Family"
);

CREATE TABLE group_permission_matrix (
    user_group_id UUID,
    contact_group_id UUID,
    allowed_actions TEXT[],        -- ["contact:create", "contact:read"]
);
```

**Purpose**: Define who (user_group) can do what (actions) on which data (contact_group)

---

#### 017_fix_missing_permissions.sql
**Purpose**: Ensure default groups exist  
**Creates**: all_users, all_contacts groups if missing

---

#### 018_restrict_default_permissions.sql
**Purpose**: Set restrictive defaults (deny all, grant specific)  
**Updates**: permission_matrix to deny all by default

---

#### 019_update_invite_codes.sql
**Purpose**: Add invite codes for wallet sharing  
**Adds**: invite_code column to wallets

---

#### 020_permission_matrix_allow_deny.sql
**Purpose**: Support both allow and deny permissions  
**Alters**:
```sql
ALTER TABLE group_permission_matrix 
    ADD COLUMN action VARCHAR(50),      -- "contact:create"
    ADD COLUMN effect VARCHAR(10),      -- "allow" or "deny"
```

---

#### 021_add_contact_edit_action.sql
**Purpose**: Add "contact:edit" as separate permission  
**Updates**: permission_actions to include contact:edit (alias for contact:update)

---

## Schema Progression

### After 001-002 (Initial)
```
events (write log)
users_projection, contacts_projection, transactions_projection (read models)
```

### After 007-008 (Sync Infrastructure)
```
+ idempotency_key on events
+ version on projections
+ projection_snapshots table
```

### After 003-006 (Features)
```
+ due_date on transactions
+ user_settings table
+ username on contacts
```

### After 009-010 (Security)
```
+ login_logs table
+ admin_users table (separate)
```

### After 011-013 (Multi-Wallet)
```
+ wallets table
+ wallet_id on ALL tables
+ wallet-scoped snapshots
```

### After 014-021 (Permissions)
```
+ user_groups, contact_groups tables
+ group_permission_matrix table
+ permission_actions table
```

---

## How to Create New Migrations

### Migration Header (REQUIRED)

Every new migration must have this comment block:

```sql
-- MIGRATION: 022_add_feature_x.sql
-- PHASE: Features (or: Infrastructure, Security, Optimization)
-- CATEGORY: User-facing feature
-- PURPOSE: [Why does this migration exist? What problem does it solve?]
-- IMPACT: [What tables/queries does this affect?]
-- ROLLBACK: [How to safely revert if needed]
-- DEPENDS: [What migrations must run first?]

-- Example: 
-- PHASE: Optimization
-- PURPOSE: Speed up contact searches by 10x
-- IMPACT: New index on contacts_projection(name), queries with .where(name=X) now use index
-- ROLLBACK: DROP INDEX idx_contacts_name

ALTER TABLE contacts_projection ADD COLUMN ...
```

### Migration Phases (Use These)

When creating a migration, choose ONE phase:

| Phase | When | Examples |
|-------|------|----------|
| **Infrastructure** | Core sync/data needs | Idempotency, snapshots, versioning |
| **Features** | User-facing functionality | New columns, new tables, new indexes |
| **Security** | Audit/protection | Login logs, rate limiting, encryption |
| **Optimization** | Performance improvements | Indexes, partitions, caching |
| **Refactoring** | Cleanup/reorganization | Rename columns, normalize data |

### Migration Naming

```
Format: NNN_what_it_does.sql

Good:
  022_add_username_field.sql
  023_create_login_audit_table.sql
  024_add_wallet_indexes.sql

Bad:
  022_fix.sql                    (too vague)
  023_schema_changes.sql         (too vague)
  024_update.sql                 (what was updated?)
```

### Testing Migrations

Before committing:

```bash
# 1. Run migrations on fresh database
sqlx migrate run

# 2. Verify schema matches expected
\d+ table_name

# 3. Check indexes were created
SELECT * FROM pg_indexes WHERE tablename = 'table_name';

# 4. Test rollback (if reversible)
sqlx migrate revert
sqlx migrate run  # Should match before
```

---

## Why This Matters

**Bad migration strategy**:
- Migrations numbered randomly: 001, 003, 002, 005, 004
- No comments explaining intent
- Impossible to understand why something exists
- Hard to debug when something breaks

**Good migration strategy** (this guide):
- Grouped by phase
- Each has clear purpose + impact statement
- History tells story of how system evolved
- Easy to find related changes

Reading your migrations is reading your database history. Make it readable.

---

## Related
- [[architecture.md]] - Why event sourcing + projections
- [[sync-refactoring-plan.md]] - How migrations enable safe refactoring
