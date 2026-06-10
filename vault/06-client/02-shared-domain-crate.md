---
tags:
  - client
  - architecture
  - proposal
---

# Proposal: Shared Domain Crate(s) Between Client and Server

**Status:** Investigation / proposal (not yet implemented)
**Branch:** `client/refactor-and-stabilize`
**Related:** [[01-design-notes]] · [[00-refactoring-plan]] · [[../backend-todo]]

---

## The question

Both sides are Rust. Both define essentially the same things twice:

| Concept | Server location | Client location |
|---|---|---|
| `EventData` enum (28 variants) | `crates/server/src/domain/events.rs` | duplicated as strings in `state_builder.rs`, `crud.rs`, `sync.rs` |
| `DomainEvent` struct | `crates/server/src/domain/events.rs` | partly mirrored by `models::Event` + `storage::StoredEvent` |
| `Action` enum (~16 actions) | `crates/server/src/permissions/action.rs` | hardcoded strings like `"contact:read"` in `sync.rs` (`READ_ACTIONS`) |
| `Resource` enum | `crates/server/src/permissions/resource.rs` | implicit, by string |
| `Contact`, `Transaction` projection | `crates/server/src/database/models/` (DB-specific) | `crates/flutter_sdk/src/models.rs` (wire-format) |
| `Currency`, `TransactionType`, `TransactionDirection` | implicit strings | typed enums in `models.rs` |
| `WalletRole` (owner/member) | `crates/server/src/permissions/context.rs` | hardcoded strings |
| Typed IDs (`WalletId`, `ContactId`, …) | `Uuid` everywhere | `crates/flutter_sdk/src/ids.rs` (validated strings) |
| `AggregateType` enum | `crates/server/src/domain/events.rs` | implicit strings |
| Event-replay logic | `apply_event_batch` in `events.rs` repository | `state_builder.rs` |

