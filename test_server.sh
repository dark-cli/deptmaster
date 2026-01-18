#!/bin/bash
# Test if server can start

cd backend/rust-api

# Try with a simple connection string first
export DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker"
export PORT=8000
export RUST_LOG=debug

echo "Testing server startup..."
timeout 10 cargo run 2>&1 | head -30 || echo "Server test completed"
