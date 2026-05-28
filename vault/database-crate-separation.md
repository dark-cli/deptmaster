---
name: database-crate-separation
description: Plan for extracting database logic into a separate crate (crates/debitum_db)
metadata:
  type: project
  status: planning
---

# Database Crate Separation Plan

**Goal**: Decouple database logic from the API crate; create a standalone, reusable database layer.

**Result**: `crates/debitum_db` crate that:
- Manages all database connections
- Owns all migrations
- Defines all database types/models
- Provides a clean Repository interface to other crates
- Can be tested independently
- Can be reused by other crates (mobile, CLI tools, etc.)

---

## Current State

### Database Code Locations
- **Connection Pool**: `backend/rust-api/src/database/mod.rs` (41 lines)
- **Raw Queries**: Scattered across handlers (sync.rs, wallets.rs, etc.) - 1000+ sqlx calls
- **Migrations**: `backend/rust-api/migrations/` (21 files)
- **Database Access**: No centralized repository; handlers hit DB directly

### Problem
- Queries scattered across many files (hard to audit)
- No single source of truth for SQL
- Database layer tightly coupled to API
- Mobile/CLI can't reuse database logic
- Difficult to test database code in isolation

---

## Proposed Architecture

### New Crate Structure
```
crates/
└── debitum_db/
    ├── Cargo.toml
    ├── migrations/                    ← Moved from backend/rust-api/migrations
    │   ├── 001_initial_schema.sql
    │   ├── 002_remove_transaction_settled.sql
    │   └── ... (all 21 migrations)
    │
    └── src/
        ├── lib.rs                     ← Public API
        ├── pool.rs                    ← Connection pool setup (moved from backend/rust-api/src/database/mod.rs)
        │
        ├── models/                    ← Database row types (moved from scattered definitions)
        │   ├── mod.rs
        │   ├── event.rs              ← Event, EventRow
        │   ├── contact.rs            ← Contact, ContactProjection, ContactRow
        │   ├── transaction.rs        ← Transaction, TransactionRow
        │   ├── wallet.rs             ← Wallet, WalletUser
        │   ├── permission.rs         ← PermissionAction, UserGroup, ContactGroup
        │   └── user.rs               ← User, UserSettings
        │
        ├── repository/                ← Data access layer
        │   ├── mod.rs                ← DatabaseRepository trait definition
        │   ├── database.rs           ← Database impl (concrete SQLx calls)
        │   ├── events.rs             ← Events queries (organized by entity)
        │   ├── contacts.rs           ← Contacts queries
        │   ├── transactions.rs       ← Transactions queries
        │   ├── wallets.rs            ← Wallets queries
        │   ├── permissions.rs        ← Permission queries
        │   ├── users.rs              ← Users queries
        │   └── snapshots.rs          ← Projection snapshot queries
        │
        ├── queries/                   ← SQL constants (if not inline)
        │   ├── mod.rs
        │   ├── events.rs
        │   ├── contacts.rs
        │   └── ...
        │
        └── error.rs                   ← Database-specific errors
```

### Backend/Rust-API Structure After Change
```
backend/rust-api/
├── Cargo.toml                    ← Add dependency: debitum_db
│
└── src/
    ├── lib.rs
    ├── main.rs
    ├── handlers/                 ← No sqlx queries; use db.repository methods
    ├── middleware/
    ├── services/
    └── (no database/ directory)  ← Removed
```

---

## Implementation Phases

### Phase 1: Create New Crate Structure (1-2 hours)
- [ ] Create `crates/debitum_db/Cargo.toml` with sqlx, tokio, uuid, chrono
- [ ] Create `crates/debitum_db/src/lib.rs` with public exports
- [ ] Move migration files to `crates/debitum_db/migrations/`
- [ ] Create `crates/debitum_db/src/pool.rs` (from backend/rust-api/src/database/mod.rs)
- [ ] Create `crates/debitum_db/src/error.rs` (database error types)
- [ ] Create `crates/debitum_db/src/models/mod.rs` structure (empty for now)

**Milestone**: New crate compiles, migrations directory recognized by sqlx

### Phase 2: Define Repository Trait (1-2 hours)
- [ ] Create `DatabaseRepository` trait with all data access methods
  - Events: get_events, get_event_by_id, insert_event, delete_event, etc.
  - Contacts: get_contacts, get_contact, create_contact, update_contact, delete_contact, etc.
  - Transactions: similar pattern
  - Users: get_user, create_user, update_user, etc.
  - Wallets: get_wallet, list_user_wallets, create_wallet, etc.
  - Permissions: get_user_groups, get_contact_groups, get_permission_matrix, etc.
