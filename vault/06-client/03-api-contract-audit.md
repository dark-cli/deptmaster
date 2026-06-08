---
tags:
  - client
  - audit
  - critical
---

# Client/Server API Contract Audit

**Date:** 2026-06-08
**Branch:** `client/refactor-and-stabilize`
**Status:** 🔴 **CRITICAL FINDINGS** — the push-events path is broken at the protocol level. Every other endpoint matches.

---

## TL;DR

- **Auth endpoints** (`/api/auth/login`, `/api/auth/register`) — ✅ match.
- **Wallet management** (users, groups, members, permissions, invite, join) — ✅ paths and bodies match.
- **Pull events** (`GET /api/sync/events`) — ✅ matches.
- **Sync hash** (`GET /api/sync/hash`) — ✅ matches, but client doesn't use it yet.
- **WebSocket** (`/ws?token=…&wallet_id=…`) — ✅ matches.
- **🔴 PUSH EVENTS** (`POST /api/sync/events`) — **BROKEN.** Client sends a payload the server's `DomainEvent` deserializer **explicitly rejects**. Almost certainly the root cause of many sync bugs.

---

## 🔴 BROKEN: `POST /api/sync/events`

### What the client sends

`crates/debitum_client_core/src/sync.rs` lines 100-114:

```json
{
  "id": "<client-generated-uuid>",
  "aggregate_type": "contact",
  "aggregate_id": "<uuid>",
  "event_type": "CREATED",
  "event_data": { "name": "...", ... },
  "timestamp": "2026-06-08T10:00:00Z",
  "version": 1
}
```

### What the server expects

`backend/rust-api/src/domain/events.rs:262-301` (custom `Deserialize` for `DomainEvent`):

```json
{
  "aggregate_id": "<uuid>",
  "wallet_id": "<uuid>",
  "user_id": "<uuid>",
  "created_at": "2026-06-08T10:00:00Z",
  "version": 1,
  "idempotency_key": "<client-generated-string>",
  "event_data": {
    "type": "contact_created",   // ← tagged enum discriminator
    "name": "...",
    ...
  }
}
```

### Mismatches (every event the client pushes will fail to deserialize)

| Field | Client sends | Server expects | Result |
|---|---|---|---|
| `id` | sent (UUID) | **explicitly rejects if present** ("event_id must not be provided by client") | 🔴 deserialize error |
| `idempotency_key` | **not sent** | required | 🔴 deserialize error |
| `wallet_id` | **not sent** (only in query string + header) | required in body | 🔴 deserialize error |
| `user_id` | **not sent** | required in body | 🔴 deserialize error |
| `created_at` | sends `timestamp` instead | requires `created_at` | 🔴 deserialize error |
| `event_data` | raw object | requires `#[serde(tag = "type")]` enum with `"type": "contact_created"` etc. | 🔴 deserialize error |
| `aggregate_type` | sent | derived server-side from `EventData` variant | benign extra field |
| `event_type` | sent | derived server-side from `EventData` variant | benign extra field |

### What actually happens at runtime

