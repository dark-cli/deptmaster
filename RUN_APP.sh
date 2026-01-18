#!/bin/bash
# Run the Debt Tracker app

set -e

echo "🚀 Debt Tracker - Quick Start"
echo ""

# Check for local PostgreSQL
if command -v psql &> /dev/null; then
    echo "✅ PostgreSQL found locally"
    
    # Check if database exists
    if psql -lqt | cut -d \| -f 1 | grep -qw debt_tracker; then
        echo "✅ Database 'debt_tracker' exists"
    else
        echo "📦 Creating database..."
        createdb debt_tracker 2>/dev/null || echo "Database might already exist"
        
        echo "📊 Running migrations..."
        psql -d debt_tracker -f backend/rust-api/migrations/001_initial_schema.sql > /dev/null 2>&1 || echo "Tables might already exist"
    fi
    
    echo ""
    echo "🎯 Starting server..."
    echo "   Access admin panel at: http://localhost:8000/admin"
    echo "   Health check: http://localhost:8000/health"
    echo ""
    
    cd backend/rust-api
    DATABASE_URL="postgresql://localhost/debt_tracker" \
    PORT=8000 \
    RUST_LOG=info \
    cargo run
    
elif docker ps &> /dev/null; then
    echo "🐳 Using Docker..."
    docker-compose up -d postgres redis
    sleep 5
    
    echo "🎯 Starting server..."
    cd backend/rust-api
    DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
    PORT=8000 \
    RUST_LOG=info \
    cargo run
else
    echo "❌ No database found. Please install PostgreSQL or Docker."
    exit 1
fi