- [ ] Create `Database` struct implementing `DatabaseRepository`
  - Contains `PgPool`
  - Each method implements the SQL query
- [ ] Create error mapping (sqlx errors → domain errors)

**Milestone**: Repository trait defined, Database impl compiles, can be imported by backend

### Phase 3: Move Database Models (2-3 hours)
- [ ] Extract all database row types from handlers/services
  - Event, EventRow
  - Contact, ContactProjection
  - Transaction, TransactionProjection
  - User, UserSettings
  - Wallet, WalletUser
  - PermissionAction, UserGroup, ContactGroup
  - etc.
- [ ] Move to `crates/debitum_db/src/models/`
- [ ] Update imports in backend handlers to use new module path

**Milestone**: All database types defined in debitum_db, backend imports work

### Phase 4: Extract SQL Queries (3-4 hours - largest phase)
- [ ] For each handler file (sync.rs, wallets.rs, etc.):
  - [ ] Identify all sqlx queries
  - [ ] Move to corresponding repository method
  - [ ] Update handler to call `db.repository.method_name()` instead
  - [ ] Test that behavior is unchanged
- [ ] Start with handlers in order: auth.rs → users.rs → wallets.rs → contacts.rs → transactions.rs → sync.rs

**Milestone**: All queries moved to repository, handlers use clean interface, tests pass

### Phase 5: Update Backend Dependencies (30 minutes)
- [ ] Update `backend/rust-api/Cargo.toml` to depend on `debitum_db`
- [ ] Remove direct sqlx dependency from backend (now via debitum_db)
- [ ] Update `main.rs` to use `debitum_db::pool::create_pool()` instead of local code
- [ ] Remove `backend/rust-api/src/database/` directory (moved to crate)

**Milestone**: Backend builds, runs, uses external database crate

### Phase 6: Testing & Validation (1-2 hours)
- [ ] Run all backend tests → should pass unchanged
- [ ] Run migrations → should apply without error
- [ ] Manual testing of API endpoints → should work as before
- [ ] Document public API in `crates/debitum_db/README.md`

**Milestone**: All tests pass, database crate is production-ready

---

## Benefits

### Immediate
- **Single source of truth**: All SQL in one place (easier to audit, optimize)
- **Testability**: Database logic testable independently of API handlers
- **Maintainability**: Changes to database queries don't require touching handler code
- **Clarity**: Repository interface documents what database operations exist

### Future
- **Code reuse**: Mobile backend, CLI tools, admin dashboards can all use debitum_db
- **Pluggable backends**: Can implement Repository trait for SQLite, MongoDB, etc.
- **Migration management**: Migrations managed by single crate (prevents drift)
- **Performance**: Easier to optimize queries when centralized

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Breaking changes during extraction | Comprehensive test suite validates behavior unchanged |
| Migration issues | Test migrations on separate database before merging |
| Import cycles | Clear dependency: backend depends on db, db depends on nothing but sqlx/tokio |
| Large refactoring = many conflicts | Work incrementally: phase by phase, commit after each |

---

## Success Criteria

- ✅ `crates/debitum_db` crate exists and builds independently
- ✅ All migrations moved and run successfully
- ✅ All database types defined in debitum_db
- ✅ Repository trait covers all current database operations
- ✅ Backend handlers use only repository methods (no raw sqlx calls)
- ✅ All existing tests pass without changes
- ✅ All API endpoints work identically to before
- ✅ Code compiles with no warnings

---

## Timeline Estimate

- **Phase 1-2**: Setup + trait definition = 2-4 hours
- **Phase 3**: Models extraction = 2-3 hours
- **Phase 4**: Query extraction = 3-4 hours (largest)
- **Phase 5**: Dependency updates = 30 minutes
- **Phase 6**: Testing & validation = 1-2 hours

**Total**: ~9-16 hours spread across multiple commits/days

Recommend breaking this into:
1. Weekend session: Phases 1-2 (foundation)
2. Next session: Phase 3-4 (bulk work)
3. Final session: Phase 5-6 (integration & validation)

---

## Related Notes
- [[todos.md]] - Repository pattern plan (Phase 2 of this larger refactoring)
- [[migration-guide.md]] - All migrations documented
- [[architecture.md]] - Current architecture
