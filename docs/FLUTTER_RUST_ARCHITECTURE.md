# Flutter UI + Rust Logic Architecture

## Goal

- **Flutter/Dart**: UI only — user input/output, layout, navigation. No business logic, no direct storage/sync/auth/WebSocket.
- **Rust**: All client logic — auth (login, token storage, staying logged in), local read/write (storage), syncing, WebSocket listener, projection building.

Dart never calls `SyncServiceV2`, `AuthService`, `EventStoreService`, `StateBuilder`, etc. directly from screens. It calls a single **Rust client API** that encapsulates everything.

---

## Is It Fully Possible?

**Yes.** The standard approach is **flutter_rust_bridge**: Rust code is compiled to a native library (Android NDK, iOS, Linux, macOS, Windows) and Dart calls it via FFI. The bridge handles async, serialization (e.g. JSON or bincode), and codegen for type-safe Dart bindings.

- **Auth**: Token and user id stored in Rust (e.g. in SQLite or a small key-value table). No Dart `SharedPreferences` / `FlutterSecureStorage` for auth.
- **Storage**: Rust uses **SQLite** (e.g. `rusqlite`) for events and projections. Same schema idea as today (events table, contacts/transactions as projection tables or single JSON blobs). No Hive in Dart for app data.
- **Sync**: Rust does HTTP (e.g. `reqwest`): push unsynced events, pull server events, merge, rebuild projection, persist. No Dart `ApiService`/`SyncServiceV2` for this logic.
- **WebSocket**: Rust holds the WebSocket connection (e.g. `tokio-tungstenite`), reconnects, and notifies Dart when “events_synced” or similar (e.g. via a stream or callback that the bridge exposes to Dart).
- **Projection**: You already have `state_builder.rs` in `frontend/`. That (or a shared crate) runs in the client Rust lib; events are read from SQLite, state is built, and result is written back to SQLite (or kept in memory and returned to Dart on demand).

So: **Fully possible.** Flutter stays as the UI layer; all “client internal” logic lives in one Rust crate that you build for each platform.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Flutter (Dart) — UI only                                        │
│  Screens, widgets, navigation, forms.                           │
│  Calls: DebitumCore.getContacts(), DebitumCore.createTransaction() │
│  Listens: DebitumCore.syncStatusStream(), dataChangedStream()    │
└───────────────────────────┬─────────────────────────────────────┘
                            │ FFI (flutter_rust_bridge)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Rust client crate (e.g. debitum_client_core)                   │
│  - Auth: login, token storage, validate, logout                  │
│  - Storage: SQLite (events + projection cache)                  │
│  - Projection: state_builder from events                         │
│  - Sync: HTTP push/pull, hash compare, apply server events       │
│  - Realtime: WebSocket client, reconnect, emit to Dart           │
│  Single entry point: all reads/writes/submits go through here   │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTP / WebSocket
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Backend (existing rust-api)                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Rust API Surface (What Dart Calls)

Dart should only see a **small, stable API**. All the “glue” and scattered logic (sync after submit, WebSocket triggering sync, etc.) lives inside Rust.

Suggested surface (names are illustrative; you can rename to match your style):

### Setup

- `init(base_url: String, ws_url: String)` — call once at app start. Rust opens SQLite, loads config.
- `set_backend_config(base_url: String, ws_url: String)` — when user changes backend in settings.

### Auth

- `login(username: String, password: String) -> Result<(), String>`
- `logout() -> ()`
- `is_logged_in() -> bool`
- `get_user_id() -> Option<String>`
- `validate_token() -> Result<bool, String>` — optional; Rust can call backend to validate and refresh.

Rust keeps token and user id in SQLite (or a dedicated secrets table). No Dart auth storage.

### Wallet

- `get_wallets() -> Result<Vec<Wallet>, String>`
- `get_current_wallet_id() -> Option<String>`
- `set_current_wallet_id(id: String) -> Result<(), String>`
- `ensure_current_wallet() -> Result<(), String>`
- `create_wallet(name: String, description: String) -> Result<Wallet, String>`

Rust uses API for list/create; current wallet id stored in SQLite.

### Read / List (no side effects)

- `get_contacts() -> Result<Vec<Contact>, String>`
- `get_transactions() -> Result<Vec<Transaction>, String>`
- `get_contact(id: String) -> Result<Option<Contact>, String>`
- `get_events_for_wallet(wallet_id: String) -> Result<Vec<Event>, String>` — for events log screen.
- `get_sync_status() -> Result<SyncStatus, String>` — e.g. `{ status: synced | unsynced | syncing | offline, hasError: bool, lastSync: Option<DateTime> }`.
- `calculate_total_debt_at_time(wallet_id: String, timestamp: String) -> Result<f64, String>` — for debt-at-time in events UI.

All read from Rust’s SQLite (projection or events). No Hive, no `LocalDatabaseServiceV2` / `StateBuilder` in Dart.

### Submit / Write (Rust does sync)

