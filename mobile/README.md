# Debitum mobile app

Flutter UI for [Debitum](../README.md). All business logic — auth, sync, storage, permission resolution — lives in the Rust client crate at `../crates/client/`; this Flutter app is a thin shell.

## Run

From the repo root:

```bash
# Linux desktop
./scripts/manage.sh run-flutter-app linux

# Android (emulator or attached device)
./scripts/manage.sh run-flutter-app android
```

The script handles: building the Rust client, regenerating FRB bindings, copying the dylib into place, then launching Flutter.

## After changing the Rust API

If you edit anything in `crates/client/src/` that's exposed to Dart:

```bash
./scripts/codegen-rust-bridge.sh
```

This regenerates both `crates/client/src/frb_generated.rs` and `mobile/lib/src/*.dart`.

## Architecture

See [the main README](../README.md) for the system overview, and [vault/06-client/](../vault/06-client/) for client-specific design notes.
