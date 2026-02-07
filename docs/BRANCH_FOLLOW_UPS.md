# Branch follow-ups (feature/multi-wallet-system and later)

List of items to do in this branch or in dedicated branches later.

---

## 1. Done in this branch

- **Backend host rename**: Committed (use "host" instead of "IP" in setup and settings).
- **.gitignore**: Added `mobile/android/app/src/main/jniLibs/`, `**/*.so`, `**/*.a`, `**/*.dylib` so build artifacts are not committed; no tracked build files were removed (none were in the repo).
- **Auth when online**: When the app comes online (WebSocket connects), we call `validateAuth()`. If the server returns 401/expired, the client logs out and cleans up (token/config cleared in Rust; `onLogout` in Flutter). So "check login when we get online" is done.
- **Scheduler TODO**: Clarified in code: the backend scheduler’s daily job is for *server-side* cleanup (e.g. old projection snapshots), not app login. App logout/cleanup is in the client (logout clears token, user_id, current_wallet_id, last_sync_timestamp). Optional: implement actual cleanup logic in the cron job later (e.g. prune old `projection_snapshots`).

---

## 2. Login / server-declined auth (like permissions)

- **Goal**: Have the server declare "login declined" in a clear, unambiguous way (similar to `DEBITUM_INSUFFICIENT_WALLET_PERMISSION` for permissions), so the app never misinterprets network errors as "logged out".
- **Possible approach**: Backend returns a specific error code or body for 401 (e.g. `DEBITUM_AUTH_DECLINED` or `DEBITUM_SESSION_EXPIRED`) so the client only logs out and cleans data when it sees that code.
- **On logout / login declined**: Already today, Rust `logout()` clears token, user_id, current_wallet_id, last_sync_timestamp. Optional: also clear local event/contact/transaction storage so the next user sees no prior user data (could be a separate "clear storage on logout" in Rust).

---

## 3. Backend scheduler cleanup (optional)

- **What it is**: `backend/rust-api/src/background/scheduler.rs` runs a daily cron at 2 AM. The job body is currently a no-op.
- **"Cleanup" meaning**: Server-side only (e.g. prune old `projection_snapshots`, old logs). Not required for multi-wallet; can be implemented later when needed.
- **Not**: App-side cleanup on login/logout; that is handled in the client (see above).

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
| Server-declared login declined (like permissions) | To do (later) |
| Clear data on logout (beyond token) | Optional (e.g. clear local DB) |
| Testing updates | Later branch |
| Docs updates | Later branch |
| List of follow-ups | This file |
