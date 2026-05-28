---
tags:
  - planning
  - client
  - flutter
  - mobile
---

# Client TODOs (Flutter/Dart & Rust Bridge)

**Quick Navigation**:
- 🔴 [HIGH PRIORITY](#high-priority-items) (Critical features, blocking issues)
- 🟡 [MEDIUM PRIORITY](#medium-priority-items) (Important features, UX improvements)
- 🟢 [LOW PRIORITY](#low-priority-items) (Nice-to-have, polish)

---

## ✅ COMPLETED

### Client-Core Integration (NEW ARCHITECTURE)
- ✅ Flutter Rust Bridge setup (done)
- ✅ Debitum client-core library (done - crates/debitum_client_core)
- ✅ Permissions module in client-core (done with full tests)
- ✅ Wallet-scoped providers (done - wallet_data_providers.dart)
- ✅ Migrate all mobile screens to use client-core (DONE - all screens use Api FFI wrapper)
- ✅ Remove old service files (DONE - no old services found in codebase)
- ✅ Use client-core for sync, CRUD, permissions (DONE - api.dart is thin FFI wrapper)

---

## 🔴 HIGH PRIORITY ITEMS

### Idempotency Keys (CRITICAL - Prevents Duplicates)
- [ ] **Implement proper idempotency keys on client**
  - Generate UUID when form/page loads (not on submit)
  - Store UUID in form state (or use transaction ID)
  - Send same UUID for all submit attempts
  - Currently: Not sending Idempotency-Key header
  - Impact: Prevents duplicates from network retries, UI glitches, or button re-enabling
  - Effort: 2-3 hours
  - Files: frontend/src/screens/*.dart

### Sync Hash Optimization (PERFORMANCE)
- [ ] Implement client-side hash caching with get_sync_hash endpoint
  - **Current State**: Client calls `GET /api/sync/events?since=<timestamp>` which returns ALL events since timestamp
  - **Problem**: Fetches full event list even when nothing changed (wasteful network round trip)
  - **Solution**: Use get_sync_hash endpoint to detect changes before pulling events
  - **Implementation**:
    1. Store last_hash + last_sync_timestamp in local storage
    2. Call `GET /api/sync/hash` (backend/rust-api/src/handlers/sync.rs:193)
    3. If returned hash == cached hash → skip get_sync_events (save network)
    4. If hash differs → call get_sync_events to pull changes
    5. Update cached hash + timestamp
  - **Server Endpoint**: GET /api/sync/hash returns { hash: String, event_count: i32, last_event_timestamp: String }
  - **Effort**: 1-2 hours
  - **Impact**: Eliminates network round trip when no changes (especially for frequent sync polling)
  - **Files**: crates/debitum_client_core/src/sync.rs (pull_and_merge function), mobile/lib/providers/sync_provider.dart

### Sync Permission Failure Recovery (CLIENT - Dependent on Backend)
- [ ] Client-side sync failure recovery system (DEPENDS ON: backend returning detailed error per event)
  - **What**: Detect permission failures, remove unpermitted events, retry sync
  - **Why**: When batch rejected due to permission, user needs way to recover
  - **Flow**:
    1. Sync batch rejected (backend returns detailed error per event)
    2. Client parses failed_events list
    3. Option A: Auto-remove unpermitted events, retry
    4. Option B: Show "X operations blocked" dialog, let user confirm removal
    5. Retry sync with cleaned batch
    6. User unblocked
  - **Prerequisite**: Backend must return detailed error response (see backend-todos.md)
  - **Files**: crates/debitum_client_core/src/sync.rs (push_unsynced)
  - **Effort**: 2-3 hours (after backend work)

---

## 🟡 MEDIUM PRIORITY ITEMS

### Permissions & Groups (New Functionality)
- [ ] Display user permissions for current wallet
- [ ] Show which actions are available based on permissions
- [ ] Group management UI for admins (create/edit user groups, contact groups)
- [ ] Permission matrix viewer for admins
- [ ] Default group selection in settings screen
- [ ] Show/hide create/edit/delete buttons based on permissions
- [ ] Permission denied error messages (show which action user lacks permission for)

### Sync & Conflict Resolution
- ✅ Offline-first architecture (done in client-core)
- ✅ Retry backoff logic (done in client-core)
- [ ] Implement merge strategy for conflicts (client-core conflict.rs module exists)
- [ ] Handle conflict resolution UI
- [ ] Display sync status and conflicts to user

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
- [ ] Better error messages for network failures vs permission failures

---

## 🟢 LOW PRIORITY ITEMS

### Security (Mobile-Specific)
- [ ] Enforce HTTPS for client-to-backend connection
  - Make `useHttps()=true` default for mobile client
  - Update documentation to require WSS connection
- [ ] Add certificate pinning for client-to-backend
  - Implement public key pinning in mobile app
  - Detect fraudulent certificates

### Performance & Optimization
- [ ] Mobile local storage optimization
  - Compress local event storage
  - Implement lazy loading for large event lists
  - Pagination for contact/transaction lists

### Data Management
- [ ] Implement data backup/restore UI
- [ ] Clear local cache with confirmation dialog
- [ ] Export wallet data (CSV, JSON)

---

## Related Backend TODOs

These client features depend on backend work:
- Sync Permission Failure Recovery (CLIENT) ← requires "Enhanced error response for sync permission failures (BACKEND)"
- Permissions & Groups UI ← requires permission matrix APIs (mostly done)

See **backend-todos.md** for complementary server-side work.
