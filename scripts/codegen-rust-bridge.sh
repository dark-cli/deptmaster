#!/usr/bin/env bash
# Generate Flutter Rust Bridge code (Dart + Rust wire).
# Run from repo root. Requires: cargo (flutter_rust_bridge_codegen, cargo-expand), flutter in PATH.
set -e
cd "$(dirname "$0")/.."
export PATH="${FLUTTER_ROOT:-$HOME/flutter}/bin:$PATH"
cd crates/debitum_client_core
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
echo "Done. Generated: mobile/lib/src/*.dart, crates/debitum_client_core/src/frb_generated.rs"
