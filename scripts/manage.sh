#!/bin/bash
# Unified management script for Debt Tracker
# Usage: ./manage.sh <command> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verbose mode flag (set via --verbose or -v)
VERBOSE=false

# Database connection details
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-debt_tracker}"
DB_USER="${DB_USER:-debt_tracker}"
DB_PASSWORD="${DB_PASSWORD:-dev_password}"

export PGPASSWORD="$DB_PASSWORD"

# Verbose mode flag (set via --verbose or -v)
VERBOSE=false
# Skip build flag (set via --no-build or --skip-build)
SKIP_BUILD=false
# Clean app data flag (set via --clean, for Android only)
CLEAN_APP_DATA=false

# Parse command line arguments for flags
ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --no-build|--skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --clean)
            CLEAN_APP_DATA=true
            shift
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments
set -- "${ARGS[@]}"

# Helper functions
print_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${YELLOW}⚠️  $1${NC}"
    fi
}

print_info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}ℹ️  $1${NC}"
    fi
}

print_step() {
    # Always show step messages (these are confirming messages)
    echo -e "${BLUE}→ $1${NC}"
}

check_docker() {
    if ! docker ps > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

wait_for_service() {
    local url=$1
    local name=$2
    local max_retries=${3:-30}
    local delay=${4:-1}
    
    if [ "$VERBOSE" = true ]; then
    print_info "Waiting for $name to be ready..."
    fi
    for i in $(seq 1 $max_retries); do
        if curl -f "$url" > /dev/null 2>&1; then
            if [ "$VERBOSE" = true ]; then
                print_success "$name is ready"
            fi
            return 0
        fi
        if [ "$VERBOSE" = true ] && [ $((i % 5)) -eq 0 ]; then
            print_info "Still waiting... ($i/$max_retries)"
        fi
        sleep $delay
    done
    print_error "$name failed to start after ${max_retries} attempts"
    if [ -f "/tmp/debt-tracker-api.log" ]; then
        print_error "Last 10 lines of server log:"
        tail -10 /tmp/debt-tracker-api.log | sed 's/^/  /'
    fi
    return 1
}

# Commands
cmd_reset() {
    local import_file="${1:-}"
    
    print_info "Resetting system (database)..."
    
    check_docker
    
    # Stop server if running
    print_info "Stopping server..."
    pkill -f "debt-tracker-api" || true
    sleep 2
    
    # Reset database
    cmd_reset_database
    
    # If import file provided, import data
    if [ -n "$import_file" ]; then
        cmd_import "$import_file"
    else
        print_info "No import file provided. Database is clean and ready."
    fi
}

cmd_full_flash() {
    local import_file="${1:-}"
    
    print_step "Full Flash: Resetting system..."
    
    check_docker
    
    # Stop server if running
    pkill -f "debt-tracker-api" > /dev/null 2>&1 || true
    sleep 2
    
    # Reset database
    print_info "Resetting database..."
    cmd_reset_database
    
    # Start server (needed for import and rebuild)
    print_info "Starting server..."
    if [ "$SKIP_BUILD" = true ]; then
        cmd_start_server_no_build
    else
        cmd_start_server
    fi
    
    # If import file provided, import data (import already rebuilds projections)
    if [ -n "$import_file" ]; then
        cmd_import "$import_file"
    else
        print_step "Rebuilding projections..."
        cmd_rebuild_projections
    fi
    
    print_success "Full Flash complete!"
}

cmd_reset_database() {
    print_info "Resetting PostgreSQL database..."
    
    check_docker
    
    # Ensure PostgreSQL is running
    if ! docker ps | grep -q "debt_tracker_postgres"; then
        print_warning "PostgreSQL not running. Starting..."
        cd "$ROOT_DIR/backend"
        docker-compose up -d postgres > /dev/null 2>&1
        sleep 5
        cd "$ROOT_DIR"
    fi
    
    print_info "Terminating all connections..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres > /dev/null 2>&1 <<EOF
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();
EOF
    
    print_info "Dropping database..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres > /dev/null 2>&1 <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
EOF
    sleep 1
    
    print_info "Creating fresh database..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres > /dev/null 2>&1 <<EOF
CREATE DATABASE $DB_NAME;
EOF
    
    print_info "Running migrations..."
    cd "$ROOT_DIR/backend/rust-api"
    
    # Try sqlx first, but fall back to manual migrations quickly
    USE_SQLX=false
    if command -v sqlx &> /dev/null 2>&1; then
        USE_SQLX=true
    fi
    
    if [ "$USE_SQLX" = true ]; then
        if timeout 10 sqlx migrate run --database-url "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" > /dev/null 2>&1; then
            print_info "Migrations completed via sqlx"
        else
            print_warning "sqlx migration failed or timed out, using manual migrations..."
            USE_SQLX=false
        fi
    fi
    
    # Manual migration fallback (always run if sqlx failed or doesn't exist)
    if [ "$USE_SQLX" = false ]; then
        print_info "Running migrations manually..."
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/001_initial_schema.sql > /dev/null 2>&1
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/002_remove_transaction_settled.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/003_add_due_date.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/004_user_settings.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/005_create_default_user.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/006_add_username_to_contacts.sql > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/007_add_idempotency_and_versions.sql > /dev/null 2>&1 || true
    fi
    
    # Ensure only the "max" user exists (clean up any other users)
    print_info "Ensuring only default user exists..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1 <<EOF
-- Delete all users except "max"
DELETE FROM users_projection WHERE email != 'max';
-- Ensure "max" user exists (migration 005 should have created it, but just in case)
INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id)
SELECT 
    gen_random_uuid(),
    'max',
    '\$2b\$12\$MzvHQ6CeZgenzzwkEV2WeeDQscVKQed1kTh8NxB7w2bXCXe2qFjxK',
    NOW(),
    0
WHERE NOT EXISTS (SELECT 1 FROM users_projection WHERE email = 'max');
EOF
    
    cd "$ROOT_DIR"
    print_success "Database reset complete"
}

