#!/bin/bash
# Run Rust server directly for faster development/testing
# This assumes postgres and redis are running in Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR/backend/rust-api"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 Starting Rust server in development mode...${NC}"
echo -e "${YELLOW}Note: Make sure postgres and redis are running in Docker${NC}"
echo ""

# Set environment variables (can be overridden by .env file)
export DATABASE_URL="${DATABASE_URL:-postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker}"
export REDIS_URL="${REDIS_URL:-redis://localhost:6379}"
export PORT="${PORT:-8000}"
export RUST_LOG="${RUST_LOG:-debug}"

# Optional: JWT settings (use defaults if not set)
export JWT_SECRET="${JWT_SECRET:-your-secret-key-change-in-production}"
export JWT_EXPIRATION="${JWT_EXPIRATION:-3600}"

echo "Configuration:"
echo "  DATABASE_URL: $DATABASE_URL"
echo "  REDIS_URL: $REDIS_URL"
echo "  PORT: $PORT"
echo "  RUST_LOG: $RUST_LOG"
echo ""

# Run with cargo (will auto-reload on code changes if using cargo-watch)
if command -v cargo-watch &> /dev/null; then
    echo -e "${GREEN}Using cargo-watch for auto-reload...${NC}"
    echo "Install with: cargo install cargo-watch"
    cargo watch -x 'run --bin debt-tracker-api'
else
    echo -e "${YELLOW}Running without auto-reload. Install cargo-watch for auto-reload:${NC}"
    echo "  cargo install cargo-watch"
    echo ""
    cargo run --bin debt-tracker-api
fi
