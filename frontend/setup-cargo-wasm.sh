#!/usr/bin/env bash
# One-time: add wasm rustflags to your global Cargo config so that when dx serve
# runs cargo from a temp dir, the build still gets -C target-feature=-reference-types
# (fixes "failed to find intrinsics to enable clone_ref").
set -e
CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
CONFIG="$CARGO_HOME/config.toml"
SECTION='[target.wasm32-unknown-unknown]'
FLAGS='rustflags = ["-C", "target-feature=-reference-types"]'

if [ -f "$CONFIG" ] && grep -q "target-feature=-reference-types" "$CONFIG" 2>/dev/null; then
  echo "Global wasm rustflags already present in $CONFIG"
  exit 0
fi

mkdir -p "$CARGO_HOME"
if [ ! -f "$CONFIG" ]; then
  printf "\n# Disable wasm reference-types so wasm-bindgen works (Rust 1.82+)\n%s\n%s\n" "$SECTION" "$FLAGS" >> "$CONFIG"
  echo "Added wasm rustflags to new $CONFIG"
else
  if grep -q "$SECTION" "$CONFIG" 2>/dev/null; then
    echo "Section $SECTION already exists in $CONFIG - add manually: $FLAGS"
    exit 1
  fi
  printf "\n# Disable wasm reference-types so wasm-bindgen works (Rust 1.82+)\n%s\n%s\n" "$SECTION" "$FLAGS" >> "$CONFIG"
  echo "Appended wasm rustflags to $CONFIG"
fi
echo "You can now run: dx serve  (or: cargo run)"