cmd_import() {
    local backup_file="${1:-debitum-backup-2026-01-18T05_51_03.zip}"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        echo ""
        echo "Usage: $0 import <path-to-backup.zip>"
        echo ""
        echo "Looking for backup files in current directory..."
        ls -la *.zip 2>/dev/null || echo "No .zip files found"
        exit 1
    fi
    
    print_step "Importing data from: $backup_file"
    
    # Ensure server is running
    if ! curl -f http://localhost:8000/health > /dev/null 2>&1; then
        print_warning "Server not running. Starting..."
        cmd_start_server > /dev/null 2>&1 || cmd_start_server
    fi
    
    # Check for Python script and dependencies
    if [ ! -f "scripts/migrate_debitum_via_api_fast.py" ]; then
        print_error "migrate_debitum_via_api_fast.py not found"
        exit 1
    fi
    
    if ! python3 -c "import requests" 2>/dev/null; then
        print_warning "Python 'requests' library not found. Installing..."
        pip3 install requests > /dev/null 2>&1 || {
            print_error "Failed to install requests library"
            exit 1
        }
    fi
    
    # Run migration
    print_info "Running migration via API..."
    if [ "$VERBOSE" = true ]; then
        python3 scripts/migrate_debitum_via_api_fast.py "$backup_file" || {
            print_error "Failed to import data"
            exit 1
        }
    else
        python3 scripts/migrate_debitum_via_api_fast.py "$backup_file" > /dev/null 2>&1 || {
            print_error "Failed to import data"
            exit 1
        }
    fi
    
    # Rebuild projections from events
    print_info "Rebuilding projections..."
    cmd_rebuild_projections
    
    print_success "Import complete!"
}

