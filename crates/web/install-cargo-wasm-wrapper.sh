#!/usr/bin/env bash
# One-time install: wrap ~/.cargo/bin/cargo so every cargo run (including from dx serve)
# gets RUSTFLAGS for wasm. Fixes "clone_ref" when dx runs cargo from a temp dir.
set -e
CARGO_BIN="${CARGO_HOME:-$HOME/.cargo}/bin"
REAL_CARGO="$CARGO_BIN/cargo"
RUSTUP="$CARGO_BIN/rustup"

if [ -f "$REAL_CARGO" ] && [ ! -L "$REAL_CARGO" ] && head -1 "$REAL_CARGO" | grep -q 'RUSTFLAGS.*reference-types'; then
  echo "Already installed: $REAL_CARGO is the wasm-flags wrapper."
  echo "To undo: rm $REAL_CARGO && ln -s rustup $REAL_CARGO"
  exit 0
fi

if [ ! -e "$REAL_CARGO" ]; then
  echo "error: $REAL_CARGO not found"
  exit 1
fi

# cargo is usually a symlink to rustup; rustup then runs the toolchain's cargo
if [ -L "$REAL_CARGO" ]; then
  rm "$REAL_CARGO"
  cat > "$REAL_CARGO" << 'WRAPPER'
#!/bin/sh
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C target-feature=-reference-types"
# rustup dispatches by argv[0]; run as "cargo" so it runs toolchain's cargo
exec -a cargo "$(dirname "$0")/rustup" "$@"
WRAPPER
  chmod +x "$REAL_CARGO"
  echo "Installed: $REAL_CARGO now adds wasm rustflags and runs rustup cargo."
  echo "To undo: rm $REAL_CARGO && ln -s rustup $REAL_CARGO"
else
  # real binary: move aside and wrap
  mv "$REAL_CARGO" "$CARGO_BIN/cargo.real"
  cat > "$REAL_CARGO" << 'WRAPPER'
#!/bin/sh
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C target-feature=-reference-types"
exec "$(dirname "$0")/cargo.real" "$@"
WRAPPER
  chmod +x "$REAL_CARGO"
  echo "Installed: $REAL_CARGO now adds wasm rustflags and runs cargo.real."
  echo "To undo: mv $CARGO_BIN/cargo.real $CARGO_BIN/cargo"
fi
echo "Then run: dx serve"
