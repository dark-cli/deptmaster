# debitum_client_core

Rust core for the Debitum mobile client: storage, sync, and CRUD.

## Running tests

From the crate directory:

```bash
cd crates/debitum_client_core
cargo test
```

From the repo root (if you have a workspace):

```bash
cargo test -p debitum_client_core
```

### Integration tests (real server)

The tests in `tests/integration_test.rs` use the **mobile Rust client** (this crate) to simulate app instance(s) that talk to a **real server** over the network. They are ignored by default.

1. Start the server (e.g. from `backend/rust-api`: `cargo run --bin debt-tracker-api` with a test DB). Default server port is 8000.
2. Set `TEST_SERVER_URL` if the server is not on port 8000 (e.g. `http://127.0.0.1:8000`). Optionally set `TEST_USERNAME` / `TEST_PASSWORD` to use an existing user in the login test.
3. Run with a single thread (client uses global state, so tests must run sequentially):

```bash
TEST_SERVER_URL=http://127.0.0.1:8000 cargo test -p debitum_client_core --test integration_test -- --ignored --test-threads=1
```

## What the tests cover

- **Storage**: `init` creates the DB file; config and events persist.
- **get_events**: Returns `[]` when no current wallet; returns `[]` when wallet has no events; returns event list when events were inserted for that wallet.
- **Wallet**: `set_current_wallet_id` / `get_current_wallet_id` round-trip.
- **Sync precondition**: For a newly selected wallet, `events_count` is 0 so the sync layer will do a full pull (no `since`).

## Why Rust `eprintln!` may not show when running the Flutter app

When the app runs via `flutter run`, the Rust code runs inside a dynamic library (`.so` on Linux). Stderr from that library is not always attached to the same terminal as the Dart VM, so `[debitum_rs]` logs may not appear.

To confirm behavior:

1. Run `cargo test` — if tests pass, storage and `get_events` work in isolation.
2. Ensure the Flutter app loads the library you built (e.g. `LD_LIBRARY_PATH` pointing at `target/release` or `target/debug`).