cmd_start_services() {
    print_info "Starting Docker services..."
    
    check_docker
    
    cd "$ROOT_DIR/backend"
    
    if [ "$1" = "postgres" ] || [ -z "$1" ]; then
        print_info "Starting PostgreSQL..."
        docker-compose up -d postgres > /dev/null 2>&1
        sleep 5
    fi
    
    if [ "$1" = "redis" ] || [ -z "$1" ]; then
        print_info "Starting Redis..."
        docker-compose up -d redis > /dev/null 2>&1
        sleep 3
    fi
    
    if [ -z "$1" ]; then
        print_info "Starting all services..."
        docker-compose up -d postgres redis > /dev/null 2>&1
    fi
    
    cd "$ROOT_DIR"
    if [ "$VERBOSE" = true ]; then
        print_success "Services started"
    fi
}

cmd_stop_services() {
    print_info "Stopping Docker services..."
    
    check_docker
    
    cd "$ROOT_DIR/backend"
    
    if [ "$1" = "postgres" ]; then
        docker-compose stop postgres
    elif [ "$1" = "redis" ]; then
        docker-compose stop redis
    else
        docker-compose stop
    fi
    
    cd "$ROOT_DIR"
    print_success "Services stopped"
}

cmd_start_server() {
    print_info "Starting API server..."
    
    # Stop any existing server
    pkill -f "debt-tracker-api" > /dev/null 2>&1 || true
    sleep 2
    
    # Ensure services are running
    cmd_start_services
    
    # Build if needed
    if [ ! -f "$ROOT_DIR/backend/rust-api/target/release/debt-tracker-api" ]; then
        print_step "Building server (this may take a minute)..."
        cd "$ROOT_DIR/backend/rust-api"
        if [ "$VERBOSE" = true ]; then
            cargo build --release || {
                print_error "Build failed. Check Rust version (requires 1.88+). Run: rustup update"
                exit 1
            }
        else
            if ! cargo build --release 2>&1 | tee /tmp/cargo-build.log | grep -E "error|Finished|Compiling" | head -20; then
                print_error "Build failed. Check Rust version (requires 1.88+). Run: rustup update"
                print_error "Build log: /tmp/cargo-build.log"
                exit 1
            fi
        fi
        cd "$ROOT_DIR"
    fi
    
    # Start server
    print_info "Starting server..."
    nohup "$ROOT_DIR/backend/rust-api/target/release/debt-tracker-api" > /tmp/debt-tracker-api.log 2>&1 &
    
    wait_for_service "http://localhost:8000/health" "API Server" 30 1
    if [ "$VERBOSE" = true ]; then
        print_success "Server started! Logs: /tmp/debt-tracker-api.log"
    fi
}

cmd_start_server_no_build() {
    print_info "Starting API server (skipping build)..."
    
    # Stop any existing server
    pkill -f "debt-tracker-api" > /dev/null 2>&1 || true
    sleep 2
    
    # Ensure services are running
    cmd_start_services > /dev/null 2>&1 || cmd_start_services
    
    # Check if binary exists
    if [ ! -f "$ROOT_DIR/backend/rust-api/target/release/debt-tracker-api" ]; then
        print_error "Server binary not found. Please build first: $0 build"
        exit 1
    fi
    
    # Start server
    print_info "Starting server..."
    nohup "$ROOT_DIR/backend/rust-api/target/release/debt-tracker-api" > /tmp/debt-tracker-api.log 2>&1 &
    
    wait_for_service "http://localhost:8000/health" "API Server" 30 1 > /dev/null 2>&1
    if [ "$VERBOSE" = true ]; then
        print_success "Server started! Logs: /tmp/debt-tracker-api.log"
    fi
}

cmd_stop_server() {
    print_info "Stopping API server..."
    
    # Stop Docker container if running
    cd "$ROOT_DIR/backend"
    docker-compose stop api 2>/dev/null || true
    cd "$ROOT_DIR"
    
    # Also stop any direct process
    pkill -f "debt-tracker-api" || true
    sleep 2
    
    print_success "Server stopped"
}

