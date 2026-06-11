---
tags:
  - client
  - architecture
  - overview
---

# Client Architecture Overview

**Last Updated**: 2026-06-12
**Status**: Stable — 47/47 integration tests pass

The client is **two parts in two places**:

1. **Flutter UI** — `mobile/lib/` (Dart screens, widgets, providers)
2. **Rust client lib** — `crates/client/` (logic, sync, storage, FRB bridge)

All business logic lives in Rust; Flutter is a thin FFI wrapper over the Rust crate via Flutter Rust Bridge.

---

## What's shared vs per-side

The Rust client lib **depends on the same rule crates as the server**. Identical event-application, identical permission resolution, identical snapshot rotation — written once, executed on both sides:

| Concern | Crate | Owns |
|---|---|---|
| Event types | `crates/core/domain` | `DomainEvent`, `EventData` (28 variants), typed IDs |
| Event application | `crates/core/applier` | `Projection` trait + `apply()` dispatch |
| Permission resolution | `crates/core/resolver` | `PermissionStore` trait + 3-state matrix rules |
| Snapshot rotation | `crates/core/snapshots` | `SnapshotStore` trait + UNDO predicates |

Each side implements the three storage adapter traits against its own engine:

| Trait | Server (`crates/server`) | Client (`crates/client`) |
|---|---|---|
| `applier::Projection` | `ServerPermissionProjection` (sqlx + Postgres) | `SdkProjection` (rusqlite + SQLite) |
| `resolver::PermissionStore` | `ServerPermissionStore` | `SdkPermissionStore` |
| `snapshots::SnapshotStore` | `ServerSnapshotStore` | `SdkSnapshotStore` |

Authority stays one-sided: **server enforces, client advises.** The client's local `resolver::resolve_actions` is for UX only — greying buttons the user can't tap, predicting the server's decision. Every write still goes through the server, which is the only place that can reject it.

---

## Rust client lib (`crates/client/src/`)

| File | Responsibility |
|---|---|
| `lib.rs` | FRB bridge entry; thread-local config; init; `can_perform` FFI export |
| `api.rs` | HTTP client to backend (auth, sync, wallets, permissions) |
| `crud.rs` | Append events; runs them through `applier::apply` so projection tables stay current |
| `sync.rs` | Push unsynced → pull and merge → optional snapshot write |
| `storage.rs` | SQLite schema + low-level helpers |
| `models.rs` | Wire types: Contact, Transaction, Currency |
| `ids.rs` | Typed IDs: WalletId, ContactId, TransactionId |
| `sdk_projection.rs` | `applier::Projection` impl |
| `sdk_store.rs` | `resolver::PermissionStore` impl |
| `sdk_snapshot_store.rs` | `snapshots::SnapshotStore` impl |
| `backoff.rs`, `log_bridge.rs` | infra |
| `frb_generated.rs` | Auto-generated FRB bindings (do not edit) |

---

## Client SQLite schema

Mirrors the server's projection schema as closely as possible — every per-side divergence is intentional and called out:

| Table | Notes |
|---|---|
| `events` | Local event log (synced + unsynced) |
| `contacts` | Projection. Mirrors `contacts_projection` on server, with `is_deleted INTEGER` |
| `transactions` | Projection. Mirrors `transactions_projection`, with `is_deleted INTEGER` |
| `wallet_users` | Membership + role |
| `wallet_owners` | Owner tracking (NEW). Dual-written by `SdkProjection` when role='owner'. Lets `is_wallet_owner` issue the same SQL as the server |
| `user_groups`, `contact_groups`, `user_group_members`, `contact_group_members`, `group_permission_matrix` | Permission tables mirroring the server |
| `projection_snapshots` | Snapshot stack (NEW). Same shape as server, `last_event_id` is TEXT (UUID) instead of BIGINT — the only legitimate per-side schema diff |
| `config` | Key-value (current wallet, last-sync timestamp, server hash for divergence detection) |

---

## Sync flow

```
UI action
  → crud::append_event
    → storage::events_insert         (mark unsynced)
    → applier::apply (via SdkProjection)  (update projection tables)
    → if event_type == "UNDO":
        sync::rebuild_projection_tables    (full UNDO-aware rebuild)
    → sync::push_unsynced              (POST to server)

server WebSocket / poll
  → sync::pull_and_merge
    → fetch new events from server
    → applier::apply each one        (update projection tables)
    → if batch contains UNDO:
        rebuild_projection_tables
    → maybe_save_snapshot            (every N events or after UNDO)
```

UNDO triggers a full rebuild because `applier::apply` is a no-op for UNDO variants — the undone event's effect is still in the projection tables. Future work (see [[../03-snapshots/]]) will restore from the latest snapshot before replaying instead of starting from scratch.

---

## Integration tests (`crates/client/tests/`)

Each file is a submodule of `tests/integration.rs`. They run against a live backend (Docker postgres + server crate). Run via:

```
./scripts/manage.sh test-integration
```

| File | Focus |
|---|---|
| `single_app.rs` | Single app CRUD + sync round-trip |
| `multi_app_sync.rs` | Multiple apps sharing one wallet |
| `offline_online_multi_app.rs` | Disconnected operation + reconnection |
| `resync.rs` | Full resync when an app missed events |
| `permissions.rs` | Read/write permission grants and revokes |
| `conflict.rs` | Concurrent event conflict handling |
| `connection.rs` | Network reachability behavior |
| `comprehensive_events.rs` | Every event type appears in the log |
| `stress.rs` | Many concurrent operations |

**All 47 tests pass.**

---

## Flutter layer (`mobile/lib/`)

Flutter is a mechanical shell. The Rust client lib does the work; Dart renders the result.

| Path | Role |
|---|---|
| `api.dart` | Thin FFI wrapper around Rust client |
| `screens/` | UI screens |
| `models/` | Dart mirrors of Rust domain types |
| `providers/` | Riverpod state |
| `widgets/` | Reusable UI |

Flutter never hits the network directly. Every call goes through Rust client which handles auth, sync, storage.

---

## Reading order

1. This file
2. [[01-design-notes]] — architectural decisions and their status
3. [[../00-getting-started/04-main-architecture]] — system-level event-sourcing architecture
4. [[../02-projections/]] — projection mechanics
5. [[../03-snapshots/]] — snapshot rotation
6. [[../04-permissions-and-undo/]] — permission model + UNDO semantics

---

## Related

- [[../client-todo]] — client work backlog
- [[../backend-todo]] — server work backlog
- [[../99-reference/01-glossary]] — terms