1. Client `push_unsynced()` posts the payload above.
2. Axum extracts `Json(events): Json<Vec<DomainEvent>>` — this fails with 400 because the first event can't be deserialized.
3. Server returns the error body (which does **not** contain `DEBITUM_INSUFFICIENT_WALLET_PERMISSION`).
4. Client's error branch logs "sync failed (e.g. offline), keeping N local events for later sync" — **but the error wasn't network; it was a contract mismatch**. The events stay unsynced forever.
5. Multi-app tests then fail because App2 pulls and the server has nothing to give it (App1's push never landed).

This is consistent with most of `BUGS.md`:
- **BUGS #1, #10, #11** ("cross-app sees no contacts / fewer transactions") — App1's push silently failed, so the data never reached the server.
- **BUGS #4–#7** ("permission grant doesn't reveal data") — same root cause: owner's data never made it to the server, so granting a member read access reveals nothing.
- **BUGS #8, #9** ("no UPDATED event in event stream") — every UPDATED event the client emits gets rejected too.

### The fix

Rewrite `push_unsynced()`'s payload to match the server's `DomainEvent` shape:

```rust
let payload: Vec<serde_json::Value> = unsynced
    .iter()
    .map(|e| {
        let mut event_data: serde_json::Value =
            serde_json::from_str(&e.event_data).unwrap_or(serde_json::json!({}));
        // Inject the tagged-enum discriminator
        if let Some(obj) = event_data.as_object_mut() {
            obj.insert("type".into(), serde_json::json!(event_type_discriminator(&e)));
        }
        serde_json::json!({
            "aggregate_id":     e.aggregate_id,
            "wallet_id":        e.wallet_id,
            "user_id":          /* current user id */,
            "created_at":       e.timestamp,
            "version":          e.version,
            "idempotency_key":  e.idempotency_key,   // requires storage::StoredEvent to grow this column
            "event_data":       event_data,
        })
    })
    .collect();
```

Also: `event_type_discriminator` is the snake_case discriminator the server's `#[serde(tag = "type")]` expects (e.g. `"contact_created"`, `"transaction_updated"`). Once the shared `EventData` crate from [[02-shared-domain-crate]] exists, this becomes free (`event_data.event_type()` returns the right string).

### Why this strongly motivates Phase 0 (shared domain crate)

- The deserialize rejection is exactly what shared types prevent: client and server compile against the same `DomainEvent` struct, so the wire shape is guaranteed identical.
- The fix above is brittle (we're hand-building JSON the server expects); the shared-crate version is `serde_json::to_value(&domain_event)`.

### Response shape problem (separate)

The server returns:

```json
{
  "accepted": ["<server-generated-event-id-1>", ...],
  "conflicts": ["<server-generated-event-id-2>", ...]
}
```

Where the IDs are the *server-generated* `event_id`s (line 224 of `handlers/sync.rs`). The client uses these to mark local events as synced:

```rust
storage::events_mark_synced(&accepted)?;
```

But local events are keyed by the *client-generated* `id` (or, post-fix, by `idempotency_key`). The server's response IDs won't match → events would be re-pushed forever.

**The server should return `accepted: [{idempotency_key, event_id}, ...]`** so the client can:
1. Look up local events by `idempotency_key` (which both sides know)
2. Mark them synced, and
3. Store the server's `event_id` for future reference.

---

## ✅ Auth endpoints — match

| Client call | Backend route | Payload | Response | Status |
|---|---|---|---|---|
| `POST /api/auth/login` (`api.rs:50`) | `main.rs:128` | `{username, password}` | `{token, user_id, username}` | ✅ |
| `POST /api/auth/register` (`api.rs:74`) | `main.rs:130` | `{username, password}` | `{token, user_id, username}` | ✅ |

---

## ✅ Wallets — match

| Client call | Backend route | Notes |
|---|---|---|
| `GET /api/wallets` (`get_wallets_api`) | `main.rs:234` (`list_user_wallets`) | Client tolerates both `{wallets: [...]}` and bare array |
| `POST /api/wallets` (`create_wallet_api`) | `main.rs:234` (`create_my_wallet`) | Body `{name, description}` → server returns `{id, name, message}` ✓ |
| `POST /api/wallets/join` (`join_wallet_by_code_api`) | `main.rs:238` | Body `{code}` → `{wallet_id}` ✓ |

---

## ✅ Wallet management — paths match

All `/api/wallets/:wallet_id/...` paths in the client's `wallet_management_url()` exist on the server with matching verbs:

| Path | Client function | Server handler |
|---|---|---|
| `/users` (GET/POST) | `list_wallet_users_api`, `add_user_to_wallet_api` | `list_wallet_users`, `add_user_to_wallet` |
| `/users/search` | `search_wallet_users_api` | `search_wallet_users` |
| `/users/:user_id` (PUT/DELETE) | `update_wallet_user_api`, `remove_wallet_user_api` | `update_wallet_user`, `remove_user_from_wallet` |
| `/invite` (POST) | `create_wallet_invite_api` | `create_wallet_invite` |
| `/user-groups` (GET/POST) | `list_user_groups_api`, `create_user_group_api` | `list_user_groups`, `create_user_group` |
| `/user-groups/:id` (PUT/DELETE) | `update_user_group_api`, `delete_user_group_api` | `update_user_group`, `delete_user_group` |
| `/user-groups/:id/members` (GET/POST) | `list_user_group_members_api`, `add_user_group_member_api` | `list_user_group_members`, `add_user_group_member` |
| `/user-groups/:gid/members/:uid` (DELETE) | `remove_user_group_member_api` | `remove_user_group_member` |
| `/contact-groups` (...) | analogous | analogous |
| `/me/permissions` (GET) | `get_my_permissions_api` | `get_my_permissions` |
| `/permission-actions` (GET) | `list_permission_actions_api` | `list_permission_actions` |
| `/permission-matrix` (GET/PUT) | `get_permission_matrix_api`, `put_permission_matrix_api` | `get_permission_matrix`, `put_permission_matrix` |

### Minor observations

- `wallet_management_url` always appends `?wallet_id=...` to the URL even though the wallet_id is also in the path. Server middleware reads it from either; harmless redundancy.
- Client strips `/api/admin` suffix from base URL (`api.rs:172, 188, 215`) — looks like dead code from when the admin panel and user API shared a base URL.

---

## ✅ Sync hash and pull events — match

| Client | Server | Notes |
|---|---|---|
| (no client caller) | `GET /api/sync/hash` → `{hash, event_count, last_event_timestamp}` | **Endpoint exists, client doesn't use it yet.** Needed for Decision 3 (cache-conflict detection). |
| `GET /api/sync/events?since=…` (`get_sync_events`) | `GET /api/sync/events` → `Vec<SyncEvent>` | Server returns array of `{id, aggregate_type, aggregate_id, event_type, event_data, timestamp, version}` — client deserializes opportunistically. ✅ |

---

## ✅ WebSocket — matches

- Server: `/ws` with query `?token=…&wallet_id=…` (`main.rs` ws_routes section).
- Client: `mobile/lib/api.dart:1083-1086` connects to `ws[s]://host:port/ws?token=…&wallet_id=…`.

---

## Action items

1. **🔴 BLOCKER: fix the push payload shape.** Cannot run end-to-end client tests until this is fixed. See task #15 (idempotency_key) — same root cause; merge them.
2. **🔴 BLOCKER: fix the response handling.** Server should return `accepted: [{idempotency_key, event_id}]` (not just event_ids); client needs `idempotency_key` to look up local events. This is a backend change too.
3. **🟡 Wire up `/api/sync/hash`.** Needed for Decision 3 (push-then-flush-then-rebuild on cache divergence).
4. **🟢 Clean up `/api/admin` strip-suffix dead code** in `api.rs:172, 188, 215`.
5. **🔥 Hard motivation for Phase 0 (shared domain crate).** The push contract mismatch is the textbook case the shared crate fixes structurally.

---

## How to verify the fix works (once applied)

A single integration test should be enough:

```rust
// pseudo
let app1 = App::login_or_create(...);
app1.create_contact("Carol")?;
app1.sync()?;
// Right now: client returns Ok but the events.count on the server is 0.
// After fix: events.count on the server is 1, the event has the expected idempotency_key,
// and a second app loading the wallet sees "Carol".
```

If this passes, `BUGS.md` #1, #2, #3, #4, #5, #6, #7, #10, #11 should *all* pass without further work. That's how confident we should be that this is the root cause.

---

## Cross-references

- [[01-design-notes]] Decision 1 (drop client perms diff) — orthogonal but also touches `sync.rs`
- [[02-shared-domain-crate]] — the structural fix that prevents this class of bug
- [[00-refactoring-plan]] Phase 0 — the shared-crate work that would have caught this at compile time
- [[../client-todo]] HIGH PRIORITY → idempotency_key task already documents this from the client side
- `crates/debitum_client_core/BUGS.md` — most entries trace to the push contract mismatch