cmd_restart_server() {
    print_info "Restarting API server..."
    
    cmd_stop_server
    sleep 2
    cmd_start_server
}

cmd_start_prod() {
    print_step "Starting production server (all in Docker)..."
    check_docker
    
    cd "$ROOT_DIR/backend"
    
    # Start all services including API in Docker
    print_info "Starting all Docker services (postgres, redis, api)..."
    docker-compose up -d
    
    # Wait for services to be healthy
    print_info "Waiting for services to be ready..."
    wait_for_service "http://localhost:8000/health" "API Server" 60 2
    
    cd "$ROOT_DIR"
    print_success "Production server started (all in Docker)"
    print_info "Server running at: http://localhost:8000"
    print_info "View logs: $0 logs"
    print_info "Stop with: docker-compose -f backend/docker-compose.yml stop api"
}

cmd_start_dev() {
    print_step "Starting development server (direct)..."
    
    # Check if cargo is available
    if ! command -v cargo &> /dev/null; then
        print_error "Cargo not found. Please install Rust: https://rustup.rs/"
        exit 1
    fi
    
    # Start services (postgres, redis) if not running
    cmd_start_services
    
    # Stop Docker API container if running (to free port 8000)
    cd "$ROOT_DIR/backend"
    if docker ps --format '{{.Names}}' | grep -q '^debt_tracker_api$'; then
        print_info "Stopping Docker API container to free port 8000..."
        docker-compose stop api 2>/dev/null || true
    fi
    cd "$ROOT_DIR"
    
    # Check if port is available and try to stop what's using it
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        print_warning "Port 8000 is already in use. Attempting to stop it..."
        
        # Try to stop Docker API container
        cd "$ROOT_DIR/backend"
        if docker ps --format '{{.Names}}' | grep -q '^debt_tracker_api$'; then
            print_info "Stopping Docker API container..."
            docker-compose stop api 2>/dev/null || true
            sleep 2
        fi
        cd "$ROOT_DIR"
        
        # Try to stop direct process
        if pgrep -f "debt-tracker-api" > /dev/null; then
            print_info "Stopping direct API process..."
            pkill -f "debt-tracker-api" || true
            sleep 2
        fi
        
        # Check again
        if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
            print_error "Port 8000 is still in use. Please manually stop the service:"
            print_info "  docker-compose -f backend/docker-compose.yml stop api"
            print_info "  pkill -f debt-tracker-api"
            print_info "  Or use: $0 stop-server"
            exit 1
        else
            print_success "Port 8000 is now free"
        fi
    fi
    
    print_info "Starting Rust server directly..."
    print_info "Database: postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker"
    print_info "Redis: redis://localhost:6379"
    print_info ""
    print_info "Press Ctrl+C to stop"
    print_info ""
    
    # Set environment variables
    export DATABASE_URL="${DATABASE_URL:-postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker}"
    export REDIS_URL="${REDIS_URL:-redis://localhost:6379}"
    export PORT="${PORT:-8000}"
    export RUST_LOG="${RUST_LOG:-debug}"
    export JWT_SECRET="${JWT_SECRET:-your-secret-key-change-in-production}"
    export JWT_EXPIRATION="${JWT_EXPIRATION:-3600}"
    
    cd "$ROOT_DIR/backend/rust-api"
    
    # Use cargo-watch if available, otherwise regular cargo run
    if command -v cargo-watch &> /dev/null; then
        print_info "Using cargo-watch for auto-reload..."
        print_info "Watching: Rust source files (.rs) and static files (.html, .js)"
        print_info "Note: Static file changes require recompilation (will auto-restart)"
        # Watch both Rust files and static files
        cargo watch \
            --watch "$ROOT_DIR/backend/rust-api/src" \
            --watch "$ROOT_DIR/backend/rust-api/static" \
            -x 'run --bin debt-tracker-api'
    else
        print_warning "cargo-watch not installed. Install for auto-reload: cargo install cargo-watch"
        print_info "Note: Static file changes require restarting the server"
        cargo run --bin debt-tracker-api
    fi
}

