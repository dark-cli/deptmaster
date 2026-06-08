---
tags:
  - client
  - tests
  - baseline
---

# Client Integration Tests — Baseline 2026-06-08

First run of `crates/debitum_client_core` integration tests against a live backend on this branch.

**How to reproduce:**
```bash
# 1. Build backend
cd backend/rust-api && cargo build --bin debt-tracker-api

# 2. Start it (or use ./scripts/manage.sh start-server-direct, which blocks)
DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
PORT=8000 RUST_LOG=info JWT_SECRET=... JWT_EXPIRATION=3600 RATE_LIMIT_REQUESTS=0 \
  nohup ./target/debug/debt-tracker-api > /tmp/debt-tracker-api.log 2>&1 &

# 3. Run tests
cd crates/debitum_client_core
cargo test --test integration -- --ignored --test-threads=1
```

`--test-threads=1` is required: the client has process-wide thread-local state (storage, sync backoff) that breaks under parallelism.

---

## Result: 5 passing / 35 failing (40 total)

Up from 3 passing in the very first run (pre-fixes).

### Real bugs surfaced and fixed during this run

| # | Symptom | Cause | Fix | Commit |
|---|---|---|---|---|
| 1 | All tests fail at signup with `500 - "Failed to create account"` | `create_user_impl` was missing `last_event_id` in the INSERT, but the column is `NOT NULL` since migration 001 | Insert with sentinel `0` (same convention as `admin.rs:624` and `reset_password.rs:60`) | `ac0b41b` |
| 2 | After signup works, all push events fail with `400 Bad Request` and middleware warns `No wallet_id provided in request` | `wallet_context_middleware` was narrowed to extract `wallet_id` only from the path segment after `wallets/` — but `/api/sync/events` doesn't have that segment | Restore 3-source extraction (path → header → query); the old version was lost in commit `dfdaafa` | `ac0b41b` |

### Remaining failures (35)

Grouped by symptom from the post-fix run:

**A. `"No wallet selected"` (tests that use `signup` then immediately operate without `create_wallet`):**
- `single_app::single_app_signup_create_contact_and_sync`
- `single_app::single_app_many_events_then_assert`
- `single_app::single_app_many_contacts_and_transactions`
- `single_app::single_app_offline_*`
- `single_app::single_app_multiple_offline_creates_then_online_sync`

These tests call `AppInstance::signup()` (register-only by design — comment says "no wallet; then call create_wallet or select_wallet") and then immediately try to create contacts. They worked at some earlier point when `signup` auto-created a default wallet, or before "no wallet selected" was a hard error.

**Fix path:** either add `create_wallet(...)` after `signup()` in each test, or make `signup()` create a default wallet for these one-app tests. The latter is closer to the test author's intent based on the test names.

**B. Cross-app visibility — the actual BUGS.md territory:**
- `single_app::two_apps_sync_via_server` ("contact name 'Carol' not found; got []") — same as BUGS #1
- `multi_app_sync::*` (delete propagation, update propagation, etc.) — BUGS #10, #11
- `resync::*` — BUGS #2, #3
- `permissions::*` (member-sees-data-after-grant, give/take read, etc.) — BUGS #4–#7
- `groups::*` — BUGS #7, #12

These are the failures the original `BUGS.md` documented, now reachable end-to-end because the contract and signup are fixed.

**C. Workflow / unknown:**
- `conflict::*` — concurrent updates / update-delete resolution
- `comprehensive_events::*` — full lifecycle + per-type event audit (BUGS #8, #9)

---

## The 5 currently passing

Not enumerated by name in this snapshot (truncated output), but likely the `offline_online_multi_app::*` ones marked "skipped in Rust" plus any test that just exercises the auth path. The signal that matters: we're past the protocol-level failures and into the semantic ones.

---

## What this means

- Phase 0 (shared crate) is still the right structural play, but it won't fix the visibility bugs by itself — those have real causes (server-side filtering, replay handling, etc.) that need diagnosis.
- The "no wallet selected" cluster is the cheapest next win — a small test-helper / signup change probably moves 6+ tests from red to green.
- The cross-app visibility cluster is the highest-value next investigation, but each case needs its own root-cause analysis.

---

## Cross-references

- [[03-api-contract-audit]] — earlier audit that motivated the contract fix
- [[00-refactoring-plan]] — overall plan
- `crates/debitum_client_core/BUGS.md` — pre-existing bug catalog (mostly subsumed by cluster B above)
