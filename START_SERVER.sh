#!/bin/bash
# Start the backend server (kills existing processes first)

set -e

echo "🛑 Stopping any existing servers..."

# Kill processes on port 8000
lsof -ti:8000 | xargs kill -9 2>/dev/null || true

# Kill any existing debt-tracker-api processes
pkill -f "debt-tracker-api" 2>/dev/null || true
pkill -f "cargo run" 2>/dev/null || true

sleep 2

echo "✅ Port 8000 is free"
echo ""

cd "$(dirname "$0")/backend/rust-api"

echo "🚀 Starting Rust API server..."
echo ""

DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
PORT=8000 \
RUST_LOG=info \
cargo run