cmd_build() {
    print_info "Building server..."
    
    cd "$ROOT_DIR/backend/rust-api"
    cargo build --release
    cd "$ROOT_DIR"
    
    print_success "Build complete"
}

cmd_status() {
    print_info "System Status:"
    echo ""
    
    # Check Docker
    if docker ps > /dev/null 2>&1; then
        print_success "Docker: Running"
        
        echo "  Services:"
        if docker ps | grep -q "debt_tracker_postgres"; then
            echo "    ✅ PostgreSQL"
        else
            echo "    ❌ PostgreSQL (not running)"
        fi
        
        if docker ps | grep -q "debt_tracker_redis"; then
            echo "    ✅ Redis"
        else
            echo "    ❌ Redis (not running)"
        fi
    else
        print_error "Docker: Not running"
    fi
    
    echo ""
    
    # Check API server
    if pgrep -f "debt-tracker-api" > /dev/null; then
        if curl -f http://localhost:8000/health > /dev/null 2>&1; then
            print_success "API Server: Running (http://localhost:8000)"
        else
            print_warning "API Server: Process running but not responding"
        fi
    else
        print_error "API Server: Not running"
    fi
    
    echo ""
    echo "📊 Quick Links:"
    echo "   - Admin Panel: http://localhost:8000/admin"
    echo "   - Server Logs: tail -f /tmp/debt-tracker-api.log"
}

cmd_logs() {
    if [ -f "/tmp/debt-tracker-api.log" ]; then
        tail -f /tmp/debt-tracker-api.log
    else
        print_error "Log file not found. Server may not be running."
    fi
}

