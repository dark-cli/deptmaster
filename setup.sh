#!/bin/bash
# Initial Setup Script for Debt Tracker
# Usage: ./setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_step() {
    echo -e "${BLUE}→ $1${NC}"
}

echo "🚀 Setting up Debt Tracker..."
echo ""

# Check prerequisites
print_step "Checking prerequisites..."

MISSING_DEPS=()

command -v rustc >/dev/null 2>&1 || MISSING_DEPS+=("Rust")
command -v cargo >/dev/null 2>&1 || MISSING_DEPS+=("Cargo")
command -v docker >/dev/null 2>&1 || MISSING_DEPS+=("Docker")
command -v docker-compose >/dev/null 2>&1 || MISSING_DEPS+=("Docker Compose")
command -v flutter >/dev/null 2>&1 || MISSING_DEPS+=("Flutter")

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    print_error "Missing prerequisites:"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Install missing dependencies:"
    echo "  ./manage.sh install-deps  # For server dependencies"
    echo "  # For Flutter, see: https://docs.flutter.dev/get-started/install"
    exit 1
fi

print_success "All prerequisites met"
echo ""

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    print_step "Creating .env file..."
    cat > .env <<EOF
# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=debt_tracker
DB_USER=debt_tracker
DB_PASSWORD=dev_password

# Server
PORT=8000
RUST_LOG=info

# EventStore
EVENTSTORE_URL=http://localhost:2113
EVENTSTORE_USERNAME=admin
EVENTSTORE_PASSWORD=changeit
EOF
    print_success ".env file created"
    print_info "Please edit .env file with your configuration if needed"
else
    print_info ".env file already exists"
fi
echo ""

# Start Docker services
print_step "Starting Docker services..."
if ! docker ps > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

cd backend
docker-compose up -d postgres eventstore redis 2>/dev/null || docker-compose up -d postgres eventstore redis
cd ..

print_info "Waiting for services to be ready..."
sleep 5

print_success "Docker services started"
echo ""

# Setup backend
print_step "Setting up backend..."
cd backend/rust-api

print_info "Installing Rust dependencies..."
cargo build --quiet 2>/dev/null || cargo build

print_info "Running database migrations..."
if command -v sqlx &> /dev/null; then
    sqlx migrate run --database-url "postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" 2>/dev/null || {
        print_info "Running migrations manually..."
        docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/001_initial_schema.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/002_remove_transaction_settled.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/003_add_due_date.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/004_user_settings.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/005_create_default_user.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/006_add_username_to_contacts.sql > /dev/null 2>&1 || true
    }
else
    print_info "sqlx-cli not found, running migrations manually..."
    docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/001_initial_schema.sql > /dev/null 2>&1 || true
    docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/002_remove_transaction_settled.sql > /dev/null 2>&1 || true
    docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/003_add_due_date.sql > /dev/null 2>&1 || true
    docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/004_user_settings.sql > /dev/null 2>&1 || true
    docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/005_create_default_user.sql > /dev/null 2>&1 || true
    docker exec -i debt_tracker_postgres psql -U debt_tracker -d debt_tracker < migrations/006_add_username_to_contacts.sql > /dev/null 2>&1 || true
fi

cd "$SCRIPT_DIR"
print_success "Backend setup complete"
echo ""

# Setup mobile
print_step "Setting up mobile app..."
cd mobile

print_info "Installing Flutter dependencies..."
flutter pub get > /dev/null 2>&1 || flutter pub get

print_info "Generating Hive adapters..."
flutter pub run build_runner build --delete-conflicting-outputs > /dev/null 2>&1 || flutter pub run build_runner build --delete-conflicting-outputs

cd "$SCRIPT_DIR"
print_success "Mobile setup complete"
echo ""

# Final summary
print_success "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Start server:     ./manage.sh start-server"
echo "  2. Run mobile app:   ./mobile.sh run android"
echo "  3. View admin panel: http://localhost:8000/admin"
echo ""
echo "For more information, see:"
echo "  - Server management: ./manage.sh help"
echo "  - Mobile app:         ./mobile.sh help"
echo "  - Documentation:     docs/README.md"