- `create_contact(contact: ContactInput) -> Result<Contact, String>`
- `update_contact(id: String, contact: ContactInput) -> Result<Contact, String>`
- `delete_contact(id: String) -> Result<(), String>`
- `undo_contact_action(contact_id: String) -> Result<(), String>`
- `create_transaction(transaction: TransactionInput) -> Result<Transaction, String>`
- `update_transaction(id: String, transaction: TransactionInput) -> Result<Transaction, String>`
- `delete_transaction(id: String) -> Result<(), String>`
- `undo_transaction_action(transaction_id: String) -> Result<(), String>`
- `bulk_delete_contacts(ids: Vec<String>) -> Result<(), String>`
- `bulk_delete_transactions(ids: Vec<String>) -> Result<(), String>`
- `undo_bulk_contact_actions(ids: Vec<String>) -> Result<(), String>`
- `undo_bulk_transaction_actions(ids: Vec<String>) -> Result<(), String>`

Each of these in Rust: write event(s) to SQLite, rebuild projection (or apply incrementally), then **start sync** (push to server). No “call sync after submit” in Dart — Rust does it.

### Sync (explicit user actions only from Dart)

- `manual_sync() -> Result<(), String>` — e.g. “Sync now” or after login.
- `on_pull_to_refresh() -> ()` — reset backoff and trigger sync.

Rust implements backoff, hash-based pull, conflict handling, and WebSocket-triggered sync internally; Dart only triggers when user pulls or taps sync.

### Realtime

- `start_realtime_listener() -> ()` — Rust opens WebSocket, reconnects, and when it receives e.g. `events_synced`, runs server-to-local sync and then notifies Dart.
- Dart listens to a **stream** (or callback) that Rust feeds: e.g. `data_changed_stream()` or `sync_event_stream()`. When Dart gets an event, it just refreshes UI (e.g. re-call `get_contacts()` / `get_transactions()` or use a cached list Rust exposes). No Dart WebSocket code.

### Optional: Biometric

- `is_biometric_available() -> bool`
- `authenticate_with_biometrics() -> Result<bool, String>`

These often need platform APIs (Android/iOS). You can either keep a tiny Dart wrapper that calls platform channels and Rust only stores “unlock” state, or use a Rust crate that supports biometrics via FFI if available.

---

## Where Code Lives

| Current (Dart) | New (Rust) | Dart keeps |
|----------------|------------|------------|
| AuthService (login, token, validate, logout) | Rust: auth module + SQLite for token/user_id | Only call `DebitumCore.login()`, etc. |
| EventStoreService (Hive events) | Rust: SQLite events table + event store API | Nothing |
| LocalDatabaseServiceV2 (Hive projections + create/update/delete + sync trigger) | Rust: SQLite projection + same commands; Rust triggers sync | Nothing |
| StateBuilder | Rust: reuse `frontend/src/state_builder.rs` or shared crate | Nothing |
| SyncServiceV2 (push, pull, hash, rebuild state) | Rust: sync module (reqwest, same algorithm) | Nothing |
| RealtimeService (WebSocket) | Rust: WebSocket client, emit to Dart via stream | Only listen to stream from Rust |
| WalletService | Rust: wallet API + SQLite for current wallet | Nothing |
| ApiService (HTTP) | Rust: internal HTTP client, not exposed to Dart | Nothing |
| Screens calling sync after submit, RealtimeService.connect(), etc. | Removed; Rust does it inside create_* / update_* / WebSocket handler | Screens only call DebitumCore.* and listen to streams |

---

## Implementation Approach

1. **New crate** (e.g. `crates/debitum_client_core` or `mobile/rust/`) that:
   - Depends on `rusqlite`, `reqwest`, `tokio`, `tokio-tungstenite`, `serde`, `serde_json`, etc.
   - Has no UI; only logic. Can share code with `frontend` by extracting a small **core** crate (e.g. `debitum_core`) with `state_builder` + `Event`/`Contact`/`Transaction` models so backend, frontend, and mobile client can all use the same event semantics.
2. **flutter_rust_bridge** in `mobile/`:
   - Add `flutter_rust_bridge` + `ffi` to `pubspec.yaml`.
   - Point to the Rust crate; run codegen so Dart gets `DebitumCore` (or similar) with the methods above.
   - Rust exposes **streams** for “data changed” / “sync status” so Flutter can listen without polling.
3. **Replace Dart services** step by step:
   - Introduce a single `DebitumCore` (generated) and a thin Dart facade that maps `Result` to exceptions or `Either` if you prefer.
   - Replace `AuthService` usage with `DebitumCore.login`, etc.
   - Replace `LocalDatabaseServiceV2.getContacts()` with `DebitumCore.get_contacts()`, and same for transactions, events, sync status.
   - Replace all create/update/delete/undo calls with the Rust API; remove `SyncServiceV2.startLocalToServerSync()` and similar from Dart.
   - Replace RealtimeService usage with `DebitumCore.start_realtime_listener()` and a stream from Rust.
   - Remove or stub out old Dart services so that nothing in the UI depends on them.