cmd_rebuild_projections() {
    print_step "Rebuilding projections..."
    
    # Ensure server is running
    if ! curl -f http://localhost:8000/health > /dev/null 2>&1; then
        print_error "Server is not running. Please start the server first: $0 start-server"
        exit 1
    fi
    
    # Call rebuild endpoint
    local response
    response=$(curl -s -X POST http://localhost:8000/api/admin/projections/rebuild)
    
    if echo "$response" | grep -q "successfully"; then
        # Success is silent in non-verbose mode (step message is enough)
        if [ "$VERBOSE" = true ]; then
            print_success "Projections rebuilt successfully"
        fi
    elif echo "$response" | grep -q "error"; then
        print_error "Failed to rebuild projections: $response"
        exit 1
    else
        if [ "$VERBOSE" = true ]; then
            print_warning "Unexpected response: $response"
        fi
    fi
}

cmd_run_app() {
    local platform="${1:-android}"
    local device_id="${2:-}"
    
    print_step "Running Flutter app ($platform)..."
    
    cd mobile
    
    if [ "$platform" = "android" ]; then
        # Clean app data if --clean flag is set
        if [ "$CLEAN_APP_DATA" = true ]; then
            print_info "Clearing app data via adb..."
            
            # Check if adb is available
            if ! command -v adb &> /dev/null; then
                print_error "adb not found. Please install Android SDK platform-tools."
                exit 1
            fi
            
            # Check if device is connected
            if ! adb devices | grep -q "device$"; then
                print_error "No Android device connected. Please connect a device or start an emulator."
                exit 1
            fi
            
            # Clear app data
            local package_name="com.example.debt_tracker_mobile"
            if [ -n "$device_id" ]; then
                adb -s "$device_id" shell pm clear "$package_name" > /dev/null 2>&1 || {
                    print_error "Failed to clear app data. Make sure the app is installed."
                    exit 1
                }
            else
                adb shell pm clear "$package_name" > /dev/null 2>&1 || {
                    print_error "Failed to clear app data. Make sure the app is installed."
                    exit 1
                }
            fi
            
            print_success "App data cleared"
        fi
        
        if [ -n "$device_id" ]; then
            flutter run -d "$device_id"
        else
            flutter run
        fi
    elif [ "$platform" = "web" ]; then
        if [ "$CLEAN_APP_DATA" = true ]; then
            print_warning "--clean flag is only supported for Android platform"
        fi
        flutter run -d chrome
    elif [ "$platform" = "linux" ]; then
        # Clean app data if --clean flag is set
        if [ "$CLEAN_APP_DATA" = true ]; then
            print_info "Clearing app data for Linux..."
            
            # Hive stores data in ~/.local/share/com.example.debt_tracker_mobile/ (package name)
            local hive_dir="$HOME/.local/share/com.example.debt_tracker_mobile"
            local files_removed=0
            
            if [ -d "$hive_dir" ]; then
                # Count files before removal
                local count_before=$(find "$hive_dir" -name "*.hive" -o -name "*.hive.lock" 2>/dev/null | wc -l)
                
                # Remove all Hive box files
                rm -f "$hive_dir"/*.hive "$hive_dir"/*.hive.lock 2>/dev/null
                
                if [ "$count_before" -gt 0 ]; then
                    files_removed=$((files_removed + count_before))
                fi
            fi
            
            # Also check Documents directory (sometimes Hive stores there during development)
            local docs_hive_files=$(find "$HOME/Documents" -maxdepth 1 -name "*.hive" -o -name "*.hive.lock" 2>/dev/null | wc -l)
            if [ "$docs_hive_files" -gt 0 ]; then
                rm -f "$HOME/Documents"/*.hive "$HOME/Documents"/*.hive.lock 2>/dev/null
                files_removed=$((files_removed + docs_hive_files))
            fi
            
            # Clear SharedPreferences
            if [ -d "$hive_dir" ]; then
                local prefs_count=$(find "$hive_dir" -name "shared_preferences*" 2>/dev/null | wc -l)
                if [ "$prefs_count" -gt 0 ]; then
                    rm -f "$hive_dir"/shared_preferences* 2>/dev/null
                    files_removed=$((files_removed + prefs_count))
                fi
            fi
            
            if [ "$files_removed" -gt 0 ]; then
                print_success "App data cleared (removed $files_removed file(s))"
            else
                print_info "No app data found (Hive boxes don't exist yet or already clean)"
            fi
        fi
        
        flutter run -d linux
    else
        print_error "Unknown platform: $platform"
        echo "Supported platforms: android, web, linux"
        exit 1
    fi
    
    cd "$ROOT_DIR"
}

cmd_run_web() {
    local mode="${1:-prod}"
    
    print_step "Running Flutter web app (mode: $mode)..."
    
    cd mobile
    
    if [ "$mode" = "dev" ]; then
        flutter run -d chrome --dart-define=FLUTTER_WEB_USE_SKIA=true
    else
        flutter run -d chrome --release
    fi
    
    cd "$ROOT_DIR"
}

cmd_test_app() {
    print_step "Running Flutter tests..."
    
    cd mobile
    
    if [ -n "$1" ]; then
        flutter test "$1"
    else
        flutter test
    fi
    
    cd "$ROOT_DIR"
    print_success "Tests complete"
}

cmd_test_server() {
    print_step "Testing server endpoints..."
    
    check_docker
    
    # Check if server is running
    if ! curl -f http://localhost:8000/health > /dev/null 2>&1; then
        print_error "Server is not running. Please start it first: $0 start-server"
        exit 1
    fi
    
    print_info "Testing health endpoint..."
    if curl -s http://localhost:8000/health | grep -q "OK"; then
        print_success "Health endpoint: OK"
    else
        print_error "Health endpoint: FAILED"
        exit 1
    fi
    
    print_info "Testing admin API..."
    if curl -s http://localhost:8000/api/admin/contacts > /dev/null 2>&1; then
        print_success "Admin API: OK"
    else
        print_warning "Admin API: Not responding"
    fi
    
    print_success "Server tests complete"
}

cmd_test_integration() {
    local test_file="${1:-integration_test/ui_integration_test.dart}"
    
    print_step "Running integration tests..."
    
    # Support test name shortcuts
    case "$test_file" in
        "stress"|"stress_test")
            test_file="integration_test/stress_test.dart"
            ;;
        "comprehensive"|"comprehensive_stress")
            test_file="integration_test/comprehensive_stress_test.dart"
            ;;
        "ui"|"ui_test")
            test_file="integration_test/ui_integration_test.dart"
            ;;
    esac
    
    # Run full-flash before tests
    print_info "Resetting system before tests..."
    cmd_full_flash > /dev/null 2>&1 || cmd_full_flash
    
    print_info "Running integration test: $test_file"
    cd mobile
    
    if command -v flutter &> /dev/null; then
        flutter test "$test_file" "${@:2}"
    else
        print_error "Flutter not found. Please install Flutter SDK."
        exit 1
    fi
    
    cd "$ROOT_DIR"
    print_success "Integration tests complete"
}

cmd_check() {
    print_info "Checking system requirements..."
    echo ""
    
    local all_ok=true
    
    # Check Docker
    if command -v docker &> /dev/null; then
        if docker ps > /dev/null 2>&1; then
            print_success "Docker: Installed and running"
        else
            print_error "Docker: Installed but not running"
            all_ok=false
        fi
    else
        print_error "Docker: Not installed"
        all_ok=false
    fi
    
    # Check Rust
    if command -v cargo &> /dev/null; then
        print_success "Rust: Installed ($(rustc --version 2>/dev/null | cut -d' ' -f2 || echo 'unknown'))"
    else
        print_error "Rust: Not installed"
        all_ok=false
    fi
    
    # Check Flutter
    if command -v flutter &> /dev/null; then
        print_success "Flutter: Installed ($(flutter --version 2>/dev/null | head -1 || echo 'unknown'))"
    else
        print_warning "Flutter: Not installed (required for mobile/web apps)"
    fi
    
    # Check PostgreSQL client
    if command -v psql &> /dev/null; then
        print_success "PostgreSQL client: Installed"
    else
        print_warning "PostgreSQL client: Not installed (optional, Docker is used)"
    fi
    
    # Check Python
    if command -v python3 &> /dev/null; then
        print_success "Python 3: Installed ($(python3 --version 2>/dev/null || echo 'unknown'))"
    else
        print_warning "Python 3: Not installed (required for import scripts)"
    fi
    
    echo ""
    if [ "$all_ok" = true ]; then
        print_success "All required tools are available"
    else
        print_error "Some required tools are missing"
        exit 1
    fi
}

cmd_install_deps() {
    print_step "Installing system dependencies..."
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
    
    case "$OS" in
        fedora|rhel|centos)
            print_info "Detected Fedora/RHEL/CentOS"
            print_info "Installing dependencies..."
            sudo dnf install -y docker docker-compose postgresql rust cargo || {
                print_error "Failed to install dependencies"
                exit 1
            }
            ;;
        ubuntu|debian)
            print_info "Detected Ubuntu/Debian"
            print_info "Installing dependencies..."
            sudo apt-get update
            sudo apt-get install -y docker.io docker-compose postgresql-client rust cargo || {
                print_error "Failed to install dependencies"
                exit 1
            }
            ;;
        *)
            print_warning "Unknown OS: $OS"
            print_info "Please install manually: Docker, Docker Compose, PostgreSQL client, Rust"
            exit 1
            ;;
    esac
    
    print_info "Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    print_success "Dependencies installed"
}

cmd_help() {
    cat <<EOF
Debt Tracker Management Script

Usage: $0 [--verbose|-v] [--no-build] [--clean] <command> [options]

Options:
  --verbose, -v              Show detailed output (default: minimal output)
  --no-build, --skip-build   Skip building server binary (faster, requires existing build)
  --clean                     Clear app data before running (Android only, for run-app command)

Commands:
  full-flash [backup.zip]     Complete reset + rebuild + optional import (recommended)
                              Use --no-build to skip server build (faster if binary exists)
  reset [backup.zip]          Reset database, optionally import data
  reset-db                    Reset PostgreSQL database only
  import <backup.zip>         Import data from Debitum backup (creates events)
  rebuild-projections         Rebuild projections from events (via API)
  
  start-services [name]       Start Docker services (postgres/redis/all)
  stop-services [name]         Stop Docker services
  start-server                 Start API server (Docker)
  start-prod                   Start production server (all services in Docker)
  start-dev                    Start development server (Rust directly, faster)
  stop-server                  Stop API server
  restart-server               Restart API server
  build                        Build the server (cargo build --release)
  
  run-app [platform] [device] Run Flutter app (android/web/linux)
  run-web [mode]              Run Flutter web app (dev/prod)
  test-app [test_file]         Run Flutter tests
  test-server                  Test server endpoints
  test-integration [test]      Run integration tests (with full-flash)
  
  check                        Check system requirements
  install-deps                 Install system dependencies (Linux)
  
  status                       Show system status
  logs                         Show server logs (tail -f)
  help                         Show this help message

Examples:
  $0 full-flash                      # Complete reset + rebuild (clean system)
  $0 full-flash backup.zip           # Complete reset + import + rebuild (recommended)
  $0 --no-build full-flash           # Fast reset (skip server build)
  $0 reset                           # Clean reset (no data)
  $0 import backup.zip               # Import data (keeps existing data)
  $0 start-prod                      # Start production (all in Docker)
  $0 start-dev                       # Start development (Rust directly, faster)
  $0 start-server                    # Start API server (Docker)
  $0 restart-server                  # Restart server
  $0 status                          # Check what's running
  $0 run-app android                 # Run Android app
  $0 run-app android --clean         # Run Android app with cleared data
  $0 run-web dev                     # Run web app in dev mode
  $0 test-app                        # Run all Flutter tests
  $0 test-server                     # Test server endpoints
  $0 test-integration ui             # Run UI integration tests
  $0 check                           # Check system requirements

Environment Variables:
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD  Database connection settings

Note: By default, only confirming messages and errors are shown. Use --verbose for detailed output.

EOF
}

# Main command dispatcher
case "${1:-help}" in
    full-flash|flash)
        cmd_full_flash "${2:-}"
        ;;
    reset)
        cmd_reset "${2:-}"
        ;;
    reset-db|reset-database)
        cmd_reset_database
        ;;
    import)
        if [ -z "$2" ]; then
            print_error "Import requires a backup file"
            echo "Usage: $0 import <backup.zip>"
            exit 1
        fi
        cmd_import "$2"
        ;;
    rebuild-projections|rebuild)
        cmd_rebuild_projections
        ;;
    start-services|start-service)
        cmd_start_services "${2:-}"
        ;;
    stop-services|stop-service)
        cmd_stop_services "${2:-}"
        ;;
    start-server|start)
        cmd_start_server
        ;;
    start-prod|prod)
        cmd_start_prod
        ;;
    start-dev|dev)
        cmd_start_dev
        ;;
    stop-server|stop)
        cmd_stop_server
        ;;
    restart-server|restart)
        cmd_restart_server
        ;;
    build)
        cmd_build
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    run-app)
        cmd_run_app "${2:-android}" "${3:-}"
        ;;
    run-web)
        cmd_run_web "${2:-prod}"
        ;;
    test-app)
        cmd_test_app "${2:-}"
        ;;
    test-server)
        cmd_test_server
        ;;
    test-integration)
        cmd_test_integration "${2:-integration_test/ui_integration_test.dart}" "${@:3}"
        ;;
    check)
        cmd_check
        ;;
    install-deps)
        cmd_install_deps
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        cmd_help
        exit 1
        ;;
esac
