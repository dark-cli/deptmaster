# Branch follow-ups (feature/multi-wallet-system and later)

List of items to do in this branch or in dedicated branches later.

---

## 1. Done in this branch

- **Backend host rename**: Committed (use "host" instead of "IP" in setup and settings).
- **.gitignore**: Added `mobile/android/app/src/main/jniLibs/`, `**/*.so`, `**/*.a`, `**/*.dylib` so build artifacts are not committed; no tracked build files were removed (none were in the repo).
- **Auth when online**: When the app comes online we call `validateAuth()` (Rust `manual_sync`). If the server responds with `DEBITUM_AUTH_DECLINED`, Rust performs logout/cleanup and returns that error; Dart only calls `onLogout` for UI. No auth/logout logic in Dart.
- **Scheduler TODO**: Clarified in code: the backend scheduler’s daily job is for *server-side* cleanup (e.g. old projection snapshots), not app login. App logout/cleanup is in the client (logout clears token, user_id, current_wallet_id, last_sync_timestamp). Optional: implement actual cleanup logic in the cron job later (e.g. prune old `projection_snapshots`).

---

## 2. Login / server-declined auth (like permissions) — DONE

- **Server**: All 401 responses (auth middleware, login handler) now include `{"code": "DEBITUM_AUTH_DECLINED", "message": "..."}` so the client only treats auth as declined when it sees that code (not on generic 401 or network errors).
- **Rust**: Login, get_sync_events, post_sync_events detect `DEBITUM_AUTH_DECLINED` in response body and return that error. `manual_sync` on that error calls `crud::logout()` (cleanup). All login, logout, check-login, and cleanup logic live in Rust.
- **Dart**: Only reacts: if `validateAuth()` throws with `DEBITUM_AUTH_DECLINED`, Dart calls `onLogout()` for UI (navigate to login). Dart does not call `rust.logout()` or interpret 401/expired.
- **Optional**: Clear local event/contact/transaction storage on logout in Rust (so next user sees no prior data).

---

## 3. Backend scheduler & projection_snapshots

- **projection_snapshots are wallet-bound**: Table has `wallet_id`; all operations (save, get, cleanup) are scoped by `wallet_id`. We do not do "whole database" snapshot cleanup.
- **No separate cleanup job needed**: Snapshots are a capped stack per wallet. When we save a new snapshot we call `cleanup_old_snapshots(pool, wallet_id)`, which keeps only the last `MAX_SNAPSHOTS` (5) for that wallet. So we never exceed the limit; no daily cron is required for snapshots.
- **Scheduler**: The daily job at 2 AM is a no-op placeholder. It does not clean projection_snapshots; that is already done inline per wallet on save.
- **Migration 013**: `013_projection_snapshots_wallet_unique.sql` — TRUNCATE snapshots, then add `UNIQUE(wallet_id, snapshot_index)` and `wallet_id NOT NULL`. Dev-only; data is dummy, wipe/re-import via manager.sh if needed.

---

## 4. Testing branch (later)

- Create a branch to update tests (integration, backend tests with TODOs/todo!, etc.).
- Many backend test files still have TODO placeholders (e.g. `transaction_handlers_test.rs`, `integration_test.rs`).

---

## 5. Docs branch (later)

- Many docs and plans (e.g. `MULTI_WALLET_SYSTEM_PLAN.md`, `ARCHITECTURE.md`) are out of date after multi-wallet and recent changes.
- Create a branch to refresh docs: update checkboxes, merge strategy note, and any architecture/flow descriptions.

---

## 6. Other TODOs (backlog)

- **Backend** `handlers/wallets.rs`: "TODO: Get user_id from auth middleware" (if still relevant).
- **Backend** `background/scheduler.rs`: Optional implementation of daily cleanup logic (e.g. snapshot pruning).
- **Docs** `ARCHITECTURE.md`: "Client handles conflicts (currently logged, merge strategy TODO)".
- **Frontend (other stack)** `login.rs` / `backend_setup.rs`: TODOs there are outside the current mobile/Rust backend scope.

---

## Summary checklist

| Item | Status / Branch |
|------|------------------|
| Commit uncommitted (host rename) | Done |
| .gitignore + no tracked build artifacts | Done |
| Scheduler: required or old? | Clarified: optional server cleanup, not login |
| Login check when online | Done (validateAuth on connect) |
| Server-declared login declined (DEBITUM_AUTH_DECLINED) | Done |
| projection_snapshots wallet-scoped + migration 013 | Done |
| Clear data on logout (beyond token) | Optional (e.g. clear local DB) |
| Testing updates | Later branch |
| Docs updates | Later branch |
| List of follow-ups | This file |
