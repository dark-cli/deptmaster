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

If the client and server ever disagree about what data exists in a wallet (e.g. client has events the server has never seen, or vice versa beyond what an incremental pull explains), the right resolution is **full flush + full re-pull**, not a partial merge. Server is the source of truth.

This already partially exists (`pull_and_merge` does a full pull when `local_count == 0` or when a permission event arrives). We should make it more general:
- After push, if the server's `event_count` for the wallet doesn't match what we expect (we sent N, server says it has M ≠ local M + N accepted), assume divergence → flush + re-pull
- Use the existing `/api/sync/hash` endpoint to detect divergence cheaply

---

## Cross-references

- [[00-overview]] — client architecture map
- [[00-refactoring-plan]] — what we're doing about all of this
- [[02-shared-domain-crate]] — the bigger structural question (share types with server)
- [[../client-todo]] · [[../backend-todo]]
