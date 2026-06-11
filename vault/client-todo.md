---
tags:
  - planning
  - client
  - flutter
  - mobile
---

# Client TODOs (Flutter/Dart & Rust Bridge)

Last updated 2026-06-12. Reflects the post-reorg layout (`crates/client`, `crates/core/{domain,applier,resolver,snapshots}`).

**Quick Navigation**:
- 🔴 [HIGH PRIORITY](#-high-priority-items)
- 🟡 [MEDIUM PRIORITY](#-medium-priority-items)
- 🟢 [LOW PRIORITY](#-low-priority-items)

---

## ✅ Completed (this branch)

### Architecture
- ✅ Renamed crate `flutter_sdk` → `client`; lib is now `libclient.so`
- ✅ Shared rules extracted to `crates/core/{domain,applier,resolver,snapshots}`
- ✅ `SdkProjection` implements `applier::Projection` (event-application rules shared with server)
- ✅ `SdkPermissionStore` implements `resolver::PermissionStore` (permission rules shared with server)
- ✅ `SdkSnapshotStore` implements `snapshots::SnapshotStore` (snapshot rotation shared with server)
- ✅ `can_perform` FFI export — Flutter can ask the local resolver "is X allowed?" for UX

### Schema convergence with server
- ✅ Soft-delete on contacts/transactions (`is_deleted` flag)
- ✅ Explicit `wallet_owners` table — `is_wallet_owner` issues same SQL as server
- ✅ `projection_snapshots` table mirroring server's schema
- ✅ Snapshot writes wired into `sync::pull_and_merge` (every N events / after UNDO)

### Sync / UNDO
- ✅ Retired in-memory `state_builder` + `state` JSON blob; SQLite projection tables are source of truth
- ✅ UNDO rebuilds via `sync::rebuild_projection_tables`, using shared `snapshots::collect_undone_event_ids`
- ✅ Hash-divergence path (server's `/api/sync/hash`) replaces the old permissions-diff polling

### Tests
- ✅ 47/47 integration tests pass

---

## 🔴 High Priority Items

### Dart-side wiring of `can_perform`
- [ ] Regenerate FRB bindings (one-time after the crate rename)
- [ ] Expose `can_perform(action, resource_type, resource_id)` through a Dart helper
- [ ] Wire into screen-level guards (button visibility/enable)
- **Files**: `mobile/lib/api.dart`, `mobile/lib/providers/`, screens that mutate data
- **Effort**: 2-3 hours

### UI button greying via the new can_perform
- [ ] Hide Delete/Edit buttons when `can_perform` returns false
- [ ] Show a tooltip explaining the missing permission
- [ ] Permission denied error mapping (server's error → human-readable message)
- **Files**: `mobile/lib/screens/*`, `mobile/lib/widgets/`
- **Effort**: 4-6 hours

### Idempotency keys (still open from before the reorg)
- [ ] Switch sync payload from `id` (event_id) to `idempotency_key`
- [ ] Local `StoredEvent` carries `idempotency_key` separately
- [ ] Server uses idempotency_key for dedup; generates its own event_id at insertion
- **Files**: `crates/client/src/crud.rs`, `crates/client/src/sync.rs`, `crates/server/src/database/repository/events.rs`
- **Effort**: 2-3 hours

---

## 🟡 Medium Priority Items

### Permissions & Groups UI
- [ ] Display user permissions for current wallet (use `get_my_permissions_api`)
- [ ] Group management UI for admins (create/edit user groups, contact groups)
- [ ] Permission matrix viewer for admins
- [ ] Default group selection in settings screen

### Sync / conflict resolution
- ✅ Offline-first architecture
- ✅ Retry backoff logic
- [ ] Per-event error response from server (PREREQ for granular failure recovery on client)
- [ ] Client-side recovery: drop unpermitted events, retry sync
- [ ] Conflict resolution UI

### Features
- [ ] Biometric authentication
- [ ] Offline notifications (background sync status)
- [ ] Data export/import UI
- [ ] Transaction filtering and search
- [ ] Contact search by name/phone

### Testing
- ✅ 47/47 integration tests in `crates/client/tests/`
- [ ] Widget tests for permission-aware screens

### UI polish
- [ ] Loading states during sync
- [ ] Better error messages: network failure vs permission failure
- [ ] Theme consistency across screens

---

## 🟢 Low Priority Items

### Security (mobile)
- [ ] Default `useHttps() = true` for mobile builds
- [ ] Certificate pinning

### Performance
- [ ] Lazy loading for very large event lists
- [ ] Pagination for contact/transaction lists

### Data management
- [ ] Backup/restore UI
- [ ] Clear local cache with confirmation
- [ ] CSV/JSON export of wallet data

---

## Future / structural

### Snapshot-aware UNDO rollback on the client
The client currently does a full wipe + replay on UNDO (`rebuild_projection_tables`). Server uses snapshots to start from the latest checkpoint instead. To share the algorithm fully:
- [ ] Add `restore_from_snapshot` method to `applier::Projection`
- [ ] Build shared `rollback_to_event(snapshot, events) → projection` in `crates/core/snapshots`
- [ ] Client + server both consume; SDK gets snapshot-aware rollback for free

### Server-side notification stack for offline clients
See [[06-client/01-design-notes]] Decision 2. Backend work tracked in [[backend-todo]].

---

## Related

- [[06-client/00-overview]] — current client architecture
- [[06-client/01-design-notes]] — decisions + statuses
- [[backend-todo]] — server-side work this client work depends on
