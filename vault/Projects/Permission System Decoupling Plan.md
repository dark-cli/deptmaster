# Permission System Decoupling & User-Level Scoping

## Context
The permission system is currently tightly coupled to wallets:
- user_groups, contact_groups have wallet_id foreign keys (wallet-scoped)
- permission_actions is global
- group_permission_matrix is wallet-scoped
- user_wallet_settings store wallet-specific default groups

This prevents proper implementation of user-level operations (users.rs, settings.rs), which currently use the hack:
```sql
SELECT id FROM users_projection LIMIT 1
```

**Goal:** Decouple permission system to support BOTH user-scoped AND wallet-scoped operations, enabling:
1. User-level settings (dark_mode, default_direction, etc.)
2. User-level backup/export (contacts & transactions without wallet context)
3. Clean separation: user-level features don't require wallet context
4. Wallets.rs continues to use wallet-scoped permission matrix for access control

## Current Architecture

### Database Schema (Wallet-Scoped Only)
```
permission_actions (global)
├── id, name, resource

user_groups (wallet-scoped)
├── id, wallet_id, name, is_system
└── user_group_members → users

contact_groups (wallet-scoped)
├── id, wallet_id, name, type, is_system
└── contact_group_members → contacts

group_permission_matrix (wallet-scoped)
└── user_group_id × contact_group_id × permission_action_id

user_wallet_settings (wallet-scoped)
└── wallet_id, user_id, default groups
```

### Current Usage
- **wallets.rs:** Uses wallet-scoped groups for permission matrix (essential)
- **users.rs:** Queries contacts/transactions directly by user_id (no auth context)
- **settings.rs:** Stores settings per user (but currently per wallet)

## Proposed Architecture

### Scope Types
1. **WALLET-SCOPED** (existing, unchanged): wallets.rs operations
   - user_groups, contact_groups tied to wallet_id
   - permission_matrix controls wallet access
   
2. **USER-SCOPED** (new): user.rs, settings.rs operations
   - user_settings table (not wallet-specific)
   - No wallet requirement
   - User-level defaults and preferences

### Database Schema Changes

**1. Rename user_wallet_settings → wallet_user_settings (no changes to structure)**
- Clarifies it's still wallet-scoped
- Stores wallet-specific default group selections

**2. Create new user_settings table (USER-SCOPED)**
```sql
CREATE TABLE user_settings (
    user_id UUID PRIMARY KEY REFERENCES users_projection(id) ON DELETE CASCADE,
    dark_mode BOOLEAN DEFAULT true,
    default_direction VARCHAR(32) DEFAULT 'give',
    flip_colors BOOLEAN DEFAULT false,
    due_date_enabled BOOLEAN DEFAULT false,
    default_due_date_days INT DEFAULT 30,
    default_due_date_switch BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
)
```

## Code Organization

### New Module Structure
```
src/
├── database/
│   ├── repository/
│   │   ├── permissions.rs (UNCHANGED - wallet-scoped only)
│   │   ├── user_settings.rs (NEW - user-scoped settings)
│   │   └── mod.rs (add user_settings trait methods)
│   └── models/
│       ├── permission.rs (UNCHANGED)
│       └── user_settings.rs (NEW model struct)
│
├── handlers/
│   ├── wallets.rs (UNCHANGED - uses wallet-scoped permissions)
│   ├── settings.rs (REFACTORED - now uses user_settings repo)
│   └── users.rs (REFACTORED - add AuthUser, remove LIMIT 1 hack)
│
└── services/
    └── (existing permission_service continues unchanged)
```

### Key Principle: Dual Path
- **Wallet operations** (wallets.rs) → permission_service + wallet-scoped groups
- **User operations** (users.rs, settings.rs) → AuthUser extraction → user-level operations (no permission matrix)

## Implementation Plan

### Phase 1: Create User-Scoped Settings
1. Create migration: add user_settings table
2. Create user_settings model in src/database/models/user_settings.rs
3. Create repository methods in src/database/repository/user_settings.rs
4. Add trait methods to DatabaseRepository in mod.rs

### Phase 2: Refactor settings.rs
1. Add AuthUser extraction to handlers
2. Replace "SELECT LIMIT 1" hack with extracted user_id from AuthUser
3. Update handlers to use repo.get_user_settings_impl() instead of repo.get_user_settings_all()
4. Store in user_settings table (not wallet_wallet_settings)

### Phase 3: Refactor users.rs
1. Add AuthUser extraction to backup handler
2. Replace "SELECT LIMIT 1" hack with extracted user_id from AuthUser
3. Query contacts/transactions by user_id (already in repo, not wallet-scoped)
4. Remove TODO comments once refactored

### Phase 4: Verify Wallets.rs
1. Confirm wallets.rs is UNCHANGED
2. Confirm permission_service continues to use wallet-scoped groups
3. Run wallet tests to ensure no regressions

## Critical Files

### To Create
- src/database/migrations/XXX_add_user_settings.sql - new user_settings table
- src/database/models/user_settings.rs - UserSettings struct
- src/database/repository/user_settings.rs - UserSettings CRUD methods

### To Modify
- src/database/repository/mod.rs - add UserSettings trait methods
- src/handlers/settings.rs - extract AuthUser, use user_settings repo
- src/handlers/users.rs - extract AuthUser, remove LIMIT 1 hack

### To Reference (NO CHANGES)
- src/database/models/permission.rs - unchanged, wallet-scoped
- src/database/repository/permissions.rs - unchanged, wallet-scoped
- src/handlers/wallets.rs - unchanged, uses wallet-scoped permissions
- src/services/permission_service.rs - unchanged

## Verification

### Tests
```bash
# Settings handler tests
cargo test --test settings_test

# Users handler tests  
cargo test --test users_test

# Wallets tests (regression check)
cargo test --test wallet_management_test
cargo test --test debug_wallet_tests

# Full suite
cargo test
```

### Key Assertions
- settings.rs handlers extract AuthUser correctly
- users.rs handlers extract AuthUser correctly
- wallets.rs continues to work unchanged
- No SQL injection via auth context
- User-scoped data isolated per user
- Wallet-scoped data isolated per wallet

## Scope & Timeline
- Phase 1: ~1 hour (database + repo methods)
- Phase 2: ~30 min (settings.rs refactoring)
- Phase 3: ~30 min (users.rs refactoring)
- Phase 4: ~15 min (verification)
- **Total: ~2 hours**

## Benefits
1. ✅ Eliminates "SELECT LIMIT 1" hack
2. ✅ Proper user authentication context in settings/users handlers
3. ✅ User-level data scoping (dark_mode per user, not per wallet)
4. ✅ Cleaner separation between user-scoped and wallet-scoped operations
5. ✅ Foundation for future user-level features
6. ✅ Wallets.rs permission system unchanged (zero risk of regression)
