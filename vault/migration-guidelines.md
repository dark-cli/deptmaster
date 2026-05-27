---
tags:
  - database
  - migrations
  - guidelines
---

# Database Migration Guidelines

**How to create migrations that are clear, safe, and maintainable.**

---

## Before You Create a Migration

Ask yourself:

1. **Is this a breaking change?**
   - Removing a column → breaking
   - Adding NOT NULL without default → breaking
   - Renaming column → breaking
   - Adding nullable column → safe
   - Adding with default → safe

2. **Will this lock the database?**
   - `DROP COLUMN` on large tables → might lock for minutes
   - `ALTER TABLE ... ADD CONSTRAINT` → locks
   - Adding index on large table → can lock
   - Solution: Use CONCURRENTLY for indexes, backfill nullable columns first

3. **Can this be reversed?**
   - `DROP TABLE` → only if you have backup
   - `ALTER ... DROP COLUMN` → only if you're sure
   - Adding column → safe, reversible
   - Solution: Always think "what if we need to revert?"

---

## Migration Template

```sql
-- ============================================================================
-- MIGRATION: NNN_descriptive_name.sql
-- PHASE: [Infrastructure|Features|Security|Optimization|Refactoring]
-- CATEGORY: [More specific: Sync, Permissions, Audit, etc.]
-- ============================================================================

-- PURPOSE:
-- Why does this migration exist? What problem does it solve?
-- Be specific. Don't say "improve performance", say "reduce contact search from 500ms to 50ms"

-- IMPACT:
-- What tables/columns/indexes are affected?
-- What queries will be affected?
-- Will existing code need changes?

-- ROLLBACK:
-- How would you safely revert this?
-- Are there data considerations? 

-- DEPENDS:
-- What migrations must run before this one?
-- Example: "Depends on 015_create_wallets.sql"

-- BACKWARDS COMPATIBILITY:
-- Will existing code work with this schema?
-- If not, is there a backfill strategy?

-- ============================================================================
-- IMPLEMENTATION
-- ============================================================================

-- Example: Adding a new table

CREATE TABLE IF NOT EXISTS wallet_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    invite_code VARCHAR(32) UNIQUE NOT NULL,
    created_by UUID NOT NULL REFERENCES users_projection(id),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL DEFAULT NOW() + INTERVAL '7 days',
    accepted_at TIMESTAMP,
    accepted_by UUID REFERENCES users_projection(id),
    revoked_at TIMESTAMP
);

-- Index for fast lookups
CREATE INDEX idx_wallet_invites_code ON wallet_invites(invite_code);
CREATE INDEX idx_wallet_invites_wallet ON wallet_invites(wallet_id) WHERE accepted_at IS NULL;
CREATE INDEX idx_wallet_invites_expires ON wallet_invites(expires_at) WHERE accepted_at IS NULL;

-- Document columns
COMMENT ON TABLE wallet_invites IS 'Temporary invite codes for sharing wallet access';
COMMENT ON COLUMN wallet_invites.invite_code IS 'Random 32-char code, shareable with others';
COMMENT ON COLUMN wallet_invites.created_by IS 'Which user created this invite';
COMMENT ON COLUMN wallet_invites.accepted_at IS 'When someone accepted this invite';
COMMENT ON COLUMN wallet_invites.accepted_by IS 'Which user accepted this invite';
```

---

## Checklist: Before Committing

- [ ] Has clear header comment (purpose, impact, rollback)
- [ ] Grouped by phase (Infrastructure, Features, Security, Optimization, Refactoring)
- [ ] Tested on fresh database
- [ ] Tested rollback (if reversible)
- [ ] Indexes created for new foreign keys
- [ ] Indexes created for columns used in WHERE clauses
- [ ] Comments added to columns (COMMENT ON COLUMN)
- [ ] No breaking changes (or documented workaround)
- [ ] Backwards compatible with existing code
- [ ] Performance impact considered (locking, table size, etc.)

---

## Common Patterns

### Adding a New Table

```sql
-- PHASE: Features
-- PURPOSE: Track user device registrations for push notifications

CREATE TABLE user_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    device_type VARCHAR(50) NOT NULL,      -- "ios", "android", "web"
    device_token VARCHAR(255) NOT NULL,    -- FCM token or APNs token
    registered_at TIMESTAMP NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_user_devices_user ON user_devices(user_id);
CREATE INDEX idx_user_devices_active ON user_devices(user_id) WHERE is_active = true;

COMMENT ON TABLE user_devices IS 'Device tokens for push notifications';
```

### Adding a Column (Safe)

```sql
-- PHASE: Features
-- PURPOSE: Track user timezone for scheduling

ALTER TABLE user_settings ADD COLUMN timezone VARCHAR(50) DEFAULT 'UTC';
CREATE INDEX idx_user_settings_timezone ON user_settings(timezone) 
    WHERE timezone != 'UTC';

COMMENT ON COLUMN user_settings.timezone IS 'IANA timezone string (e.g., "America/New_York")';
```

### Adding a Column (Requires Backfill)