4. **Storage in Rust**: Use a single SQLite DB (e.g. `debitum.db` in app documents dir). Tables: `config` (key/value for base_url, ws_url, token, user_id, current_wallet_id), `events`, optionally `contacts` and `transactions` as projection cache (or one “projection” blob per wallet). On first run, create DB and run migrations.

5. **WebSocket in Rust**: Spawn a long-running task (e.g. tokio) that connects to `ws_url` with token, reconnects on disconnect, and when it receives a message like `events_synced`, runs the same server-to-local sync you have today, then pushes an event to a channel that flutter_rust_bridge exposes as a Dart stream so the UI refreshes.

---

## Dev Workflow

### Building

- **Rust**:  
  - From repo root: `cargo build -p debitum_client_core` (or whatever the crate name).  
  - For Android: install NDK, then `cargo build -p debitum_client_core --target aarch64-linux-android` (and similar for other ABIs). flutter_rust_bridge can automate this.
- **Flutter**:  
  - `cd mobile && flutter pub get && flutter run`.  
  - Codegen (e.g. `flutter_rust_bridge_codegen`) runs as part of build; it compiles the Rust lib and generates Dart bindings.

### Running the app

- `flutter run` (or from IDE). Rust is compiled and linked; no separate “run Rust” step in normal dev.
- **Hot reload**: Only Dart/UI changes hot reload. **Rust changes require a full restart** (stop and `flutter run` again).

### Debugging

- **Dart**: Usual Flutter/Dart debugging (breakpoints, logs).
- **Rust**: `println!` / `tracing`; for native debugging, attach debugger to the running process (e.g. Android: `lldb` with NDK; iOS: Xcode). Logs from Rust show up in the same console as Flutter when running from IDE/terminal.

### Iteration

- Prefer to **keep the Rust API surface small and stable**. Add new “commands” or queries in Rust and expose one function at a time so most changes are inside Rust without touching FFI.
- You can **develop and test the Rust crate without Flutter**: e.g. `cargo test` in the client crate, or a small CLI or integration test that calls the same functions with a mock server.

---

## Testing

### Rust (logic only)

- **Unit tests** in the client crate:
  - **State builder**: Already have `frontend/tests/state_builder_test.rs`; reuse or move to shared `debitum_core` and test there. No Flutter involved.
  - **Event store**: Test append, get_events, get_unsynced, mark_synced with in-memory SQLite or a temp file.
  - **Sync logic**: Mock HTTP (e.g. with `mockito` or a test server): push events, pull events, hash comparison, rebuild projection — all in Rust.
  - **Auth**: Test token storage and validation with a test DB.
- **Integration test** (optional): Rust binary or test that starts a real backend (or uses a test container), runs full sync and checks final state. No UI.

### Flutter (UI only)

- **Widget / screen tests**: Do **not** call real Rust. Use a **mock or fake** implementation of the Dart API that talks to Rust (e.g. a `DebitumCoreMock` that returns canned `get_contacts()`, `get_transactions()`, etc.). Then test that:
  - Lists show the canned data.
  - Tapping “add” calls the mock’s `create_transaction` (or whatever the facade is) with expected args.
  - No need to run Rust or backend in widget tests.
- **Integration tests** (full app): Either run with the **real** Rust lib (and optionally a real or fake backend) to test full flows (login → create contact → sync), or run with a “stub” Rust build that returns fixed data so tests are deterministic and don’t depend on network.

### Summary

| Test type | Where | What |
|-----------|--------|------|
| State builder, event store, sync algorithm | Rust crate | `cargo test` |
| Auth, storage, WebSocket behavior | Rust crate | `cargo test` (mock HTTP/WS if needed) |
| UI: lists, forms, navigation | Flutter | Widget tests with mock core |
| Full flow: login → data → sync | Flutter integration or Rust | Real Rust + fake/real backend |

---

## Migration Order (Suggested)

1. Add `flutter_rust_bridge` and the Rust client crate; implement **init**, **auth** (login, logout, is_logged_in, get_user_id), **storage** (SQLite schema for events + config).
2. Implement **projection** in Rust (reuse state_builder), and **read** API: get_contacts, get_transactions, get_contact, get_sync_status.
3. Implement **sync** (push/pull, hash, apply server events, rebuild projection). Then implement **write** API (create_contact, create_transaction, etc.) so each write triggers sync inside Rust.
4. Implement **WebSocket** in Rust and **stream** for “data changed”; Dart replaces RealtimeService with listening to that stream.
5. Wire **wallet** API in Rust; replace WalletService usage in Dart.
6. Remove or stub old Dart services; ensure no screen calls them. Keep only UI and calls to the Rust API.

This way you get **Dart as UI only** and **all client logic in Rust**, with a clear boundary, single place for “sync after submit” and “realtime triggers sync,” and a workflow and testing strategy that keep Rust testable without Flutter and Flutter testable without real Rust.
