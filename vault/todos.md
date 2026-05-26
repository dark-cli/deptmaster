# TODOs & Incomplete Features

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
- ✅ ADVANCED_PERMISSIONS_PLAN.md
- ✅ LAYERED_PERMISSION_SYSTEM_DESIGN.md
- ✅ MERGED_FEATURES.md

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

## Backend (Rust) - Next Phase

### Wallet & Permission UX (Next Priority)
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
- [ ] Migrate all mobile screens to use client-core instead of old services
- [ ] Remove old service files (sync_service_v2.dart, projection_service.dart, etc.)
- [ ] Use client-core for sync, CRUD, permissions

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

## General Architecture

### Security
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

### Permissions System
- [ ] Add `is_admin` field to AuthUser struct
  - Enable handler-level role verification
  - Move from route-only protection to logic-level protection

- [ ] Add handler-level role checks to `/api/admin/*` endpoints
  - Verify user is admin before executing
  - Add tests for permission boundaries

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

## Related Notes
- [[architecture.md]] - Context for these TODOs
- [[decisions.md]] - Design decisions that affect these items
