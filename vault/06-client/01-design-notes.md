---
tags:
  - client
  - design
  - notes
---

# Client Design Notes

Running notes captured during the client refactoring discussions. Decisions made here feed into the implementation work in [[00-refactoring-plan]].

---

## Decision 1: Permissions on the client — what stays, what goes

**Context:** `sync.rs::check_read_revoked_and_resync` polls `get_my_permissions_api` on every full_sync, diffs against a cached set in `perms_cache_{wallet_id}`, and decides on its own whether to clear local data and re-pull. This is duplicating server work and is likely the root cause of BUGS #4–#7 (members not seeing data they're allowed to see).

**Decision:** Keep client permissions only for UI guards (e.g. don't render a Delete button for a read-only user). **Drop** the read-revoke / read-grant diff logic entirely. The server is authoritative — it owns the `user_readable_events` cache and the permission matrix; it returns exactly the events the user can see.

**Action items:**
- Remove `READ_ACTIONS`, `perms_cache_key`, `check_read_revoked_and_resync`, `clear_wallet_and_resync`, `invalidate_perms_cache_and_pull` from `sync.rs`
- Keep `get_my_permissions_api` (UI still needs it for affordances)
- Keep `get_permission_matrix_api` / `put_permission_matrix_api` (admin matrix editor)
- The existing "if pull batch contains permission events, force full pull" path in `pull_and_merge` (line 184) is the correct trigger and is sufficient

**Risk:** the backend `user_readable_events` cache must be populated before the client's next pull. If it isn't, the bug surfaces server-side where it belongs — not papered over on the client.

**Why this is safe:** the server enforces permissions on every request; the client's local check was never a security boundary, only an optimization (and a buggy one).

---

## Decision 2: Server-side notification stack for offline clients

**Problem we want to solve:** Today the client only knows to resync when:
1. It calls `full_sync` and pulls some events, or
2. The WebSocket is connected and a `events_synced` broadcast arrives

If a client is **offline** when something happens (permission change, contact deleted by another app, etc.), it has no way to find out *what* changed once it comes back online — it can only do a blind incremental pull and hope the events are visible.

**Proposed design: a notification stack on the server**

A per-user queue of typed notifications that:
- Survives the user being offline (rows in a `user_notifications` table)
- Is drained when the client polls `/api/notifications` (or on next sync)
- Carries enough payload for the client to know *what to do*, not just *that something happened*

**Notification types (initial set):**

| Type | Payload | Client should... |
|---|---|---|
| `permission_changed` | `{wallet_id}` | clear & full re-pull that wallet |
| `wallet_membership_changed` | `{wallet_id, change: "added"\|"removed"}` | refresh wallet list; clear if removed |
| `contact_group_membership_changed` | `{wallet_id}` | full re-pull (visible contact set may have changed) |
| `wallet_deleted` | `{wallet_id}` | drop local copy |

**Delivery:**
- WebSocket pushes notifications in real-time when connected
- HTTP `GET /api/notifications?since=<id>` drains on reconnect / app launch
- Server marks notifications as delivered when the client ACKs (or auto-expires after N days)

**Why this beats the current "client polls permission diff" approach:**
- Server knows *exactly* what changed and *for whom* (it processed the event)
- Client gets a specific instruction (`clear wallet X and re-pull`) instead of having to figure it out
- Works equally well online and offline
- Generalizes to other future changes (e.g. user account flags, billing state)

**Status:** proposal — not implemented. Would be a backend addition (new table, new endpoint, new WebSocket message); client side becomes a notification handler instead of the current polling/diff code.

**Action items:**
- Backend: new migration for `user_notifications` table (`id`, `user_id`, `kind`, `payload`, `created_at`, `delivered_at`)
- Backend: helper to emit notifications when relevant events are processed (hook into permission event handlers in [[../04-permissions-and-undo/04-permission-matrix-cache]])
- Backend: `GET /api/notifications` endpoint, WebSocket message type
- Client: notification consumer that maps `kind` to action (clear+pull, drop wallet, etc.)
- Both: add to [[../backend-todo]] and [[../client-todo]]

---

## Decision 3: Cache-conflict full-flush

If the client and server disagree about what data exists in a wallet (e.g. hash mismatch on `/api/sync/hash`, or after-push counts don't reconcile), the right resolution is **push-then-flush-then-rebuild**:

1. **Push first.** The client may have unsynced events from when it was offline; those must reach the server before we throw away local state. (`storage::events_get_unsynced` → `push_unsynced`.)
2. **Flush local data.** Drop the projection and events for this wallet (`storage::events_delete_all_for_wallet`, projection clear).
3. **Full re-pull and rebuild.** `pull_and_merge` with `since=None` so the server returns the full visible-to-this-user event set; replay them locally to rebuild the projection.

This preserves offline work (step 1) while still treating the server as source of truth (steps 2–3).

**Why not just merge?** Partial merges have to reason about ordering, idempotency, and what to do with events the client has but the server doesn't. After a push, the server is definitively up to date with the user's intent; a full pull then gives exactly the right state. Cheaper to throw away local state and rebuild than to write merge logic that handles every divergence case.

**What already exists:**
- `pull_and_merge` does a full pull when `local_count == 0` or when a permission event arrives in the batch — these paths skip step 1 because there's nothing to push or because permission changes warrant a clean slate.

**What to add:**
- After push completes, compare server's wallet hash to local hash via `/api/sync/hash`. On mismatch → run the flush + re-pull path.
- Same trigger on app startup if last sync was long ago or the device was offline.

---

## Cross-references
## Decision 4: Share `DomainEvent`, permission model, and projection types between client and server

**Short answer: yes — and we should do it before any more bug fixes, because most of the bugs in `BUGS.md` exist precisely because client and server can't compile against the same shape.**

Full proposal with crate layout, constraint analysis, FRB compatibility, migration steps, and risk table: [[02-shared-domain-crate]].

### What can be shared
- `EventData` enum (28 variants), `DomainEvent`, `AggregateType`, `EventDiscriminator`
- `Action`, `Resource`, `WalletRole`, `PermissionContext` (pure data, no DB)
- Projection types: `Contact`, `Transaction`, `Wallet`, `Currency`, `TransactionType`, `TransactionDirection`
- Typed IDs (`WalletId`, `ContactId`, …)
- Event-replay *logic* (`apply(state, event) -> state`) — server-side `apply_event_batch_typed` and client-side `state_builder` are doing the same job twice

### What can't (and shouldn't try to)
- `sqlx::PgRow` parsing / `rusqlite` storage — different DBs, but the conversion target (the projection struct) is shared
- `axum` handlers / `reqwest` client / `flutter_rust_bridge` exports — platform glue
- DB connection pools, tokio runtime choice

### Proposed structure

```
crates/
  debitum_domain/         ← NEW: pure types (serde, uuid, chrono only)
  debitum_event_replay/   ← NEW: apply(state, event) — used by both sides
  debitum_client_core/    ← uses the two above
backend/rust-api/         ← uses the two above
```

### Why do it NOW (before more bug fixes)

- We just refactored the server to use type-driven dispatch (`apply_event_batch_typed`). That logic is *exactly* what the client needs. If we share it, the client and server can't disagree.
- BUGS #8 and #9 (UPDATED events not visible) would likely disappear — currently the client emits an event the server doesn't recognise as UPDATED. Shared `EventData` enum makes that impossible.
- Every fix we apply now risks drifting from the other side. Sharing first means fixes apply once.

### Order of execution

1. Create the two shared crates with backend types copied in (no callers touched yet)
2. Migrate backend to use them — tests must still pass
3. Migrate client to use them — this alone should kill some bugs
4. Then proceed with the rest of [[00-refactoring-plan]] Phase 3 (multi-app sync, permission visibility)

### Open questions for the user

1. **Workspace `Cargo.toml`** at the root, or keep crates independent with path deps?
2. Should `frontend/` (the Dioxus web crate) also depend on `debitum_domain`?
3. Are you OK with a thin DTO shell in `debitum_client_core` for FRB ↔ Dart (to avoid FRB issues with serde-tagged enums)?

---


- [[00-overview]] — client architecture map
- [[00-refactoring-plan]] — what we're doing about all of this
- [[02-shared-domain-crate]] — the bigger structural question (share types with server)
- [[../client-todo]] · [[../backend-todo]]
