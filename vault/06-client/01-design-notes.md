---
tags:
  - client
  - design
  - notes
---

# Client Design Notes

Architectural decisions captured during the client refactor and their status. Sections in chronological order; the most recent decisions sit at the end.

---

## Decision 1: Permissions on the client — what stays, what goes

**Status:** ✅ Implemented

**Context:** Old code (`sync.rs::check_read_revoked_and_resync`) polled `get_my_permissions_api` on every full_sync, diffed against a cached set, and decided on its own whether to clear local data and re-pull. This duplicated server work and was the root cause of multi-app visibility bugs.

**Decision:** Keep client permissions only for UI affordances. **Drop** the read-revoke / read-grant diff logic. The server is authoritative — it owns the `user_readable_events` cache and the permission matrix; it returns exactly the events the user can see.

**What landed:**
- `READ_ACTIONS`, `perms_cache_key`, `check_read_revoked_and_resync`, `clear_wallet_and_resync`, `invalidate_perms_cache_and_pull` removed from `sync.rs`
- Server's `/api/sync/hash` is now the divergence-detection mechanism (one byte to compare instead of a perms diff)
- Client kept: `get_my_permissions_api` (still used for affordances), permission matrix admin endpoints

**Why this is safe:** the server enforces permissions on every request; the client's local check was never a security boundary, only an optimization.

---

## Decision 2: Server-side notification stack for offline clients

**Status:** 🟡 Proposed — not implemented

**Problem we want to solve:** Today the client only knows to resync when it calls `full_sync` and pulls events, or the WebSocket pushes an `events_synced` broadcast. An offline client coming back online has to do a blind incremental pull and hope the events are visible.

**Proposed design:** A per-user `user_notifications` queue on the server. Survives offline (rows in a table), drained on poll/WS reconnect, carries typed payloads so the client knows *what to do* — not just *that something changed*.

**Notification types (initial set):**

| Type | Payload | Client should... |
|---|---|---|
| `permission_changed` | `{wallet_id}` | clear & full re-pull that wallet |
| `wallet_membership_changed` | `{wallet_id, change}` | refresh wallet list; clear if removed |
| `contact_group_membership_changed` | `{wallet_id}` | full re-pull |
| `wallet_deleted` | `{wallet_id}` | drop local copy |

Backend additions needed: migration for `user_notifications`, helper to emit on relevant events, `GET /api/notifications` endpoint, WebSocket message type. Client side becomes a notification handler instead of polling.

Tracked in [[../backend-todo]].

---

## Decision 3: Cache-conflict full-flush

**Status:** ✅ Implemented (via hash-divergence path)

If the client and server disagree about what data exists in a wallet, the resolution is **push-then-flush-then-rebuild**:

1. **Push first.** The client may have unsynced events; those must reach the server before we throw away local state.
2. **Flush local data.** Drop the projection and events for this wallet (`storage::events_delete_all_for_wallet`).
3. **Full re-pull and rebuild.** `pull_and_merge` with `since=None`; replay locally.

This preserves offline work (step 1) while still treating the server as source of truth (steps 2–3).

**Trigger:** server hash mismatch on next pull. Client stashes the server's hash after every successful sync (in `config: server_hash_<wallet_id>`); the next pull compares.

---

## Decision 4: Share `DomainEvent`, permission model, and projection types between client and server

**Status:** ✅ Implemented (Phase 0 + convergence steps 1-5)

**Original short answer:** yes — and we should do it before any more bug fixes, because most of the bugs were down to client and server not compiling against the same shape.

**What landed (`crates/core/`):**

| Crate | Owns |
|---|---|
| `domain` | `DomainEvent`, `EventData` (28 variants), `Action`, `Resource`, typed IDs, `PermissionContext` |
| `applier` | `Projection` trait + `apply()` dispatch — exhaustive match over all 28 `EventData` variants |
| `resolver` | `PermissionStore` trait + pure-Rust `resolve_actions` / `permitted_contacts_for_action` |
| `snapshots` | `SnapshotStore` trait + rotation + `should_create_snapshot` + UNDO predicates |

Each side implements the three storage traits against its own engine (Postgres + sqlx server-side, SQLite + rusqlite client-side). The rules layer doesn't know the engine exists.

**Architectural payoffs:**
- Multi-app visibility bugs traced to client/server divergence are now structurally impossible: same enum, same dispatch
- `can_perform` works locally on the client because the resolver crate is the resolver crate, period
- UNDO predicate is a constant in one crate; both sides import it

**What's still per-side and legitimately so:**
- Storage engine (sqlx/Postgres ↔ rusqlite/SQLite)
- Authority (server enforces; client advises)
- Server's deep rollback path (`projections.rs` Phase-1/3 event-window dance + `event_id_to_position` map) — not refactored to share with the client's simpler `rebuild_projection_tables`. Worth its own dedicated commit.

---

## Decision 5: SDK soft-delete + wallet_owners + snapshots table parity

**Status:** ✅ Implemented (convergence steps 1-3)

The SDK schema was drifting from the server. We brought it back in line:

- **Soft delete:** `contacts.is_deleted` and `transactions.is_deleted` columns; `soft_delete_*` projection methods UPDATE the flag instead of DELETEing. Server semantics.
- **`wallet_owners` table:** explicit ownership. `SdkProjection::upsert_wallet_user` dual-writes when role='owner'. `is_wallet_owner` reads from `wallet_owners` (same SQL shape as server).
- **`projection_snapshots` table:** mirrors server's schema; one legitimate diff (TEXT `last_event_id` for UUIDs vs server's BIGINT for BIGSERIAL).

After this, the only schema divergences left are the unavoidable SQLite ↔ Postgres ones (column types, JSON storage as TEXT, etc.).

---

## Cross-references

- [[00-overview]] — current client architecture
- [[../00-getting-started/04-main-architecture]] — system-level event-sourcing flow
- [[../client-todo]] · [[../backend-todo]]
