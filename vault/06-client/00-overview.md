---
tags:
  - client
  - architecture
  - overview
---

# Client Architecture Overview

**Last Updated**: 2026-06-08
**Status**: Active refactoring (branch `client/refactor-and-stabilize`)

The client is **two parts in two places**:

1. **Flutter UI** — `mobile/lib/` (Dart screens, widgets, providers)
2. **Rust core** — `crates/flutter_sdk/` (logic, sync, storage, FRB bridge)

All business logic lives in Rust; Flutter is a thin FFI wrapper (`mobile/lib/api.dart` calls into the Rust crate via Flutter Rust Bridge).

---

## Rust Core Modules (`crates/flutter_sdk/src/`)

| File | LOC | Responsibility |
|---|---:|---|
| `lib.rs` | 790 | FRB bridge entry; backoff/in-flight gates; thread-local config; init |
| `api.rs` | 500 | HTTP client to backend (auth, sync, wallets, permissions) |
| `crud.rs` | 400 | Create/update/delete event append; triggers rebuild + push |
| `sync.rs` | 261 | Push unsynced → server, pull server events → merge → rebuild |
| `state_builder.rs` | 333 | Replay events → Contact/Transaction projection |
| `storage.rs` | 343 | Local SQLite: events, projections, config (per-wallet) |
| `models.rs` | 167 | Typed domain: Contact, Transaction, Currency |
| `ids.rs` | 109 | Typed IDs: WalletId, ContactId, TransactionId (parse validation) |
| `backoff.rs` | 49 | Exponential backoff for sync retries |
| `log_bridge.rs` | 57 | Forward Rust logs to Flutter |
| `frb_generated.rs` | 7368 | Auto-generated FRB bindings (do not edit) |

**Total handwritten code:** ~3000 LOC

---

## Integration Tests (`crates/flutter_sdk/tests/`)

| File | Focus |
|---|---|
| `single_app.rs` | Single app CRUD + sync round-trip |
| `multi_app_sync.rs` | Multiple apps sharing one wallet |
| `offline_online_multi_app.rs` | Disconnected operation + reconnection |
| `resync.rs` | Full resync when an app missed events |
| `permissions.rs` | Read/write permission grants and revokes |
| `conflict.rs` | Concurrent event conflict handling |
| `connection.rs` | Network reachability behavior |
| `comprehensive_events.rs` | All event types appear in event log |
| `stress.rs` | Many concurrent operations |
| `integration.rs` | End-to-end flows |

These run against a **live backend** (Docker postgres + rust-api). Many currently fail — see `client-todo.md` and `crates/flutter_sdk/BUGS.md`.

---

## Flutter Layer (`mobile/lib/`)

| Path | Role |
|---|---|
| `api.dart` (1310 LOC) | Thin FFI wrapper around Rust core |
| `screens/` | 17 screens, largest: `events_log_screen.dart` (2189), `manage_wallet_screen.dart` (1833) |
| `models/` | Dart mirrors of Rust domain types (with json codegen) |
| `providers/` | Riverpod state |
| `widgets/` | Reusable UI |

Flutter never hits the network directly — every call goes through Rust core which handles auth, sync, storage.

---

## Sync Architecture (one-liner)

```
UI action → Rust crud.append_event → SQLite (unsynced)
                                  → rebuild projection
                                  → push_unsynced → backend
backend → notify (websocket) → Rust pull_and_merge → SQLite
                                                  → rebuild projection
                                                  → emit to Flutter
```

See `06-client/01-sync-flow.md` (TODO) for details.

---

## Known Issues

- 12 active bugs documented in `crates/flutter_sdk/BUGS.md`
- Most are sync/visibility related (multi-app, permission-filtered views, full-resync)
- Architectural: client sends `event_id` instead of `idempotency_key` (see `client-todo.md` HIGH PRIORITY)

---

## Reading Order

1. This file (overview)
2. `[[01-sync-flow]]` — push/pull/merge mechanics (TODO)
3. `[[02-storage-schema]]` — local SQLite tables (TODO)
4. `[[03-event-flow]]` — event creation lifecycle (TODO)
5. `[[00-refactoring-plan]]` — the plan we're executing now

---

## Related

- [[../client-todo]] — frontend/mobile work backlog
- [[../backend-todo]] — backend work backlog
- `crates/flutter_sdk/BUGS.md` — failing integration tests with explanations
