---
name: database-refactoring
description: Centralize database logic into organized module with repository pattern
metadata:
  type: project
  status: phase-1-complete
---

# Database Refactoring Plan

**Goal**: Centralize database logic and queries; create a clean repository interface.

**Status**: ✅ Phase 1 Complete - Module structure created, migrations preserved

---

## Current State

### Database Code Locations
- **Connection Pool**: `crates/server/src/database/pool.rs` ✅
- **Models**: `crates/server/src/database/models/` ✅ (event, contact, transaction, wallet, permission, user)
- **Repository Interface**: `crates/server/src/database/repository.rs` ✅ (stub)
- **Raw Queries**: Still scattered across handlers (sync.rs, wallets.rs, etc.) - 1000+ sqlx calls to move
- **Migrations**: `crates/server/migrations/` (21 files, untouched)

---

## Implemented Structure

```
crates/server/src/database/
├── mod.rs                         ← Module exports + re-exports
├── pool.rs                        ← Connection pool (PgPool, DatabasePool type)
├── error.rs                       ← DbError enum (NotFound, DuplicateKey, etc.)
│
├── models/                        ← Database row/entity types
│   ├── mod.rs                     ← Exports all models
│   ├── event.rs                   ← Event, EventRow
│   ├── contact.rs                 ← Contact, ContactProjection
│   ├── transaction.rs             ← Transaction, TransactionProjection
│   ├── wallet.rs                  ← Wallet, WalletUser
│   ├── permission.rs              ← PermissionAction, UserGroup, ContactGroup
│   └── user.rs                    ← User, UserSettings
│
└── repository.rs                  ← Data access layer
    ├── DatabaseRepository trait   (to be implemented in Phase 2)
    └── Database impl stub         (queries to be added in Phase 2-4)
```

---

## Implementation Phases (Revised)

### ✅ Phase 1: Module Structure & Models (COMPLETE)
- [x] Create `crates/server/src/database/` module organization
- [x] Create `pool.rs` with connection pool setup
- [x] Create `error.rs` with DbError enum
- [x] Create `models/` submodule with all entity types
  - [x] event.rs - Event, EventRow
  - [x] contact.rs - Contact, ContactProjection
  - [x] transaction.rs - Transaction, TransactionProjection
  - [x] wallet.rs - Wallet, WalletUser
  - [x] permission.rs - PermissionAction, UserGroup, ContactGroup
  - [x] user.rs - User, UserSettings
- [x] Create `repository.rs` with DatabaseRepository trait stub
- [x] Verify compilation (no unused warnings, just unused imports)

**Milestone**: ✅ New module structure compiles, migrations directory preserved

### Phase 2: Repository Trait Definition (NEXT)
- [ ] Define DatabaseRepository trait with all data access methods
  - [ ] Events: get_events, get_event_by_id, insert_event, delete_event, etc.
  - [ ] Contacts: get_contacts, get_contact, create_contact, update_contact, delete_contact, etc.
  - [ ] Transactions: similar pattern
  - [ ] Users: get_user, create_user, update_user, etc.
  - [ ] Wallets: get_wallet, list_user_wallets, create_wallet, etc.
  - [ ] Permissions: get_user_groups, get_contact_groups, get_permission_matrix, etc.
- [ ] Create Database struct with pool field
- [ ] Implement DatabaseRepository for Database (methods with SQL implementations)

**Effort**: 2-3 hours
**Milestone**: Repository trait defined, Database impl compiles with real queries

### Phase 3: Extract SQL Queries (BULK WORK)
For each handler file (in order): auth.rs → users.rs → wallets.rs → contacts.rs → transactions.rs → sync.rs
- [ ] Identify all sqlx queries in handler
- [ ] Move to corresponding repository method implementation
- [ ] Update handler to call `db.method_name()` instead of raw SQL
- [ ] Test that behavior is unchanged
- [ ] Commit after each handler

**Effort**: 4-6 hours (largest phase)
**Milestone**: All queries moved to repository, handlers use clean interface

### Phase 4: Testing & Validation
- [ ] Run all backend tests → should pass unchanged
- [ ] Run migrations → should apply without error
- [ ] Manual testing of all API endpoints
- [ ] Document public API in code comments

**Effort**: 1-2 hours
**Milestone**: All tests pass, database module is production-ready

---

## Benefits

### Immediate
- **Single source of truth**: All SQL in one place (easier to audit, optimize)
- **Organization**: Database code clearly separated from handlers
- **Testability**: Database logic testable independently if needed
- **Clarity**: Repository interface documents what database operations exist

### Future
- **Pluggable backends**: Can implement Repository trait for different databases
- **Code reuse**: Easy to extract if building CLI tools or admin dashboards
- **Query optimization**: Central location to add caching, batching, etc.

---

## Migration Plan

The migrations directory in `crates/server/migrations/` is NOT moved. SqlX will continue to discover migrations from there automatically.

If in the future the database module becomes its own crate, migrations can be moved at that time with sqlx.toml configuration.

---

## Success Criteria

- ✅ Module structure created and compiles
- ✅ Database models defined in `models/` submodule
- ✅ Pool setup isolated in `pool.rs`
- ✅ DatabaseRepository trait defined
- ✅ Errors centralized in `error.rs`
- [ ] All queries moved to repository (Phase 2-3)
- [ ] All handler tests pass without modification (Phase 4)
- [ ] No raw sqlx calls in handlers (Phase 3 complete)

---

## Timeline

- **Done**: Phase 1 (module setup) - ~2 hours
- **Next**: Phase 2 (trait definition) - 2-3 hours
- **Then**: Phase 3 (query extraction) - 4-6 hours  
- **Finally**: Phase 4 (testing) - 1-2 hours

**Total**: ~10-13 hours

Recommend: Phase 2 in this session, Phases 3-4 in follow-up sessions
