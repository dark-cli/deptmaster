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
