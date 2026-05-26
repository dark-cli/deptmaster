#!/usr/bin/env bash
# Run the Dioxus web dev server. Puts our cargo wrapper first in PATH so when dx
# runs "cargo", it gets RUSTFLAGS=-C target-feature=-reference-types. Run from frontend: ./serve.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$DIR/cargo-wrap:$PATH"
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C target-feature=-reference-types"
exec dx serve