**Cost of duplication today:**
- The client emits events whose shape the server might or might not accept (BUGS #8, #9: UPDATED events not visible — almost certainly a shape mismatch we'd catch at compile time).
- Adding a new event variant means editing N files in M places with no compiler help.
- Permission action names are stringly-typed on the client (`"contact:read"`), so a server-side rename silently breaks the client.
- The client just rewrote the idempotency_key/event_id confusion in JSON; with shared types this would have been a struct field with one obvious name.

**Cost of *not* sharing:** every BUG in `BUGS.md` could plausibly be a shape mismatch the compiler would have caught.

---

## What can be shared

### Definitely shareable (pure types, no I/O)
- `EventData` enum + `AggregateType` + event_type string discriminator
- `Action` enum (permission actions)
- `Resource` enum (with `Uuid` IDs)
- `WalletRole` (owner/member)
- Domain projection structs: `Contact`, `Transaction`, `Wallet`, `Currency`, `TransactionType`, `TransactionDirection`
- Typed IDs: `WalletId`, `UserId`, `ContactId`, `TransactionId`, `EventId`
- Event-replay *logic* (pure function: `apply(state, event) -> state`), once we factor it out of database I/O

### Probably shareable (pure logic that doesn't touch DB/network)
- `DomainEvent` struct (the wrapper around `EventData` + metadata)
- `EventDiscriminator` mapping (we just added this on the server in the type-driven refactor)
- Permission resolution rules — *as data* (action → required resource etc.), not the DB query

### NOT shareable (platform-specific)
- `sqlx::PgRow` parsing (server)
- `rusqlite` storage (client)
- `axum` handlers / `reqwest` API client / `flutter_rust_bridge` exports
- DB connection pools, transactions
- `tokio` async runtimes (acceptable to leave each side's choice)

---

## Proposed crate layout

```
deptmaster/
├── crates/
│   ├── domain/          ← NEW. Pure types. No I/O. No async. No DB. No FRB.
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── event.rs         (DomainEvent, EventData, AggregateType, EventDiscriminator)
│   │   │   ├── permission.rs    (Action, Resource, WalletRole, PermissionContext)
│   │   │   ├── projection.rs    (Contact, Transaction, Wallet, Currency, TransactionType, TransactionDirection)
│   │   │   ├── ids.rs           (WalletId, UserId, ContactId, TransactionId, EventId)
│   │   │   └── notification.rs  (NotificationKind, Notification — for the new stack)
│   │   └── Cargo.toml           (deps: serde, serde_json, uuid, chrono, thiserror — nothing else)
│   │
│   ├── debitum_event_replay/    ← NEW. Pure event-replay logic.
│   │   ├── src/lib.rs           (apply_event(state, event) -> state, exhaustive on EventData)
│   │   └── Cargo.toml           (deps: domain)
│   │
│   └── flutter_sdk/     ← MODIFIED. Adds domain + debitum_event_replay deps.
│
└── crates/server/            ← MODIFIED. Adds domain + debitum_event_replay deps.
                                     Removes its own copies of EventData, Action, Resource, etc.
```

Optionally add a workspace `Cargo.toml` at the root so the three crates share a target dir.

### What lives where

| Crate | Owns | Depends on |
|---|---|---|
| `domain` | Pure types only | serde, uuid, chrono, thiserror |
| `debitum_event_replay` | `apply(state, &event) -> state` | `domain` |
| `flutter_sdk` | SQLite storage, sync, FRB bridge, HTTP client | both above + rusqlite, reqwest, FRB |
| `crates/server` | Postgres, axum, HTTP handlers, projection cache | both above + sqlx, axum, tokio |

---

## Constraints check

### 1. Compile targets
- `domain` and `debitum_event_replay` must compile to: x86_64-unknown-linux-gnu (server), aarch64-apple-darwin / aarch64-linux-android (mobile), wasm32-unknown-unknown (frontend).
- All listed deps (serde, serde_json, uuid, chrono, thiserror) are wasm-clean. ✅

### 2. Flutter Rust Bridge
- FRB processes the *client* crate, not the shared crate.
- FRB-exportable items in `flutter_sdk` can re-export `domain` types via `pub use` (FRB v2 supports type re-exports).
- Risk: FRB type emission for tagged-enum (`EventData`) is more complex on the Dart side. May need to keep a flat "DTO" layer in `flutter_sdk` for FRB and convert to/from `domain::EventData` internally. Acceptable cost.

### 3. Async / runtime
- Pure types don't need async. ✅
- Replay logic is sync (`fn apply(state, event) -> state`). ✅

### 4. Serde wire format
- The server already uses `#[serde(tag = "type", rename_all = "snake_case")]` for `EventData`. The client currently uses untyped JSON. After the move, both serialize/deserialize the same way → no more shape divergence.

### 5. Database models
- *Projection structs* (Contact, Transaction) can be shared as pure structs.
- *Database rows* (with `#[derive(sqlx::FromRow)]` on the server, `rusqlite::Row::try_get` on the client) stay platform-specific.
- The conversion `DbRow -> Projection` lives in the platform-specific crate.

### 6. Permission model
- `Action`, `Resource`, `WalletRole`, `PermissionContext` are pure data → shareable.
- `PermissionModel` (with PgPool) stays on the server.
- The client gets the same enums for free → no more hardcoded `"contact:read"` strings.

---

## Migration steps (high level — not committing yet)

1. **Create `crates/domain`** with the pure types. Copy from backend, adapt where backend uses DB-specific decorators.
2. **Create `crates/debitum_event_replay`** with `apply(&mut Projection, &DomainEvent)`. Extract from server's `apply_event_batch_typed` handlers (we just wrote them in type-driven form — perfect timing).
3. **Add workspace `Cargo.toml`** at the project root so all three crates share `target/`.
4. **Backend migration:** swap backend's `domain::events`, `permissions::action`, `permissions::resource`, `permissions::context` for re-exports from `domain`. Keep the backend-specific glue (`apply_event_batch` becomes a thin wrapper that loads rows → calls `debitum_event_replay::apply` → writes back).
5. **Client migration:** swap client's `models.rs`, `state_builder.rs` for shared types + shared replay. Remove the hardcoded string event types.
6. **Run all tests both sides.** This should *expose* shape mismatches we've been ignoring (especially BUGS #8, #9).
7. **Add the `Notification` type to `domain`** so the notification stack from [[01-design-notes]] decision 2 is type-shared from day one.

---

## Risk assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| FRB can't export `#[serde(tag = "type")]` enum cleanly | Medium | Keep DTO layer in `flutter_sdk`, convert internally |
| Backend has subtle dependencies on `DomainEvent` having access to `wallet_id`/`user_id` that the client version doesn't need | Low | The fields are already aligned; verify by diffing the struct |
| Workspace Cargo refactor disrupts build scripts (`build.rs` in `frontend`, `cargo-wrap`) | Medium | Test workspace compile before committing; can also avoid workspace and use path deps |
| Cyclic git-history pain (huge diff) | Medium | Land in two PRs: (1) introduce shared crates with copies, no callers; (2) switch callers. Easy to bisect. |
| `chrono` version skew between backend (0.4.38) and client (0.4) | Low | Pin in workspace Cargo.toml |

**No identified blocker.**

---

## Decision needed

This is a multi-day refactor with a *very* high payoff. Recommendation: **do it now, before piling more fixes on top of the duplicated structure** — because every BUG fix we apply to one side risks drifting from the other. The current branch (`client/refactor-and-stabilize`) is the right place; we can land the shared crates first, then the bug fixes on top.

If the user agrees, the order becomes:

1. **First:** create the two shared crates with current backend types copied in. No caller changes yet. (1 commit)
2. **Then:** migrate backend to use them. Tests must still pass. (1 commit)
3. **Then:** migrate client to use them. This should make BUGS #8 and #9 disappear (UPDATED event shape will be the same struct). (1 commit)
4. **Then:** proceed with the remaining bug-cluster fixes (multi-app sync, permission visibility) from [[00-refactoring-plan]] Phase 3.

---

## Open questions for the user

1. **Workspace yes/no?** Adding a root `Cargo.toml` workspace is conventional and shares `target/`, but it touches every crate. Alternative: keep them independent with path deps.
2. **Should `frontend/` (Dioxus web) also depend on `domain`?** It currently has its own (untyped) view of events.
3. **FRB DTO layer:** are you OK with a thin DTO shell in `flutter_sdk` for the Dart bridge, with conversion to `domain` types internally? (Avoids FRB issues with serde-tagged enums on the Dart side.)