```sql
-- PHASE: Optimization
-- PURPOSE: Denormalize contact_count for faster queries

-- Step 1: Add nullable column
ALTER TABLE wallets ADD COLUMN contact_count INTEGER;

-- Step 2: Backfill existing data
UPDATE wallets SET contact_count = (
    SELECT COUNT(*) FROM contacts_projection 
    WHERE wallet_id = wallets.id AND is_deleted = false
);

-- Step 3: Add NOT NULL constraint
ALTER TABLE wallets ALTER COLUMN contact_count SET NOT NULL;

-- Step 4: Add index if needed
CREATE INDEX idx_wallets_contact_count ON wallets(contact_count) 
    WHERE contact_count > 0;

COMMENT ON COLUMN wallets.contact_count IS 'Denormalized count of active contacts for fast queries. Updated via trigger.';
```

### Creating an Index on Large Table

```sql
-- PHASE: Optimization
-- PURPOSE: Speed up contact name searches by 50x

-- Use CONCURRENTLY to avoid locking (PostgreSQL 9.2+)
CREATE INDEX CONCURRENTLY idx_contacts_name_gin 
    ON contacts_projection USING GIN (name gin_trgm_ops);

-- If using like '%...%', create trigram index:
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

### Removing Unused Column (Safe)

```sql
-- PHASE: Refactoring
-- PURPOSE: Remove deprecated field that's no longer used

ALTER TABLE contacts_projection DROP COLUMN legacy_field CASCADE;
```

### Renaming Column (Breaking Change - Handle Carefully)

```sql
-- PHASE: Refactoring
-- PURPOSE: Standardize column naming convention

-- Step 1: Create new column
ALTER TABLE contacts_projection ADD COLUMN full_name VARCHAR(255);

-- Step 2: Backfill
UPDATE contacts_projection SET full_name = name WHERE name IS NOT NULL;

-- Step 3: Update code to use full_name instead of name

-- Step 4: Drop old column (in next release, after code is updated)
ALTER TABLE contacts_projection DROP COLUMN name;
```

---

## Anti-Patterns (Don't Do These)

### ❌ Vague Comments
```sql
-- Bad
ALTER TABLE contacts ADD COLUMN x VARCHAR(100);

-- Good
-- PHASE: Features
-- PURPOSE: Track contact's company affiliation for filtering
ALTER TABLE contacts ADD COLUMN company_name VARCHAR(100);
```

### ❌ Multiple Unrelated Changes
```sql
-- Bad: Mixing multiple unrelated concerns
ALTER TABLE contacts ADD COLUMN company VARCHAR(100);
ALTER TABLE transactions ADD COLUMN category VARCHAR(50);
CREATE TABLE new_audit_log (...);
-- Hard to review, hard to revert one specific change

-- Good: One migration, one purpose
-- Migration 025: Add company to contacts
-- Migration 026: Add category to transactions
-- Migration 027: Create audit log table
```

### ❌ No Backward Compatibility
```sql
-- Bad: Breaks existing code immediately
ALTER TABLE contacts_projection DROP COLUMN email;  -- App code might reference this

-- Good: Add deprecation period
ALTER TABLE contacts_projection ADD COLUMN email_alternative VARCHAR(255);
-- Give code time to migrate to new column
-- Drop in migration N+5 after app has deployed
```

### ❌ Locking Queries on Large Tables
```sql
-- Bad: Locks table for potentially minutes
ALTER TABLE events ADD COLUMN status VARCHAR(50) NOT NULL DEFAULT 'pending';

-- Better: Add nullable first, then update separately
ALTER TABLE events ADD COLUMN status VARCHAR(50);
-- Backfill in smaller batches to avoid locking
UPDATE events SET status = 'pending' WHERE status IS NULL LIMIT 10000;
-- Repeat until done, then add NOT NULL
ALTER TABLE events ALTER COLUMN status SET NOT NULL;
```

---

## Phase Selection

Choose the right phase for your migration:

```
┌─────────────────────────────────────────────────────────────┐
│ INFRASTRUCTURE                                              │
│ For sync, state management, versioning, snapshots          │
│ These enable other features to exist                        │
│ Examples: idempotency keys, projection snapshots, versions │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ FEATURES                                                    │
│ For user-facing functionality                              │
│ New tables, new columns, new queries                       │
│ Examples: due_date, username, user_settings               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ SECURITY                                                    │
│ For audit trails, compliance, protection                   │
│ Examples: login_logs, rate_limiting, encryption            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ OPTIMIZATION                                                │
│ For performance improvements                               │
│ Indexes, denormalization, caching                          │
│ Examples: contact_name_index, wallet_contact_count         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ REFACTORING                                                 │
│ For cleanup and reorganization                             │
│ Rename columns, normalize data, remove dead code           │
│ Examples: rename deprecated_field → modern_field           │
└─────────────────────────────────────────────────────────────┘
```

---

## Testing Strategy

```bash
# 1. Test on fresh database (simulates new deployment)
createdb test_db
sqlx migrate run --database-url postgres://test_db
# Verify schema looks right
psql test_db
  \d+ table_name

# 2. Test on existing database (simulates upgrade)
createdb existing_db
# Load old schema snapshot
psql existing_db < old_schema.sql
# Run new migration
sqlx migrate run --database-url postgres://existing_db
# Verify schema matches expected
psql existing_db
  \d+ table_name

# 3. Test rollback (if reversible)
sqlx migrate revert
# Verify schema reverted correctly
psql existing_db
  \d+ table_name
sqlx migrate run
# Verify schema is back to current
```

---

## Related
- [[migration-guide.md]] - Explanation of current migrations
- [[architecture.md]] - Why migrations matter to event sourcing
