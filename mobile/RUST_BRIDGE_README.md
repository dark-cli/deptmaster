# Flutter–Rust bridge (debitum_client_core)

The app uses **flutter_rust_bridge** so that all client logic (auth, storage, sync, projection) lives in Rust; Flutter is UI only and calls into Rust via `lib/core/debitum_core.dart`.

## Prerequisites

- **Rust**: `cargo`, and installed:
  - `flutter_rust_bridge_codegen` — `cargo install flutter_rust_bridge_codegen`
  - `cargo-expand` — `cargo install cargo-expand`
- **Flutter**: `flutter` in PATH (e.g. `export PATH="$HOME/flutter/bin:$PATH"`).

## Regenerating the bridge

After changing the Rust API in `crates/debitum_client_core/src/lib.rs` (or adding new `pub fn`), regenerate Dart and Rust wire code:

```bash
# From repo root
./scripts/codegen-rust-bridge.sh
```

Or manually:

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd crates/debitum_client_core
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

This updates:

- `mobile/lib/src/frb_generated*.dart` and `lib.dart`
- `crates/debitum_client_core/src/frb_generated.rs` (and `.c`)

Then rebuild the Rust crate and the Flutter app.

## Building the native library

- **Linux (desktop)**:
  1. Build the Rust lib: `cd crates/debitum_client_core && cargo build --release` (or `cargo build` for debug).
  2. If you only built debug, copy so the loader finds it: `cp target/debug/libdebitum_client_core.so target/release/`.
  3. Run from `mobile/` with `LD_LIBRARY_PATH` set: `LD_LIBRARY_PATH="../crates/debitum_client_core/target/release" flutter run -d linux`
- **Android / iOS**: Use flutter_rust_bridge’s build instructions (e.g. copy the built lib into `android/app/src/main/jniLibs/` or use the recommended build script for your version).

## Current API

- `DebitumCore.init()` — call once at startup (called from `main.dart`).
- `DebitumCore.greet(name)` — example; replace with real API (e.g. `login`, `get_contacts`) as you add them in Rust.

See `docs/FLUTTER_RUST_ARCHITECTURE.md` for the full target API and migration plan.
