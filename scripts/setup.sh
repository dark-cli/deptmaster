#!/bin/bash
# Setup script for Debt Tracker

set -e

echo "🚀 Setting up Debt Tracker..."

# Check prerequisites
echo "📋 Checking prerequisites..."

command -v rustc >/dev/null 2>&1 || { echo "❌ Rust is not installed. Please install Rust first."; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo "❌ Cargo is not installed. Please install Cargo first."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is not installed. Please install Docker first."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is not installed. Please install Docker Compose first."; exit 1; }

echo "✅ All prerequisites met"

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Creating .env file from .env.example..."
    cp .env.example .env
    echo "⚠️  Please edit .env file with your configuration"
else
    echo "✅ .env file already exists"
fi

# Build Rust backend
echo "🔨 Building Rust backend..."
cd backend/rust-api
cargo build
cd ../..

# Start Docker services
echo "🐳 Starting Docker services..."
docker-compose up -d postgres redis

echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 5

# Run database migrations
echo "📊 Running database migrations..."
# TODO: Add migration command when sqlx-cli is set up
# sqlx migrate run

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env file with your configuration"
echo "2. Run: docker-compose up -d"
echo "3. Run backend: cd backend/rust-api && cargo run"
echo "4. Test: curl http://localhost:8000/health"
