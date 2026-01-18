#!/bin/bash
# Start the app after SELinux is disabled

set -e

echo "🚀 Starting Debt Tracker after SELinux fix..."
echo ""

# Start Docker services
echo "🐳 Starting Docker services..."
docker-compose up -d postgres redis

echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 10

# Check if database exists and create if needed
echo "📊 Setting up database..."
docker-compose exec -T postgres psql -U debt_tracker -d postgres -c "CREATE DATABASE debt_tracker;" 2>/dev/null || echo "Database might already exist"

# Run migrations
echo "📝 Running migrations..."
cat backend/rust-api/migrations/001_initial_schema.sql | docker-compose exec -T postgres psql -U debt_tracker -d debt_tracker 2>/dev/null || echo "Tables might already exist"

# Verify database is ready
echo "✅ Verifying database..."
docker-compose exec -T postgres psql -U debt_tracker -d debt_tracker -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | grep -q "[0-9]" && echo "✅ Database is ready!" || echo "⚠️  Database might need setup"

echo ""
echo "🎯 Starting Rust API server..."
echo "   Admin Panel: http://localhost:8000/admin"
echo "   Health Check: http://localhost:8000/health"
echo "   API: http://localhost:8000/api/admin/contacts"
echo ""
echo "Press Ctrl+C to stop"
echo ""

cd backend/rust-api
DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
REDIS_URL="redis://localhost:6379" \
PORT=8000 \
RUST_LOG=info \
cargo run
