---
tags:
  - planning
---

# TODOs & Incomplete Features

**Quick Navigation**:
- ✅ [Completed Work](#completed---merged-from-feature-advanced-permissions-system) (55 commits merged)
- 🔴 [HIGH PRIORITY](#high-priority-items) (Critical bugs, missing auth)
- 🟡 [MEDIUM PRIORITY](#medium-priority-items) (Important features, refactoring)
- 🟢 [LOW PRIORITY](#low-priority-items) (Nice-to-have, optimizations)
- 📋 [External Checklists](#external-checklists-deployment--security) (Deployment, security hardening)

---

## ✅ COMPLETED - MERGED FROM feature/advanced-permissions-system

**Merged**: May 26, 2026 (55 commits, 3+ months of development)

### Multi-Wallet System
- ✅ Wallets as top-level containers (per-wallet data isolation)
- ✅ Wallet membership with roles (owner, admin, member)
- ✅ Database migrations (011, 012, 013)
- ✅ Wallet handlers (create, read, update, delete, list)
- ✅ Wallet context middleware

### Advanced Permission System (Discord/Telegram Style)
- ✅ 13+ permission actions (contact:*, transaction:*, wallet:*, events:read)
- ✅ User groups & contact groups (per wallet)
- ✅ Permission matrix (user_group × contact_group → actions)
- ✅ Permission service with `can_perform()` and `resolve_allowed_actions()`
- ✅ Database migrations (014, 017, 018, 020, 021)
- ✅ Permission enforcement in handlers (contacts, transactions, sync)
- ✅ APIs: `/api/wallets/:wallet_id/me/permissions`, `/api/wallets/:wallet_id/me/settings`

### Testing & Validation
- ✅ Wallet isolation tests
- ✅ Permission enforcement tests
- ✅ Wallet context middleware tests
- ✅ Comprehensive integration tests
- ✅ Client-core permissions module with full test suite

### Mobile & Frontend
- ✅ Wallet model and data providers
- ✅ Wallet screens (selection, creation, management)
- ✅ Mobile animations (glitch, scramble, pixelated text)
- ✅ Flutter Rust Bridge client-core library
- ✅ Rust/Leptos frontend

### Documentation
- ✅ advanced-permissions-plan.md
- ✅ LAYERED_PERMISSION_SYSTEM_DESIGN.md
- ✅ merged-features.md

---

## 🚨 CRITICAL - RESOLVED BY MERGE

### Data Isolation (FIXED)
- ✅ Multi-wallet system solves data isolation
- ✅ All data now scoped to wallet_id
- ✅ User A cannot access User B's data (different wallets/groups)
- ✅ Permission matrix enforces access control
- Status: RESOLVED - No longer global user_id access issue

### Permission System (UPGRADED)
- ✅ Replaced two-tier admin/user system with granular group-based permissions
- ✅ Handlers now enforce permissions at code level (not just routing)
- ✅ Support for custom user groups and contact groups
- Status: RESOLVED - Much more sophisticated than original plan

---

## 🔴 HIGH PRIORITY ITEMS

### Authentication & Authorization Fixes (CRITICAL)
- [ ] Fix create_wallet handler missing AuthUser extraction (CODE TODO)
  - File: `backend/rust-api/src/handlers/wallets.rs`
  - Issue: Uses `SELECT id FROM users_projection LIMIT 1` instead of extracting user from auth
  - Fix: Extract AuthUser from middleware, use authenticated user_id
  - Test: Verify wallet creation is attributed to correct user

- [ ] Enforce TLS encryption for database connections (CRITICAL)
  - Make `sslmode=require` mandatory for production
  - Update `docker-compose.yml` to include `?sslmode=require`
  - Update `config.rs` to ERROR (not warn) in production

- [ ] Enforce HTTPS for client-to-backend connection (CRITICAL)
  - Make `ENABLE_TLS=true` default for backend
  - Make `useHttps()=true` default for mobile client

---

## 🟡 MEDIUM PRIORITY ITEMS

### Backend (Rust) - Next Phase

### Wallet & Permission UX
- [ ] Group management UI for admins (create/edit/delete user groups and contact groups)
- [ ] Permission matrix UI (view/edit what each user group can do)
- [ ] Default group selection in mobile (settings for default contact/transaction groups)
- [ ] Dynamic contact groups (overdue, we_owe, they_owe, contacts_we_own, etc.)
- [ ] Dynamic transaction groups (over_limit, under_limit)
- [ ] Allow/deny permission matrix (currently allow-only)
- [ ] Transaction groups implementation (currently placeholders)

### Authentication & Authorization (COMPLETED/UPDATED)
- ✅ JWT token implementation (done)
- ✅ Multi-wallet support (done)
- ✅ Role-based access control upgraded to group-based (done)
- ✅ Rate limiting (middleware exists, configured in config.rs)

### Integration Tests (UPDATED)
- ✅ Wallet isolation tests (new)
- ✅ Permission enforcement tests (new)
- ✅ Wallet context middleware tests (new)
- ✅ Comprehensive integration tests for multi-wallet sync (new)
- [ ] WebSocket integration tests (still needed)
- [ ] Dynamic group evaluation tests
- [ ] Allow/deny matrix tests (future feature)

### Background Scheduler
- [ ] Implement cleanup logic in scheduler.rs (TODO comment)
- [ ] Configure cron tasks for maintenance
- [ ] Event log archiving strategy

### Admin Panel
- [ ] Merge conflict resolution UI
- [ ] Event filtering and search improvements
- [ ] Projection status dashboard

---

## Mobile (Flutter) - Client-Core Migration & Features

### Client-Core Integration (NEW ARCHITECTURE)
- ✅ Flutter Rust Bridge setup (done)
- ✅ Debitum client-core library (done - crates/debitum_client_core)
- ✅ Permissions module in client-core (done with full tests)
- ✅ Wallet-scoped providers (done - wallet_data_providers.dart)
- ✅ Migrate all mobile screens to use client-core (DONE - all screens use Api FFI wrapper)
- ✅ Remove old service files (DONE - no old services found in codebase)
- ✅ Use client-core for sync, CRUD, permissions (DONE - api.dart is thin FFI wrapper)

### Permissions & Groups (New Functionality)
- [ ] Display user permissions for current wallet
- [ ] Show which actions are available based on permissions
- [ ] Group management UI for admins (create/edit user groups, contact groups)
- [ ] Permission matrix viewer for admins
- [ ] Default group selection in settings screen
- [ ] Show/hide create/edit/delete buttons based on permissions

### Sync & Conflict Resolution
- ✅ Offline-first architecture (done in client-core)
- ✅ Retry backoff logic (done in client-core)
- [ ] Implement merge strategy for conflicts (client-core conflict.rs module exists)
- [ ] Handle conflict resolution UI
- [ ] Display sync status and conflicts to user

### Sync Permission Failure Recovery (CLIENT - FUTURE)
- [ ] Client-side sync failure recovery system (DEPENDS ON: enhanced backend error response)
  - **What**: Detect permission failures, remove unpermitted events, retry sync
  - **Why**: When batch rejected due to permission, user needs way to recover
  - **Flow**:
    1. Sync batch rejected (backend returns detailed error per event)
    2. Client parses failed_events list
    3. Option A: Auto-remove unpermitted events, retry
    4. Option B: Show "X operations blocked" dialog, let user confirm removal
    5. Retry sync with cleaned batch
    6. User unblocked
  - **Files**: crates/debitum_client_core/src/sync.rs (push_unsynced)
  - **Note**: Only implement after backend returns detailed error response
  - Related: WebSocket migration should include this recovery from start

### Idempotency Keys (HIGH PRIORITY)
- [ ] **Implement proper idempotency keys on client**
  - Generate UUID when form/page loads (not on submit)
  - Store UUID in form state (or use transaction ID)
  - Send same UUID for all submit attempts
  - Currently: Not sending Idempotency-Key header
  - This prevents duplicates from network retries, UI glitches, or button re-enabling

### Features
- [ ] Biometric authentication (library added, not integrated)
- [ ] Offline notifications (background sync status)
- [ ] Data export/import UI
- [ ] Transaction filtering and search
- [ ] Contact search by name/phone
- [ ] Wallet switching notifications

### Testing
- ✅ Comprehensive test suite in client-core (permissions, sync, conflict, integration, stress)
- [ ] Widget tests for new permission-aware screens
- [ ] Integration tests with mock wallet setup

### UI Polish
- [ ] Theme consistency across screens
- [ ] Loading states for network requests (show sync in progress)
- [ ] Error handling UI improvements
- [ ] Permission denied error messages (show which action user lacks permission for)

---

## 🟢 LOW PRIORITY ITEMS

### General Architecture

### Security (Hardening - See docs/SECURITY.md for checklist)
- [ ] Production deployment security hardening
- [ ] HTTPS/TLS enforcement
- [ ] Secure session management
- [ ] Rate limiting configuration
- [ ] CORS policy review

### Performance
- [ ] Database query optimization
- [ ] WebSocket message batching
- [ ] Pagination for large event logs
- [ ] Mobile local storage optimization

### Monitoring & Observability
- [ ] Expand `/health` endpoint to expose runtime metrics
  - Database connection pool status (active/idle connections)
  - Request statistics (total requests, errors, latency)
  - Background scheduler status
  - Memory usage
  - Uptime
  - WebSocket connection count
  - Event processing lag/backlog
  - Return JSON with detailed status instead of just "OK"

### Documentation
- [ ] API endpoint examples with curl/Postman
- [ ] Deployment troubleshooting guide
- [ ] Migration guide for data format changes

---

## Code Cleanup & Technical Debt

### Dead Code - Direct Contact/Transaction Handlers (LEGACY)
- [ ] Remove unused direct REST endpoints for contacts/transactions
  - **Discovery**: Mobile client uses ONLY sync API (`POST /api/sync/events`), NOT direct handlers
  - Files affected:
    - `backend/rust-api/src/handlers/contacts.rs` - create_contact, update_contact, delete_contact, get_contacts
    - `backend/rust-api/src/handlers/transactions.rs` - all CRUD endpoints
    - `backend/rust-api/src/main.rs:139-142` - route registrations
  - **Why kept?**: Legacy from pre-sync architecture, never removed after sync API added
  - **Impact**: Unnecessary code complexity, confusing API surface, maintenance burden
  - **Action**: Remove handlers, routes, and verify tests still pass
  - **Note**: Discovered May 27, 2026 - these endpoints have been dead for ~1 year, contributing to codebase bloat (~1000+ lines of unused code)

### Unused Dependencies
- [ ] Remove Lettre (email library) — Declared in Cargo.toml, never used
  - Remove from `Cargo.toml`
  - Remove SMTP variables from `.env.example`
  - Update `architecture.md` (lists "Email: Lettre" in tech stack)

- [ ] Remove or implement Redis
  - Either: Remove from docker-compose.yml, Cargo.toml, config.rs
  - Or: Implement actual caching logic if needed
  - Currently: Declared but not used (wastes resources)

### Security Issues
- [ ] Enforce TLS encryption for database connections (CRITICAL)
  - Make `sslmode=require` mandatory for production
  - Update `docker-compose.yml` to include `?sslmode=require`
  - Update `config.rs` to ERROR (not warn) in production
  - Change default DB password from `dev_password`

- [ ] Add TLS certificate pinning for database (HIGH)
  - Implement certificate pinning to prevent MITM attacks
  - Configure PostgreSQL client certificates

- [ ] Enforce HTTPS for client-to-backend connection (CRITICAL)
  - Make `ENABLE_TLS=true` default for backend
  - Make `useHttps()=true` default for mobile client
  - Update documentation to require WSS connection

- [ ] Add certificate pinning for client-to-backend (HIGH)
  - Implement public key pinning in mobile app
  - Detect fraudulent certificates

### Rate Limiting
- [ ] Reconsider rate limit numbers and change from per-IP to per-user + per-IP
  - Current: 100/60s unauthenticated (1.67/sec), 500/60s authenticated (8.33/sec)
  - Issue: Multiple users behind same IP (corporate networks, VPNs) share limit bucket
  - Solution: Implement per-user limits for authenticated requests + per-IP for unauthenticated
  - Consider: Is 100/60s and 500/60s appropriate for real usage patterns?

### Users Architecture (Event-Sourced with Per-User Tables)
- [ ] Convert users to event-sourced system with separate tables per user
  - Create USER_CREATED, USER_UPDATED, USER_DELETED events
  - Each user gets their own events table partition/shard
  - No mixing of user data (complete isolation)
  - Update handlers to create events before mutations
  - Update handlers to filter queries by authenticated user_id
  - Ensure permission checks: users can only see their own data
  - Add permission logic for cross-user access if needed (shared transactions, etc.)

### Sync Permission Failure Recovery (BACKEND)
- [ ] Enhanced error response for sync permission failures
  - **Current**: Batch rejected with generic 403 "DEBITUM_INSUFFICIENT_PERMISSION"
  - **Issue**: User doesn't know which event failed or why, can't recover
  - **Solution**: Return detailed failure information per event
  - Implementation:
    ```json
    {
      "error": "DEBITUM_SYNC_PERMISSION_DENIED",
      "failed_events": [
        {
          "event_id": "uuid-3",
          "aggregate_type": "contact",
          "event_type": "CREATED",
          "required_permission": "contact:create",
          "reason": "User lacks permission"
        }
      ],
      "accepted_count": 0,
      "total_count": 3
    }
    ```
  - File: `backend/rust-api/src/handlers/sync.rs` - post_sync_events error response
  - Benefit: Enables client-side recovery (remove failed events, retry batch)
  - Note: Architecture decision: reject entire batch (atomic) + detailed error (recovery-friendly) is correct
    - Alternative "accept partial": breaks atomicity, causes inconsistent state
    - With detailed errors: client can recover by removing unpermitted events and retrying

### Sync Handler Refactoring (LARGE TASK)
- [ ] Split sync.rs (2400 lines) into focused modules
  - **Current**: Monolithic file handles push, pull, hash, projections, snapshots, validation
  - **Issue**: Impossible to read/maintain, mixes concerns
  - **Split into**:
    - `sync_pull.rs` — GET /api/sync/events, get_sync_hash (pull logic)
    - `sync_push.rs` — POST /api/sync/events (push logic, ~300 lines)
    - `event_validator.rs` — Validate events, check permissions, check idempotency
    - `projection_applier.rs` — Apply events to projections (contacts, transactions, permissions)
    - `snapshot_manager.rs` — Create/restore snapshots for fast rebuilds
    - `group_manager.rs` — Sync contact/transaction group memberships
    - `sync_utils.rs` — Shared helpers (calculate_total_debt, event_read_allowed, etc.)
  - **Files affected**: 
    - Split `backend/rust-api/src/handlers/sync.rs` → new modules
    - Update `backend/rust-api/src/handlers/mod.rs` to export submodules
    - Update imports in `main.rs`
  - **Testing**: Run existing sync tests after split to verify no behavior change
  - **Note**: This is a large refactoring, estimated ~2-3 hours, but greatly improves code readability

### Database & Repository Architecture
- [ ] Implement Repository pattern with abstracted SQL queries (CODE ARCHITECTURE)
  - Goal: Single data access layer, all SQL in one place, handlers don't touch database
  - Create: `backend/rust-api/src/database/queries.rs` - all SQL strings as constants
  - Create: `backend/rust-api/src/database/repository.rs` - DatabaseRepository trait + Database impl
  - Structure:
    ```
    database/
    ├── queries.rs          ← ALL SQL (Queries::LIST_CONTACTS, Queries::CREATE_CONTACT, etc.)
    └── repository.rs       ← DatabaseRepository trait + Database impl (functions call queries)
    ```
  - Rules: Only `Database` struct calls `sqlx::query()`, handlers call `db.list_contacts()` etc.
  - Benefits: Single point of DB access, all SQL auditable in one file, testable, no SQL in handlers
  - Refactor: Move all inline SQL from handlers/middleware into `queries.rs`

### Middleware & Routing Cleanup
- [ ] Standardize wallet_id extraction to path parameters only (CODE CLEANUP)
  - File: `backend/rust-api/src/middleware/wallet_context.rs`
  - Issue: Supports 3 methods with unclear precedence: query param (`?wallet_id=`), header (`X-Wallet-Id`), path (`/api/wallets/:id/`)
  - Fix: Extract wallet_id ONLY from path (REST standard) - `/api/wallets/:id/...`
  - Remove: Query param and header extraction fallbacks
  - Reason: Single source of truth, clearer intent, easier debugging, better security
  - Test: Verify all endpoints still extract wallet_id correctly

- [ ] Optimize wallet_context middleware to eliminate double-fetch (PERFORMANCE)
  - Issue: Middleware fetches wallet to validate existence, then handler fetches same wallet again
  - Fix: Cache wallet info in request extension, handlers reuse from middleware
  - File: backend/rust-api/src/middleware/wallet_context.rs
  - Benefit: Reduce database queries by 1 per request to wallet endpoints
  - Audit: Check entire codebase for similar double-fetch patterns

- [ ] Audit codebase for double-fetch patterns (CODE OPTIMIZATION)
  - Search for: Middleware fetching data that handlers also fetch
  - Example: wallet_context fetching wallet info, handlers fetching same wallet
  - Document: All instances found and optimize them
  - Pattern: Cache in request extensions when middleware already has the data

### Missing Middleware (Future)
- [ ] Permission enforcement middleware (NICE-TO-HAVE)
  - Currently: Permission checks scattered in handlers (contacts.rs, transactions.rs, etc.)
  - Idea: Create middleware that checks permissions before handler runs
  - Requires: Resource type/id in request, permission service integration
  - Benefit: Centralized permission logic, consistent enforcement, testable

- [ ] Audit logging middleware (MEDIUM PRIORITY)
  - Log all database mutations (INSERT, UPDATE, DELETE)
  - Include: who (user_id), what (operation), when (timestamp), where (wallet_id)
  - Purpose: Compliance, debugging, security audit trail
  - Store: In events table or separate audit_log table

- [ ] Request ID correlation middleware (LOW PRIORITY)
  - Generate/extract request ID for all requests
  - Inject into logs and responses (X-Request-ID header)
  - Purpose: Trace requests across logs, helpful for debugging distributed issues
if user_role != "owner" && user_role != "admin" {
        for contact_group_id in &group_id
- [ ] Caching headers middleware (LOW PRIORITY)
  - Add appropriate Cache-Control headers based on endpoint
  - GET endpoints: cacheable, POST/PUT/DELETE: no-cache
  - Purpose: Improve mobile app performance, reduce bandwidth

### Permissions System (Architecture)
- [ ] Separate admin/user auth into distinct route groups and middleware
  - Currently: middleware checks `if path.starts_with("/api/admin/")` and admin token restrictions
  - Target: Create `admin_routes` (admin_auth_middleware), `user_routes` (user_auth_middleware), `shared_routes` (auth_middleware)
  - Admin routes require `is_admin=true`
  - User routes require `is_admin=false` (deny admin tokens)
  - Shared routes allow both
  - Test: Verify each group enforces its constraints
  - Reason: Separate concerns, routing defines authorization intent, middleware only validates

- [ ] Add `is_admin` field to AuthUser struct
  - Enable handler-level role verification
  - Move from route-only protection to logic-level protection

- [ ] Add handler-level role checks to `/api/admin/*` endpoints
  - Verify user is admin before executing
  - Add tests for permission boundaries

- [ ] Refactor events to use trait-based permission declarations (ARCHITECTURE)
  - Goal: Make permission requirements part of event definition, not separate mapping logic
  - Current: Scattered match statements, separate `map_event_to_permission_action()` function
  - Better: Each event struct implements `Event` trait with `required_permission()` method
  - Implementation:
    ```rust
    pub trait Event {
        fn required_permission(&self) -> Option<PermissionAction>;
        fn aggregate_type(&self) -> AggregateType;
        fn resource_type(&self) -> ResourceType;
    }
    ```
  - Benefits: Single source of truth, impossible to create event without declaring permission, self-documenting
  - Also enables: Removing hardcoded owner/admin bypass (always check permission matrix)
  - Files: `backend/rust-api/src/handlers/sync.rs`, event definitions, sync handler

- [ ] Consolidate contact:update and contact:edit aliases (PERMISSION SYSTEM)
  - Issue: Both `contact:update` and `contact:edit` refer to same action, creates confusion
  - Fix: Use single canonical action name throughout permission matrix
  - Update: Handlers, permission service, permission matrix resolution
  - Reason: Cleaner permission model, no ambiguity in matrix

- [ ] Define clear wallet role semantics (PERMISSION SYSTEM)
  - **OWNER**: Immovable role, cannot be removed, has all permissions, bypasses all checks
  - **ADMIN**: Conditional permission manager, manages other users' permissions BUT cannot modify own permissions
  - **MEMBER**: Group-based permissions, resolved via permission matrix
  - Add: Role semantics documentation to permission system deep dive
  - Enforce: Admin cannot change own permissions (prevent privilege escalation)
  - Test: Verify owner immovability, admin self-permission protection

- [ ] Optimize events:read permission enforcement (PERMISSION SYSTEM - FUTURE)
  - Current: events:read permission currently not enforced at API level (all users can GET /api/sync/events)
  - Optimization: For users without events:read permission, send projections instead of full event history
  - Benefit: Allows fine-grained event access control while maintaining performance
  - Implementation: Send contact/transaction projections to non-permitted users, full events to permitted users
  - Note: Document this approach for future implementation after refactoring event API

- [ ] Optimize permission matrix resolution to single SQL query (PERMISSION SYSTEM)
  - Current approach: Fetch user_group + contact_group contexts, then query permission matrix separately
  - Better approach: Single SQL JOIN query resolving user groups + contact groups + permissions in one call
  - Benefit: Reduced database round-trips, cleaner code, better performance
  - File: backend/rust-api/src/services/permission_service.rs - resolve_allowed_actions()
  - Test: Verify single query returns same permissions as current two-query approach

- [ ] Normalize hardcoded owner/admin bypass to permission matrix (REFACTORING WITH ENUM CONVERSION)
  - Current: Owner and Admin roles bypass all permission checks with hardcoded logic in sync handler
  - Better approach: Owner/Admin still have permissions in matrix (unrestricted group or "all actions"), but everyone goes through same `can_perform()` check
  - Implementation: When converting to Event traits (required_permission on each event), ALWAYS call permission_service::can_perform() for every user including owner/admin
  - Benefit: Unified permission model, single source of truth, impossible for owner/admin to bypass permissions by accident, easier to audit/test
  - Related: This refactoring pairs with Event struct trait approach (event declares required_permission)if user_role != "owner" && user_role != "admin" {
        for contact_group_id in &group_id

### Database Query Performance
- [ ] Add LIMIT 1 to all queries that aren't filtered by unique columns
  - Review all `fetch_one()` calls to ensure query returns at most one row
  - Queries filtering by non-unique columns (email, name, etc.) should have `LIMIT 1`
  - Queries filtering by primary key (id) or using aggregates (EXISTS, COUNT) are fine
  - Prevents wasted CPU/bandwidth on database server

### Configuration & Documentation
- [ ] Review and document production defaults (backend/rust-api/src/config.rs:19-56)
  - **CRITICAL**: JWT_SECRET default (line 36) - must be changed, less than 32 chars
  - **CRITICAL**: DATABASE_URL default (line 28) - uses dev_password, no sslmode
  - **CRITICAL**: ALLOWED_ORIGINS default (line 21) - allows all origins (*)
  - **CRITICAL**: ENABLE_TLS default (line 42-45) - disabled by default
  - RATE_LIMIT_REQUESTS default (line 48-51) - 100/60s, needs reconsideration
  - RATE_LIMIT_WINDOW default (line 52-55) - 60s, needs reconsideration
  - REDIS_URL default (line 30) - points to localhost
  - Create `.env.production.example` with proper values and clear warnings
  - Document which values MUST be changed before production deployment

- [ ] Create DEPLOYMENT.md documenting secure setup
  - TLS certificate configuration
  - Database connection security
  - HTTPS/WSS requirements
  - Production environment variables checklist

- [ ] Document unimplemented features in README
  - Email support (Lettre added but unused)
  - Redis caching (added but unused)
  - Mark which features are in progress

---

## Known Issues

- **Conflict Handling**: Server detects version conflicts but no merge strategy implemented
- **Scheduler Cleanup**: Background cleanup tasks not implemented
- **Test Coverage**: Limited integration test coverage (stubs present)
- **Admin Panel**: Limited to basic event viewing (no filtering/search)
- **Offline→Online Sync**: Glitches when app transitions from offline to online (consider [[sync-architecture.md]] WebSocket-only plan)
- **Unencrypted Connections**: Both database and client-to-backend use HTTP/unencrypted by default

---

---

## External Checklists (Deployment & Security)

These are detailed checklists in separate documents, not development tasks:
- **docs/DEPLOYMENT.md** — Deployment checklist for production (TLS, passwords, CORS, rate limiting, etc.)
- **docs/SECURITY.md** — Security hardening checklist (JWT_SECRET, ALLOWED_ORIGINS, HTTPS, monitoring, backups, etc.)
- **vault/code-cleanup.md** — Explanatory document for cleanup issues (see Unused Dependencies section above)

**Note**: MULTI_WALLET_SYSTEM_PLAN.md and BRANCH_FOLLOW_UPS.md are completed planning documents from the merged feature branch and are kept for historical reference only.

---

## Related Notes
- [[architecture.md]] - Context for these TODOs
- [[decisions.md]] - Design decisions that affect these items
- [[reading-guide.md]] - Navigation guide for vault documentation
- [[permission-system-deep-dive.md]] - Current permission system implementation details
