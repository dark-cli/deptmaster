---
tags:
  - client
  - tests
  - baseline
---

# Client Integration Tests — Baseline 2026-06-08

Series of fixes that landed today against the integration tests in
`crates/flutter_sdk/tests/`. All run against a live backend via the
single `integration` test binary; per-file binaries are disabled
(`autotests = false`) since they're just modules of `integration.rs`.

**2026-06-08 snapshot: 22/40 passing (55%)** — over the >50% goal.
**2026-06-10 baseline: 45/47 passing under nextest (~29s vs ~177s sequential).**
See "Run instructions" below for the standard workflow.

---

## Run instructions

**Always use `cargo-nextest`.** Each test runs in its own process, parallel
across CPU cores. ~6x faster than `cargo test --test-threads=1` AND eliminates
the shared-SQLite-globals contamination that drove most of the sequential-run
flakiness. `scripts/manage.sh test-integration` enforces this — there's no
fallback to `cargo test`.

```bash
# One-time install if you don't have it
cargo install cargo-nextest --locked

# 1. Start the backend (scripts/run-server-dev.sh sets the high rate limit
#    the parallel runner needs)
./scripts/run-server-dev.sh

# 2. Run the suite
./scripts/manage.sh test-integration
# or directly:
cd crates/flutter_sdk && cargo nextest run --run-ignored all --no-fail-fast
```

The dev server defaults `RATE_LIMIT_REQUESTS=100000`. The production default
(100/min) blocks the parallel runner immediately — if you see `429 Too Many
Requests` in test failures, the rate limit is the cause, not your code.

---

## Progression

| Stage | Pass | Fail | Note |
|---:|---:|---:|---|
| Start (this session) | 3 | 37 | All blocked at `signup` 500 (`last_event_id` regression) |
| After signup fix | 5 | 35 | `signup` works; all push events now blocked at 400 (middleware refused) |
| After wrong middleware "fix" + route-move + revert | 5 | 35 | Same count, but for the right reason (signup auto-creates a wallet now misses) |
| After signup auto-creates wallet | 8 | 32 | Single-app signup-then-CRUD tests unblock |
| After client pull no longer destroys local on first sync | 13 | 27 | Single-app suite mostly green (7/8) |
| **After server applies projections before populating readable cache** | **22** | **18** | **Multi-app same-user sync works** |

---

## Real bugs fixed in this session

| # | Symptom | Root cause | Fix | Commit |
|---|---|---|---|---|
| 1 | `register` → 500 on every signup | `create_user_impl` skipped `last_event_id` in INSERT; column is NOT NULL since migration 001 | Insert with sentinel `0` | `ac0b41b` |
| 2 | Push events fail with 400, middleware warns "No wallet_id" | `/api/sync/events` was mounted under wallet middleware but its path didn't contain `wallets/`; middleware reads from path only by design | Move routes to `/api/wallets/:wallet_id/sync/...` and update client URLs accordingly | `dfee556` + part of `94b611b` |
| 3 | After single-app push+sync, next sync deletes the just-pushed event | `pull_and_merge` did destructive `delete_all_for_wallet` whenever `last_sync_timestamp` was None, even if local had data. Race-prone | Only delete on truly empty wallet; always advance `last_sync_timestamp` to "now" even when server returned 0 events | part of `94b611b` |
| 4 | Multi-app: server accepts push but returns 0 events on pull, even for the wallet owner | `post_sync_events` called `populate_events_cache_after_sync` BEFORE `apply_events_batch` — the readable-cache check queries `contacts_projection` which didn't yet reflect the new event | Reorder: apply projections first, then populate cache | `a4cbf74` |

---

## Architectural decisions enforced (durable, see memory)

- **wallet_id is path-only.** Every wallet-scoped route has `:wallet_id` in its URL. No fallback to header or query. The middleware was deliberately narrowed; do not undo that.
- **Client tests stay in client scope.** Tests assert what the client sends and what it receives. No "get from server" helpers, no peeking at backend state. Server-state assertions belong in backend tests. Removed `get_contacts_from_server` and rewrote its two usages to be `manual_sync()` + `get_contacts()` (assert on local state after a normal sync — same path production uses).
- **BUGS.md is stale.** Written against `main`'s old backend. We are NOT mapping current failures to BUGS entries.

---

## What's still failing (18 tests)

All in multi-app permission/group flows. Concentrated:

- **11 permissions tests** — read grant/revoke, group-based access, deny-overrides-allow, etc.
- **3 comprehensive_events tests** — full-lifecycle and concurrent-mixed scenarios
- **1 conflict** — `conflict_update_delete_resolution`
- **1 multi_app_sync** — `multi_app_delete_propagation`
- **2 resync** — full + incremental resync

These need investigation of permission resolution semantics (matrix expansion, group membership across the readable_contacts query) and the delete/UNDO propagation. They were NOT addressed in this session — the >50% goal was met by fixing structural issues (auth flow, contract, sync logic, cache ordering) that affected many tests at once.

---

## Where this leaves us

The baseline is now stable and high enough to start the shared-domain-crate refactor ([[02-shared-domain-crate]]) without losing test signal. Phase 0 of [[00-refactoring-plan]] can begin. The remaining 18 failures are best diagnosed AFTER Phase 0 — many of them likely simplify or auto-resolve once the client and server use the same `EventData` enum.

---

## Cross-references

- [[03-api-contract-audit]] — contract analysis that motivated the session
- [[00-refactoring-plan]] — Phase 0 (shared crate) is the right next move
- [[01-design-notes]] — three decisions taken during the audit
