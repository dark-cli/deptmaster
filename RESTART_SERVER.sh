#!/bin/bash
# Script to restart the Rust API server

set -e

echo "🛑 Stopping existing server..."
pkill -f "debt-tracker-api" || true
sleep 2

echo "🔨 Building server..."
cd backend/rust-api
cargo build --release

echo "🚀 Starting server..."
cd ../..
nohup backend/rust-api/target/release/debt-tracker-api > /tmp/debt-tracker-api.log 2>&1 &

echo "✅ Server restarted! Check /tmp/debt-tracker-api.log for logs"
echo "   Server should be running on http://localhost:8000"
