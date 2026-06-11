# Code Organization

**Main question this file answers:** Where does each piece of code live in the repo?

---

## Repo top level

```
deptmaster/
├── crates/             ← all Rust crates
├── mobile/             ← Flutter app (Dart)
├── scripts/            ← manage.sh, codegen-rust-bridge.sh
├── vault/              ← this documentation
└── (configs, license, README)
```

## Crate layout

```
crates/
├── core/                ← shared rules (no storage engine)
│   ├── domain/          DomainEvent, EventData, typed IDs, Action/Resource
│   ├── applier/         Projection trait + apply() dispatch over all 28 EventData variants
│   ├── resolver/        PermissionStore trait + resolve_actions / permitted_contacts_for_action
│   └── snapshots/       SnapshotStore trait + rotation + UNDO predicates
│
├── server/              ← Postgres backend
└── client/              ← Rust client lib for Flutter; FRB bindings
```

The four `core/*` crates have no Postgres, no SQLite, no axum, no FRB dependencies. They define rules and traits. Server and client implement those traits against their own storage engines.

---

## `crates/core/domain` — pure data

```
domain/src/
├── lib.rs               DomainEvent, EventData enum (28 variants), aggregate types
└── ids.rs               WalletId, ContactId, TransactionId (typed UUID wrappers)
```

No I/O. Pure types. Used by every other crate.

## `crates/core/applier` — event application rules

```
applier/src/
├── lib.rs               Projection trait (~30 methods) + apply() function
└── patches.rs           ContactPatch, TransactionPatch (field-update structs)
```

`apply()` exhaustively matches `EventData`. Per-variant code calls methods on the Projection trait. The trait impl belongs to each side.

## `crates/core/resolver` — permission resolution

```
resolver/src/lib.rs      PermissionStore trait (6 methods)
                         + resolve_actions(store, ctx, resource) -> Set<Action>
                         + permitted_contacts_for_action(store, ctx, action) -> Set<ContactId>
```

3-state matrix (allow / deny / unset). Deny wins. Owner check short-circuits.

## `crates/core/snapshots` — snapshot rotation

```
snapshots/src/lib.rs     SnapshotStore trait
                         + save_snapshot[_with_limit] (next_index → insert → cleanup)
                         + should_create_snapshot[_with_interval]
                         + batch_has_undo / collect_undone_event_ids
                         + UNDO_EVENT_TYPE constant
```

---

## `crates/server` — Postgres backend

```
server/src/
├── domain/              server-only types (DTOs, request/response shapes)
├── database/
│   ├── models/          row structs
│   └── repository/
│       ├── events.rs    insert + apply_event_batch_typed
│       ├── server_projection.rs  ServerPermissionProjection (Projection trait impl)
│       ├── snapshots.rs server-only snapshot helpers (create_snapshot_json, etc.)
│       └── ...
├── handlers/            axum routes
│   ├── sync.rs          POST /sync, GET /sync, GET /sync/hash
│   ├── wallets.rs       wallet management
│   └── ...
├── middleware/          auth, wallet scope, etc.
├── permissions/
│   ├── server_store.rs  ServerPermissionStore (PermissionStore impl)
│   └── ...
├── services/
│   ├── server_snapshot_store.rs   ServerSnapshotStore (SnapshotStore impl)
│   ├── snapshots.rs     server-only snapshot reads
│   └── projections.rs   server's per-pull projection rebuild + UNDO handling
└── main.rs, lib.rs
```

## `crates/client` — Rust client lib

```
client/src/
├── lib.rs               FRB entry, init, can_perform FFI
├── api.rs               HTTP client to server
├── crud.rs              CRUD via events; applier::apply integration
├── sync.rs              push_unsynced, pull_and_merge, snapshot writes
├── storage.rs           SQLite schema + low-level helpers
├── models.rs            wire types (Contact, Transaction, Currency)
├── ids.rs               re-exports of typed IDs
├── sdk_projection.rs    SdkProjection (Projection impl)
├── sdk_store.rs         SdkPermissionStore (PermissionStore impl)
├── sdk_snapshot_store.rs SdkSnapshotStore (SnapshotStore impl)
├── backoff.rs, log_bridge.rs   infra
└── frb_generated.rs     auto-generated FRB bindings
```

Tests at `crates/client/tests/integration.rs` (single binary, submodules). 47/47 pass.

---

## Adding new code

| You're adding... | It belongs in... |
|---|---|
| New event variant | `crates/core/domain` (EventData) |
| New rule for an event variant | `crates/core/applier` (match arm in apply()) |
| New low-level mutation that some event needs | `crates/core/applier` (new Projection trait method) + impl on both `ServerPermissionProjection` and `SdkProjection` |
| New permission rule | `crates/core/resolver` (resolve_actions / permitted_contacts_for_action) |
| New HTTP endpoint | `crates/server/src/handlers/` |
| New DB query that's not event-driven | `crates/server/src/database/repository/` |
| New Flutter-exposed function | `crates/client/src/lib.rs` (FRB-decorated) then regen via `scripts/codegen-rust-bridge.sh` |
| New SQLite table on client | `crates/client/src/storage.rs` (schema) + helper methods |
| New screen/widget | `mobile/lib/screens/` or `mobile/lib/widgets/` (Dart) |
