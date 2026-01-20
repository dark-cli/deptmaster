#!/bin/bash
# Script to restart the Rust API server

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛑 Stopping existing server..."
pkill -f "debt-tracker-api" || true
sleep 2

# Check if Docker services are running
echo "🔍 Checking Docker services..."
if ! docker ps > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Ensure PostgreSQL is running
if ! docker ps | grep -q "debt_tracker_postgres"; then
    echo "⚠️  PostgreSQL not running. Starting..."
    cd backend
    docker-compose up -d postgres
    echo "⏳ Waiting for PostgreSQL to be ready..."
    sleep 5
    cd ..
fi

# Ensure EventStore is running
if ! docker ps | grep -q "debt_tracker_eventstore"; then
    echo "⚠️  EventStore not running. Starting..."
    cd backend
    docker-compose up -d eventstore
    echo "⏳ Waiting for EventStore to be ready..."
    sleep 5
    cd ..
else
    # Check if EventStore is healthy
    if ! curl -f http://localhost:2113/health/live > /dev/null 2>&1; then
        echo "⚠️  EventStore not healthy. Restarting..."
        cd backend
        docker-compose restart eventstore
        echo "⏳ Waiting for EventStore to be ready..."
        sleep 5
        cd ..
    fi
fi

echo "🔨 Building server..."
cd backend/rust-api
cargo build --release

echo "🚀 Starting server..."
cd "$SCRIPT_DIR"
nohup backend/rust-api/target/release/debt-tracker-api > /tmp/debt-tracker-api.log 2>&1 &

echo "✅ Server restarted! Check /tmp/debt-tracker-api.log for logs"
echo "   Server should be running on http://localhost:8000"
echo "   EventStore UI: http://localhost:2113 (admin/changeit)"