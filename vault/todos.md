# TODOs & Incomplete Features

## 🚨 CRITICAL - BLOCKS PRODUCTION

### Data Isolation Bug (All Users Can Access Each Other's Data)
- [ ] **URGENT: Add user_id filtering to ALL handlers** - ANY authenticated user can see/modify ALL other users' data
  - Issue: Handlers query projections with NO WHERE user_id filter
  - Examples: `get_contacts`, `get_transactions`, `get_settings` all return ALL data
  - User A sees User B's contacts, transactions, settings
  - User A can modify User B's data
  - This completely breaks the multi-user system
  - Solution: Every CRUD handler needs `WHERE user_id = $1` in SQL queries
  - Affected tables: contacts_projection, transactions_projection, users_projection, settings_projection
  - Estimated scope: ~20+ handlers need modification

### Permission System (Admin Endpoints Accessible by Regular Users)
- [ ] Add `is_admin` field to AuthUser struct - required for role-based access control
- [ ] Add handler-level role checks to `/api/admin/*` endpoints - currently protected by routing only, not logic

---

## Backend (Rust)

### Authentication & Authorization
- [ ] JWT token implementation (planned)
- [ ] Multi-user support (single user currently)
- [ ] Role-based access control
- [ ] Rate limiting (middleware exists, needs configuration)

### Integration Tests
- [ ] Complete integration_test.rs stubs (marked with TODO)
- [ ] Transaction handler tests (test_helpers needed)
- [ ] WebSocket integration tests
- [ ] Database setup for test suite

### Background Scheduler
- [ ] Implement cleanup logic in scheduler.rs (TODO comment)
- [ ] Configure cron tasks for maintenance
- [ ] Event log archiving strategy

### Admin Panel
- [ ] Merge conflict resolution UI
- [ ] Event filtering and search improvements
- [ ] Projection status dashboard

---

## Mobile (Flutter)

### Sync & Conflict Resolution
- [ ] Implement merge strategy for conflicts (SyncServiceV2, TODO comment)
- [ ] Handle conflict resolution UI
- [ ] Retry logic refinement for failed syncs
- [ ] **Implement proper idempotency keys on client** (HIGH)
  - Generate UUID when form/page loads (not on submit)
  - Store UUID in form state
  - Send same UUID for all submit attempts
  - Currently: Not sending Idempotency-Key header at all
  - This prevents duplicates from network retries, UI glitches, or button re-enabling

### Features
- [ ] Biometric authentication (library added, not integrated)
- [ ] Offline notifications (background sync status)
- [ ] Data export/import UI
- [ ] Transaction filtering and search
- [ ] Contact search by name/phone

### Testing
- [ ] Unit tests for services
- [ ] Integration tests with mock server
- [ ] Widget tests for screens

### UI Polish
- [ ] Theme consistency across screens
- [ ] Loading states for network requests
- [ ] Error handling UI improvements

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
