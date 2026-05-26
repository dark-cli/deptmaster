# Sync Architecture and Current Issues

## 1. What’s actually going on (current issues)

### Integration tests
- **Admin API**: Tests create users/wallets via admin API. The helper was using regular login instead of `/api/auth/admin/login`, so create user often failed (403). That’s fixed (admin login + 429 retry).
- **Rate limiting (429)**: When the full suite runs, many requests hit the server in a short time. The server returns 429. We added retries and small delays in the test helper to reduce flakiness, but that’s a workaround, not a fix of the app design.
- **Manual sync in tests**: We added `app1!.sync()` in server-side tests so that after creating events we “push and pull” before asserting on server state. That papers over a design question: **the client is supposed to push after each event** (see below). If the app did that reliably, tests wouldn’t need to call sync just to get events onto the server.

### App behavior
- **“App only fetches wallet names”**:  
  - **Wallets**: Fetched from the server via HTTP (`GET /api/wallets`).  
  - **Contacts and transactions**: **Not** fetched by a dedicated “get from server” call. They are read from **local state** only (`get_contacts()` / `get_events()` → `state_load()` / events from local DB).  
  - So the only way server data becomes visible in the app is when **pull** runs (see below). If pull never runs or always fails, the UI only shows what’s already in local state (often empty).
- **No Rust output in the app**:  
  - Rust uses `eprintln!()` for debug/warn/error.  
  - On Flutter (Linux/Android/iOS), native stderr is usually **not** wired to the Dart debug console, so you don’t see those messages in the IDE.  
  - So yes, it’s concerning: we have no visibility into Rust logs or errors from the app, and failures can be silent.

---

## 2. Should we “baby” the client with manual sync in tests?

**Short answer: No. The Rust client is already designed to push after each event. We shouldn’t need to call manual sync in tests just to get events onto the server.**

### What the Rust client does today

- **After every CRUD** (create contact, create transaction, update, delete, undo):
  - It appends an event locally and calls `rebuild_and_save(wallet_id)`.
  - `rebuild_and_save` does:
    - Rebuild in-memory state from events.
    - Save that state locally.
    - **`sync::push_unsynced()`** → sends unsynced events to the server and marks them synced.

So **each event is pushed to the server as part of the same CRUD call**. There is no “only write locally and never push until someone calls sync.”

- **Pull** (getting server data into local state) only happens when:
  - `manual_sync()` is called (which does `push_unsynced()` then `pull_and_merge()`), or
  - Some other code path calls `pull_and_merge()` (e.g. future realtime handling).

So:
- **Push**: Automatic after each event in the Rust client; no need for tests to call sync just to “push.”
- **Pull**: Only on `manual_sync()` (or equivalent). So the app **does** depend on something triggering a full sync (e.g. startup, or realtime) to ever show server-origin data.

If tests still need `app1!.sync()` before asserting on the server, the likely reasons are:
1. **Push is failing** (e.g. network, auth, or error not surfaced), so events never reach the server until we force a sync.
2. **Test double-checks server state** after a pull; then sync is needed to run pull, not to “make push happen.”

So the right direction is: **rely on the backend (Rust client) to push after each event; fix any place where push fails silently; and only use manual sync in tests where we explicitly want to pull and then assert on server state.**

---

## 3. App “doesn’t fetch data” and no Rust prints — is that concerning?

**Yes. Both are concerning.**

### “App doesn’t fetch data (except wallet names)”

- **Wallets**: Fetched from server (HTTP).
- **Contacts / transactions / events**: Always read from **local storage**. They are never fetched by a separate “GET contacts/events” API; they come from state built from the **local event store**.
- That local state is updated from the server **only when** `pull_and_merge()` runs, which today is only when `manual_sync()` is invoked (e.g. from Dart `Api.manualSync()`).
- So if:
  - `manualSync()` is never called after login/wallet selection, or
  - it’s called but fails (e.g. no token, no wallet, network error), and the error is swallowed (e.g. `catch (_) {}` in `main.dart`),

then **pull never succeeds**, local state stays empty, and the app shows no contacts/transactions even though the server might have data. So the app effectively “doesn’t fetch” that data because the only path that fills it (pull) isn’t running or is failing silently.

### No Rust debug / warning / error in the app

- Rust uses `eprintln!()`; that goes to **stderr** of the native process.
- Flutter does not automatically show native stderr in the Dart debug console, so you see no Rust logs in the IDE.
- Consequences:
  - Sync failures (push or pull) can be invisible.
  - We can’t see the existing `[debitum_rs]` debug lines (e.g. in `sync.rs`, `lib.rs`, `crud.rs`) when running the app.
  - Harder to diagnose “app doesn’t fetch data” and other sync issues.

So yes: **both the “no fetch” behavior and the lack of Rust logs are concerning** and worth fixing (see next section).

---

## Recommended next steps

1. **Rust logging in the app**
   - Add a way to send Rust logs to Dart (e.g. a callback from Rust to Dart that calls `debugPrint`), or use a crate that integrates with the platform’s logging, so that Rust errors and `[debitum_rs]` messages appear in the Flutter console.

2. **Ensure initial pull runs and errors are visible**
   - In `main.dart`, after login and wallet selection, ensure `manualSync()` is called (it already is) but **do not** swallow errors silently: at least log them (e.g. `debugPrint` or a user-visible message) so we know when pull fails.
   - Optionally: if `manualSync()` fails, show a non-blocking hint (“Sync failed; data may be outdated”) so we don’t have a silent “no data” state.

3. **Tests**
   - Remove or reduce reliance on “baby” manual sync in tests where the only goal is “events are on the server.” If the client pushes after each event, those tests should pass without an extra sync, unless we confirm push is failing (then fix push instead of papering over with sync).
   - Keep explicit sync only where the test intentionally does a full sync and then asserts on server or local state after pull.

4. **Rate limiting**
   - For local/dev, consider higher limits or exempting certain paths so the full integration suite doesn’t depend on 429 retries.

---

## Implemented (recommended steps)

- **Rust → Dart logging**: `log_bridge.rs` buffers log lines; `drain_rust_logs()` returns them. Dart calls it after `manualSync()` and on startup failure and forwards lines to `debugPrint`. Use `rust_log!` in the Rust crate instead of `eprintln!`.
- **main.dart**: `manualSync()` failures are logged with `debugPrint` and Rust logs are drained so errors are visible.
- **Tests**: Server-side scenario `app1!.sync()` calls are **required** (push then assert on server state); no removals. Other scenarios use sync only where pull-and-assert is needed.
- **Rate limiting**: `RATE_LIMIT_REQUESTS=0` disables rate limiting (for local dev/testing). When 0, the middleware skips checks; config validation allows 0.

This document summarizes the current behavior and why the app appears not to fetch data and why Rust output is missing; it does not change code by itself.
