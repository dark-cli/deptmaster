#!/bin/bash
# Start server with your imported Debitum data

set -e

echo "🚀 Starting Debt Tracker with YOUR Debitum data..."
echo ""

# Check if server is already running
if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "✅ Server is already running!"
    echo "🌐 Admin Panel: http://localhost:8000/admin"
    exit 0
fi

# Start Docker if needed
if ! docker ps | grep -q debt_tracker_postgres; then
    echo "🐳 Starting Docker services..."
    docker-compose up -d postgres redis
    sleep 5
fi

# Start server
echo "🎯 Starting Rust API server..."
cd backend/rust-api

DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
REDIS_URL="redis://localhost:6379" \
PORT=8000 \
RUST_LOG=info \
cargo run
