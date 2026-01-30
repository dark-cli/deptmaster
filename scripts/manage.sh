#!/bin/bash
# Unified management script for Debt Tracker
# Usage: ./manage.sh <command> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Note: We don't cd here to avoid affecting the parent shell's working directory

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Database connection details
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-debt_tracker}"
DB_USER="${DB_USER:-debt_tracker}"
DB_PASSWORD="${DB_PASSWORD:-dev_password}"

export PGPASSWORD="$DB_PASSWORD"

# Flag variables
VERBOSE=false
SKIP_SERVER_BUILD=false
CLEAR_APP_DATA=false
WINDOW_SIZE=""  # Format: "WIDTHxHEIGHT" or "WIDTH HEIGHT"

# Define valid flags for each command
# Format: "command:flag1,flag2,flag3"
declare -A VALID_FLAGS=(
    ["reset-database-complete"]="verbose,skip-server-build"
    ["reset-database-only"]="verbose"
    ["import-backup"]="verbose"
    ["rebuild-database-projections"]="verbose"
    ["start-docker-services"]="verbose"
    ["stop-docker-services"]="verbose"
    ["start-server-direct"]="verbose"
    ["start-server-docker"]="verbose,skip-server-build"
    ["start-all-docker-production"]="verbose"
    ["stop-server"]="verbose"
    ["restart-server"]="verbose,skip-server-build"
    ["build-server"]="verbose"
    ["run-flutter-app"]="verbose,clear-app-data,window-size"
    ["run-flutter-web"]="verbose"
    ["test-flutter-app"]="verbose"
    ["test-api-server"]="verbose"
    ["test-flutter-integration"]="verbose,skip-server-build"
    ["set-admin-password"]="verbose"
    ["show-android-logs"]="verbose"
    ["status"]="verbose"
    ["logs"]="verbose"
    ["check"]="verbose"
    ["install-deps"]="verbose"
)

# Parse command line arguments for flags
ARGS=()
UNKNOWN_FLAGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --skip-server-build|--no-server-build)
            SKIP_SERVER_BUILD=true
            shift
            ;;
        --clear-app-data|--clean-app-data)
            CLEAR_APP_DATA=true
            shift
            ;;
        --window-size|--size)
            if [ -z "$2" ]; then
                print_error "--window-size requires a value (format: WIDTHxHEIGHT or WIDTH HEIGHT)"
                exit 1
            fi
            # Check if second argument is also a number (for "WIDTH HEIGHT" format)
            if [[ "$2" =~ ^[0-9]+$ ]] && [[ -n "$3" ]] && [[ "$3" =~ ^[0-9]+$ ]]; then
                WINDOW_SIZE="$2 $3"
                shift 3
            else
                WINDOW_SIZE="$2"
                shift 2
            fi
            ;;
        --*)
            UNKNOWN_FLAGS+=("$1")
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

validate_flags() {
    local command="$1"
    local valid_flags="${VALID_FLAGS[$command]:-}"
    
    # Check for unknown flags
    if [ ${#UNKNOWN_FLAGS[@]} -gt 0 ]; then
        print_error "Unknown flag(s): ${UNKNOWN_FLAGS[*]}"
        echo ""
        echo "Valid flags for '$command':"
        if [ -z "$valid_flags" ]; then
            echo "  (no flags supported for this command)"
        else
            IFS=',' read -ra FLAGS <<< "$valid_flags"
            for flag in "${FLAGS[@]}"; do
                case "$flag" in
                    "verbose")
                        echo "  --verbose, -v"
                        ;;
                    "skip-server-build")
                        echo "  --skip-server-build, --no-server-build"
                        ;;
                    "clear-app-data")
                        echo "  --clear-app-data, --clean-app-data"
                        ;;
                esac
            done
        fi
        exit 1
    fi
    
    # Check flag compatibility
    if [ -z "$valid_flags" ]; then
        # Command doesn't support any flags
        if [ "$VERBOSE" = true ] || [ "$SKIP_SERVER_BUILD" = true ] || [ "$CLEAR_APP_DATA" = true ]; then
            print_error "Command '$command' does not support flags"
            echo ""
            echo "This command does not accept any flags."
            exit 1
        fi
        return 0
    fi
    
    # Check each flag against valid flags
    IFS=',' read -ra FLAGS <<< "$valid_flags"
    
    if [ "$VERBOSE" = true ] && [[ ! " ${FLAGS[@]} " =~ " verbose " ]]; then
        print_error "Flag --verbose is not valid for command '$command'"
        exit 1
    fi
    
    if [ "$SKIP_SERVER_BUILD" = true ] && [[ ! " ${FLAGS[@]} " =~ " skip-server-build " ]]; then
        print_error "Flag --skip-server-build is not valid for command '$command'"
        echo ""
        echo "This flag is only valid for commands that build the server."
        exit 1
    fi
    
    if [ "$CLEAR_APP_DATA" = true ] && [[ ! " ${FLAGS[@]} " =~ " clear-app-data " ]]; then
        print_error "Flag --clear-app-data is not valid for command '$command'"
        echo ""
        echo "This flag is only valid for 'run-flutter-app' command."
        exit 1
    fi
    
    if [ -n "$WINDOW_SIZE" ] && [[ ! " ${FLAGS[@]} " =~ " window-size " ]]; then
        print_error "Flag --window-size is not valid for command '$command'"
        echo ""
        echo "This flag is only valid for 'run-flutter-app' command."
        exit 1
    fi
    
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
cmd_reset_database_complete() {
    local import_file="${1:-}"
    
    validate_flags "reset-database-complete"
    
    print_step "Complete Database Reset: Resetting system..."
    
    check_docker
    
    # Stop server if running
    pkill -f "debt-tracker-api" > /dev/null 2>&1 || true
    sleep 2
    
    # Reset database
    print_info "Resetting database..."
    cmd_reset_database_only
    
    # Start server (needed for import and rebuild)
    print_info "Starting server..."
    if [ "$SKIP_SERVER_BUILD" = true ]; then
        cmd_start_server_docker_no_build
    else
        cmd_start_server_docker
    fi
    
    # If import file provided, import data (import already rebuilds projections)
    if [ -n "$import_file" ]; then
        cmd_import_backup "$import_file"
    else
        print_step "Rebuilding projections..."
        cmd_rebuild_database_projections
    fi
    
    # Reset admin password to default (ensures admin access after reset)
    print_info "Resetting admin password..."
    local default_admin_password="admin123456"
    
    # Wait for server to be ready (needed for database connection)
    if ! wait_for_service "http://localhost:8000/health" "API server" 30 1; then
        print_warning "Server not ready, skipping admin password reset"
        print_warning "You may need to run: $0 set-admin-password admin $default_admin_password"
    else
        (cd "$ROOT_DIR/backend/rust-api" && cargo run --bin set_admin_password -- "admin" "$default_admin_password" > /dev/null 2>&1) && {
            print_success "Admin password reset to: $default_admin_password"
        } || {
            print_warning "Failed to reset admin password (may need to run manually)"
            print_warning "Run: $0 set-admin-password admin $default_admin_password"
        }
    fi
    
    print_success "Complete database reset finished!"
    echo ""
    echo "📧 Admin username: admin"
    echo "🔑 Admin password: $default_admin_password"
    echo ""
}

cmd_reset_database_only() {
    validate_flags "reset-database-only"
    
    local import_file="${1:-}"
    
    print_info "Resetting system (database only)..."
    
    check_docker
    
    # Stop server if running
    print_info "Stopping server..."
    pkill -f "debt-tracker-api" || true
    sleep 2
    
    # Reset database
    print_info "Resetting PostgreSQL database..."
    
    # Ensure PostgreSQL is running
    if ! docker ps | grep -q "debt_tracker_postgres"; then
        print_warning "PostgreSQL not running. Starting..."
        (cd "$ROOT_DIR/backend" && docker-compose up -d postgres > /dev/null 2>&1)
        sleep 5
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
    
    # Try sqlx first, but fall back to manual migrations quickly
    USE_SQLX=false
    if command -v sqlx &> /dev/null 2>&1; then
        USE_SQLX=true
    fi
    
    if [ "$USE_SQLX" = true ]; then
        if (cd "$ROOT_DIR/backend/rust-api" && timeout 10 sqlx migrate run --database-url "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" > /dev/null 2>&1); then
            print_info "Migrations completed via sqlx"
        else
            print_warning "sqlx migration failed or timed out, using manual migrations..."
            USE_SQLX=false
        fi
    fi
    
    # Manual migration fallback (always run if sqlx failed or doesn't exist)
    if [ "$USE_SQLX" = false ]; then
        print_info "Running migrations manually..."
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/001_initial_schema.sql" > /dev/null 2>&1
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/002_remove_transaction_settled.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/003_add_due_date.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/004_user_settings.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/005_create_default_user.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/006_add_username_to_contacts.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/007_add_idempotency_and_versions.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/008_add_projection_snapshots.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/009_add_login_logs.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/010_add_admin_users.sql" > /dev/null 2>&1 || true
    fi
    
    # Ensure only the "max" user exists (clean up any other users)
    print_info "Ensuring only default user exists..."
    # Generate password hash for "max" (bcrypt cost 12)
    # Hash: $2b$12$MzvHQ6CeZgenzzwkEV2WeeDQscVKQed1kTh8NxB7w2bXCXe2qFjxK is for "1234"
    # We'll use Python to generate a hash for "max" if available, otherwise use "1234" hash
    MAX_PASSWORD_HASH="\$2b\$12\$MzvHQ6CeZgenzzwkEV2WeeDQscVKQed1kTh8NxB7w2bXCXe2qFjxK"  # Default: "1234"
    if command -v python3 &> /dev/null; then
        # Try to generate hash for "max"
        NEW_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'max', bcrypt.gensalt(rounds=12)).decode())" 2>/dev/null)
        if [ -n "$NEW_HASH" ]; then
            MAX_PASSWORD_HASH="$NEW_HASH"
        fi
    fi
    
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1 <<EOF
-- Delete all users except "max"
DELETE FROM users_projection WHERE email != 'max';
-- Ensure "max" user exists with password "max" (migration 005 should have created it, but just in case)
-- Update password hash if user exists, or create new user
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM users_projection WHERE email = 'max') THEN
        UPDATE users_projection SET password_hash = '$MAX_PASSWORD_HASH' WHERE email = 'max';
    ELSE
        INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id)
        VALUES (gen_random_uuid(), 'max', '$MAX_PASSWORD_HASH', NOW(), 0);
    END IF;
END \$\$;
EOF
    print_success "Database reset complete"
    
    # If import file provided, import data
    if [ -n "$import_file" ]; then
        cmd_import_backup "$import_file"
    else
        print_info "No import file provided. Database is clean and ready."
    fi
}

cmd_import_backup() {
    validate_flags "import-backup"
    
    local backup_file="${1:-debitum-backup-2026-01-18T05_51_03.zip}"
    
    # Expand ~ to home directory
    if [[ "$backup_file" == ~* ]]; then
        backup_file="${backup_file/#\~/$HOME}"
    fi
    
    # Resolve backup file path (handle relative paths)
    if [[ "$backup_file" != /* ]]; then
        # Relative path - try multiple locations
        local resolved_file=""
        
        # 1. Try current directory
        if [ -f "$backup_file" ]; then
            resolved_file="$(cd "$(dirname "$backup_file")" && pwd)/$(basename "$backup_file")"
        # 2. Try root directory
        elif [ -f "$ROOT_DIR/$backup_file" ]; then
            resolved_file="$ROOT_DIR/$backup_file"
        # 3. Try scripts directory
        elif [ -f "$SCRIPT_DIR/$backup_file" ]; then
            resolved_file="$SCRIPT_DIR/$backup_file"
        # 4. Try root/scripts directory
        elif [ -f "$ROOT_DIR/scripts/$backup_file" ]; then
            resolved_file="$ROOT_DIR/scripts/$backup_file"
        fi
        
        if [ -n "$resolved_file" ]; then
            backup_file="$resolved_file"
        fi
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        echo ""
        echo "Usage: $0 import-backup <path-to-backup.zip>"
        echo ""
        echo "Searched in:"
        echo "  - Current directory: $(pwd)"
        echo "  - Root directory: $ROOT_DIR"
        echo "  - Scripts directory: $SCRIPT_DIR"
        echo ""
        echo "Looking for backup files in common locations..."
        (cd "$ROOT_DIR" && find . -maxdepth 2 -name "*.zip" -type f 2>/dev/null | head -10) || echo "No .zip files found"
        exit 1
    fi
    
    print_step "Importing data from: $backup_file"
    
    # Ensure server is running
    if ! curl -f http://localhost:8000/health > /dev/null 2>&1; then
        print_warning "Server not running. Starting..."
        if ! wait_for_service "http://localhost:8000/health" "API server" 60 2; then
            print_error "Failed to start server for import"
            exit 1
        fi
    fi
    
    # Check for Python script and dependencies
    local migrate_script="$ROOT_DIR/scripts/migrate_debitum_via_api_fast.py"
    if [ ! -f "$migrate_script" ]; then
        print_error "Migration script not found: $migrate_script"
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
        python3 "$migrate_script" "$backup_file" || {
            print_error "Failed to import data"
            print_error "Check the output above for details"
            exit 1
        }
    else
        # Show output on error, but suppress success messages
        if ! python3 "$migrate_script" "$backup_file" 2>&1 | tee /tmp/import_output.log | grep -E "(error|Error|ERROR|failed|Failed|FAILED)" || [ ${PIPESTATUS[0]} -eq 0 ]; then
            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                print_error "Failed to import data"
                print_error "Last 20 lines of output:"
                tail -20 /tmp/import_output.log | sed 's/^/  /'
                exit 1
            fi
        fi
    fi
    
    # Rebuild projections from events
    print_info "Rebuilding projections..."
    cmd_rebuild_database_projections
    
    print_success "Import complete!"
}

cmd_start_docker_services() {
    validate_flags "start-docker-services"
    
    print_info "Starting Docker services..."
    
    check_docker
    
    if [ "$1" = "postgres" ] || [ -z "$1" ]; then
        print_info "Starting PostgreSQL..."
        (cd "$ROOT_DIR/backend" && docker-compose up -d postgres > /dev/null 2>&1)
        sleep 5
    fi
    
    if [ "$1" = "redis" ] || [ -z "$1" ]; then
        print_info "Starting Redis..."
        (cd "$ROOT_DIR/backend" && docker-compose up -d redis > /dev/null 2>&1)
        sleep 3
    fi
    
    if [ -z "$1" ]; then
        print_info "Starting all services..."
        (cd "$ROOT_DIR/backend" && docker-compose up -d postgres redis > /dev/null 2>&1)
    fi
    if [ "$VERBOSE" = true ]; then
        print_success "Services started"
    fi
}

cmd_stop_docker_services() {
    validate_flags "stop-docker-services"
    
    print_info "Stopping Docker services..."
    
    check_docker
    
    if [ "$1" = "postgres" ]; then
        (cd "$ROOT_DIR/backend" && docker-compose stop postgres)
    elif [ "$1" = "redis" ]; then
        (cd "$ROOT_DIR/backend" && docker-compose stop redis)
    else
        (cd "$ROOT_DIR/backend" && docker-compose stop)
    fi
    print_success "Services stopped"
}

cmd_start_server_docker() {
    validate_flags "start-server-docker"
    
    print_info "Starting API server (runs directly on system, uses Docker for database/redis)..."
    
    # Stop any existing server
    pkill -f "debt-tracker-api" > /dev/null 2>&1 || true
    sleep 2
    
    # Ensure services are running
    cmd_start_docker_services
    
    # Build if needed
    if [ ! -f "$ROOT_DIR/backend/rust-api/target/release/debt-tracker-api" ]; then
        print_step "Building server (this may take a minute)..."
        if [ "$VERBOSE" = true ]; then
            (cd "$ROOT_DIR/backend/rust-api" && cargo build --release) || {
                print_error "Build failed. Check Rust version (requires 1.88+). Run: rustup update"
                exit 1
            }
        else
            if ! (cd "$ROOT_DIR/backend/rust-api" && cargo build --release 2>&1 | tee /tmp/cargo-build.log | grep -E "error|Finished|Compiling" | head -20); then
                print_error "Build failed. Check Rust version (requires 1.88+). Run: rustup update"
                print_error "Build log: /tmp/cargo-build.log"
                exit 1
            fi
        fi
    fi
    
    # Start server
    print_info "Starting server..."
    nohup "$ROOT_DIR/backend/rust-api/target/release/debt-tracker-api" > /tmp/debt-tracker-api.log 2>&1 &
    
    wait_for_service "http://localhost:8000/health" "API Server" 30 1
    if [ "$VERBOSE" = true ]; then
        print_success "Server started! Logs: /tmp/debt-tracker-api.log"
    fi
}

cmd_start_server_docker_no_build() {
    print_info "Starting API server (skipping build)..."
    
    # Stop any existing server
    pkill -f "debt-tracker-api" > /dev/null 2>&1 || true
    sleep 2
    
    # Ensure services are running
    cmd_start_docker_services > /dev/null 2>&1 || cmd_start_docker_services
    
    # Check if binary exists
    if [ ! -f "$ROOT_DIR/backend/rust-api/target/release/debt-tracker-api" ]; then
        print_error "Server binary not found. Please build first: $0 build-server"
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
    validate_flags "stop-server"
    
    print_info "Stopping API server..."
    
    # Stop Docker container if running
    (cd "$ROOT_DIR/backend" && docker-compose stop api 2>/dev/null) || true
    
    # Also stop any direct process
    pkill -f "debt-tracker-api" || true
    sleep 2
    
    print_success "Server stopped"
}

cmd_restart_server() {
    validate_flags "restart-server"
    
    print_info "Restarting API server..."
    
    cmd_stop_server
    sleep 2
    if [ "$SKIP_SERVER_BUILD" = true ]; then
        cmd_start_server_docker_no_build
    else
        cmd_start_server_docker
    fi
}

cmd_start_all_docker_production() {
    validate_flags "start-all-docker-production"
    
    print_step "Starting production server (all services in Docker containers)..."
    check_docker
    
    # Start all services including API in Docker
    print_info "Starting all Docker services (postgres, redis, api)..."
    (cd "$ROOT_DIR/backend" && docker-compose up -d)
    
    # Wait for services to be healthy
    print_info "Waiting for services to be ready..."
    wait_for_service "http://localhost:8000/health" "API Server" 60 2
    print_success "Production server started (all in Docker)"
    print_info "Server running at: http://localhost:8000"
    print_info "View logs: $0 logs"
    print_info "Stop with: docker-compose -f backend/docker-compose.yml stop api"
}

cmd_start_server_direct() {
    validate_flags "start-server-direct"
    
    print_step "Starting development server (runs directly on system, not in Docker)..."
    
    # Check if cargo is available
    if ! command -v cargo &> /dev/null; then
        print_error "Cargo not found. Please install Rust: https://rustup.rs/"
        exit 1
    fi
    
    # Start services (postgres, redis) if not running
    cmd_start_docker_services
    
    # Stop Docker API container if running (to free port 8000)
    if docker ps --format '{{.Names}}' | grep -q '^debt_tracker_api$'; then
        print_info "Stopping Docker API container to free port 8000..."
        (cd "$ROOT_DIR/backend" && docker-compose stop api 2>/dev/null) || true
    fi
    
    # Check if port is available and try to stop what's using it
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        print_warning "Port 8000 is already in use. Attempting to stop it..."
        
        # Try to stop Docker API container
        if docker ps --format '{{.Names}}' | grep -q '^debt_tracker_api$'; then
            print_info "Stopping Docker API container..."
            (cd "$ROOT_DIR/backend" && docker-compose stop api 2>/dev/null) || true
            sleep 2
        fi
        
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
    
    # Use cargo-watch if available, otherwise regular cargo run
    if command -v cargo-watch &> /dev/null; then
        print_info "Using cargo-watch for auto-reload..."
        print_info "Watching: Rust source files (.rs) and static files (.html, .js)"
        print_info "Note: Static file changes require recompilation (will auto-restart)"
        # Watch both Rust files and static files
        (cd "$ROOT_DIR/backend/rust-api" && cargo watch \
            --watch "$ROOT_DIR/backend/rust-api/src" \
            --watch "$ROOT_DIR/backend/rust-api/static" \
            -x 'run --bin debt-tracker-api')
    else
        print_warning "cargo-watch not installed. Install for auto-reload: cargo install cargo-watch"
        print_info "Note: Static file changes require restarting the server"
        (cd "$ROOT_DIR/backend/rust-api" && cargo run --bin debt-tracker-api)
    fi
}

cmd_build_server() {
    validate_flags "build-server"
    
    print_info "Building server..."
    
    (cd "$ROOT_DIR/backend/rust-api" && cargo build --release)
    
    print_success "Build complete"
}

cmd_status() {
    validate_flags "status"
    
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
    validate_flags "logs"
    
    if [ -f "/tmp/debt-tracker-api.log" ]; then
        tail -f /tmp/debt-tracker-api.log
    else
        print_error "Log file not found. Server may not be running."
    fi
}

cmd_rebuild_database_projections() {
    validate_flags "rebuild-database-projections"
    
    print_step "Rebuilding projections..."
    
    # Ensure server is running
    if ! curl -f http://localhost:8000/health > /dev/null 2>&1; then
        print_error "Server is not running. Please start the server first: $0 start-server-docker"
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

cmd_run_flutter_app() {
    validate_flags "run-flutter-app"
    
    local platform="${1:-android}"
    local mode="${2:-dev}"
    local device_id="${3:-}"
    
    # Normalize mode names (dev/debug are the same)
    case "$mode" in
        dev|debug)
            mode="debug"
            mode_flag=""
            ;;
        release)
            mode_flag="--release"
            ;;
        profile)
            mode_flag="--profile"
            ;;
        *)
            print_error "Unknown mode: $mode"
            echo "Supported modes: dev, debug, release, profile"
            echo "Usage: $0 run-flutter-app <platform> [mode] [device]"
            exit 1
            ;;
    esac
    
    print_step "Running Flutter app ($platform, mode: $mode)..."
    
    # Build flutter run command with mode flag
    local flutter_cmd="flutter run"
    if [ -n "$mode_flag" ]; then
        flutter_cmd="$flutter_cmd $mode_flag"
    fi
    
    if [ "$platform" = "android" ]; then
        # Check if adb is available
        if ! command -v adb &> /dev/null; then
            print_error "adb not found. Please install Android SDK platform-tools."
            exit 1
        fi
        
        # Check if Android device is connected
        if ! adb devices | grep -q "device$"; then
            print_error "No Android device connected. Please connect a device or start an emulator."
            echo ""
            echo "Available devices:"
            adb devices
            exit 1
        fi
        
        # Clean app data if --clear-app-data flag is set
        if [ "$CLEAR_APP_DATA" = true ]; then
            print_info "Clearing app data via adb..."
            
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
        
        # Run on Android device (explicitly specify android to avoid fallback to Linux)
        if [ -n "$device_id" ]; then
            (cd "$ROOT_DIR/mobile" && $flutter_cmd -d "$device_id")
        else
            # List available devices and use the first Android device
            local android_device=$(adb devices | grep "device$" | head -1 | awk '{print $1}')
            if [ -n "$android_device" ]; then
                print_info "Running on Android device: $android_device"
                (cd "$ROOT_DIR/mobile" && $flutter_cmd -d "$android_device")
            else
                print_error "No Android device found"
                exit 1
            fi
        fi
    elif [ "$platform" = "web" ]; then
        if [ "$CLEAR_APP_DATA" = true ]; then
            print_warning "--clear-app-data flag is only supported for Android and Linux platforms"
        fi
        if [ -n "$device_id" ]; then
            (cd "$ROOT_DIR/mobile" && $flutter_cmd -d "$device_id")
        else
            (cd "$ROOT_DIR/mobile" && $flutter_cmd -d chrome)
        fi
    elif [ "$platform" = "linux" ]; then
        # Clean app data if --clear-app-data flag is set
        if [ "$CLEAR_APP_DATA" = true ]; then
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
        
        # Launch Flutter app and configure window for Hyprland
        if [ -n "$device_id" ]; then
            (cd "$ROOT_DIR/mobile" && $flutter_cmd -d "$device_id")
        else
            # Check if running on Hyprland
            if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || command -v hyprctl &> /dev/null; then
                # Parse window size (default to phone size: 390x844)
                local window_width=390
                local window_height=844
                
                if [ -n "$WINDOW_SIZE" ]; then
                    # Parse WINDOW_SIZE (supports "WIDTHxHEIGHT" or "WIDTH HEIGHT")
                    if [[ "$WINDOW_SIZE" =~ ^([0-9]+)[xX]([0-9]+)$ ]]; then
                        window_width="${BASH_REMATCH[1]}"
                        window_height="${BASH_REMATCH[2]}"
                    elif [[ "$WINDOW_SIZE" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
                        window_width="${BASH_REMATCH[1]}"
                        window_height="${BASH_REMATCH[2]}"
                    else
                        print_error "Invalid window size format: $WINDOW_SIZE"
                        echo "Expected format: WIDTHxHEIGHT (e.g., 800x600) or WIDTH HEIGHT (e.g., 800 600)"
                        exit 1
                    fi
                    
                    if [ "$window_width" -lt 100 ] || [ "$window_height" -lt 100 ]; then
                        print_error "Window size too small. Minimum: 100x100"
                        exit 1
                    fi
                    
                    print_info "Using custom window size: ${window_width}x${window_height}"
                else
                    print_info "Using default phone size: ${window_width}x${window_height}"
                fi
                
                print_info "Detected Hyprland - will configure window to float with fixed size"
                
                # Function to configure window in background
                configure_hyprland_window() {
                    local width=$1
                    local height=$2
                    local max_wait=15
                    local waited=0
                    local window_found=false
                    
                    while [ $waited -lt $max_wait ]; do
                        sleep 0.5
                        waited=$((waited + 1))
                        
                        # Check if the app window exists (by class or title)
                        local window_exists=false
                        if command -v jq &> /dev/null; then
                            # Use jq if available
                            local window_info=$(hyprctl clients -j 2>/dev/null | \
                                jq -r '.[] | select(.class == "debt_tracker_mobile" or (.title | test("debt_tracker_mobile|Debt Tracker"; "i")))' 2>/dev/null | head -1)
                            if [ -n "$window_info" ] && [ "$window_info" != "null" ]; then
                                window_exists=true
                            fi
                        else
                            # Fallback: check with grep
                            if hyprctl clients 2>/dev/null | grep -qi "debt_tracker_mobile"; then
                                window_exists=true
                            fi
                        fi
                        
                        if [ "$window_exists" = true ]; then
                            window_found=true
                            
                            # Focus the window first (by class name)
                            hyprctl dispatch focuswindow "class:debt_tracker_mobile" 2>/dev/null || \
                            hyprctl dispatch focuswindow "title:.*debt_tracker_mobile.*" 2>/dev/null || true
                            sleep 0.3
                            
                            # Set window to floating mode (works on active window)
                            hyprctl dispatch togglefloating 2>/dev/null || true
                            sleep 0.2
                            
                            # Resize window to specified size
                            hyprctl dispatch resizeactive $width $height 2>/dev/null || true
                            sleep 0.2
                            
                            # Center the window
                            hyprctl dispatch centerwindow 2>/dev/null || true
                            
                            if [ "$VERBOSE" = true ]; then
                                echo "Window configured: floating mode, size ${width}x${height}"
                            fi
                            break
                        fi
                    done
                    
                    if [ "$window_found" = false ] && [ "$VERBOSE" = true ]; then
                        echo "Warning: Could not find window to configure"
                    fi
                }
                
                # Start window configuration in background with size parameters
                configure_hyprland_window $window_width $window_height &
                local config_pid=$!
                
                # Start window configuration in background
                configure_hyprland_window &
                local config_pid=$!
                
                # Launch Flutter (foreground)
                (cd "$ROOT_DIR/mobile" && $flutter_cmd -d linux)
                
                # Clean up background process if still running
                kill $config_pid 2>/dev/null || true
            else
                # Not on Hyprland, just run normally
                (cd "$ROOT_DIR/mobile" && $flutter_cmd -d linux)
            fi
        fi
    else
        print_error "Unknown platform: $platform"
        echo "Supported platforms: android, web, linux"
        echo "Usage: $0 run-flutter-app <platform> [mode] [device]"
        echo "Modes: dev (default), debug, release, profile"
        exit 1
    fi
}

cmd_run_flutter_web() {
    validate_flags "run-flutter-web"
    
    local mode="${1:-prod}"
    
    print_step "Running Flutter web app (mode: $mode)..."
    
    if [ "$mode" = "dev" ]; then
        (cd "$ROOT_DIR/mobile" && flutter run -d chrome --dart-define=FLUTTER_WEB_USE_SKIA=true)
    else
        (cd "$ROOT_DIR/mobile" && flutter run -d chrome --release)
    fi
}

cmd_show_android_logs() {
    validate_flags "show-android-logs"
    
    print_step "Showing filtered Android logs (Flutter/Dart only)..."
    
    # Check if adb is available
    if ! command -v adb &> /dev/null; then
        print_error "adb not found. Please install Android SDK platform-tools."
        exit 1
    fi
    
    # Check if Android device is connected
    if ! adb devices | grep -q "device$"; then
        print_error "No Android device connected. Please connect a device or start an emulator."
        echo ""
        echo "Available devices:"
        adb devices
        exit 1
    fi
    
    print_info "Filtering logs to show only Flutter/Dart output..."
    print_info "Press Ctrl+C to stop filtering"
    echo ""
    
    # Run adb logcat with Flutter/Dart filters
    adb logcat -s flutter:D DartVM:D
}

cmd_test_flutter_app() {
    validate_flags "test-flutter-app"
    
    print_step "Running Flutter tests..."
    
    if [ -n "$1" ]; then
        (cd "$ROOT_DIR/mobile" && flutter test "$1")
    else
        (cd "$ROOT_DIR/mobile" && flutter test)
    fi
    
    print_success "Tests complete"
}

cmd_test_api_server() {
    validate_flags "test-api-server"
    
    print_step "Testing server endpoints..."
    
    check_docker
    
    # Check if server is running
    if ! curl -f http://localhost:8000/health > /dev/null 2>&1; then
        print_error "Server is not running. Please start it first: $0 start-server-docker"
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

cmd_test_flutter_integration() {
    validate_flags "test-flutter-integration"
    
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
    
    # Run complete database reset before tests
    print_info "Resetting system before tests..."
    cmd_reset_database_complete > /dev/null 2>&1 || cmd_reset_database_complete
    
    print_info "Running integration test: $test_file"
    
    if command -v flutter &> /dev/null; then
        (cd "$ROOT_DIR/mobile" && flutter test "$test_file" "${@:2}")
    else
        print_error "Flutter not found. Please install Flutter SDK."
        exit 1
    fi
    
    print_success "Integration tests complete"
}

cmd_check() {
    validate_flags "check"
    
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
    validate_flags "install-deps"
    
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

cmd_set_admin_password() {
    validate_flags "set-admin-password"
    
    local username="${1:-admin}"
    local password="${2:-}"
    
    if [ -z "$password" ]; then
        print_error "Password is required"
        echo ""
        echo "Usage: $0 set-admin-password [username] <password>"
        echo "Example: $0 set-admin-password admin mynewpassword123"
        exit 1
    fi
    
    if [ ${#password} -lt 8 ]; then
        print_error "Password must be at least 8 characters"
        exit 1
    fi
    
    print_step "Setting admin password for user: $username"
    
    check_docker
    
    # Ensure PostgreSQL is running
    if ! docker ps | grep -q "debt_tracker_postgres"; then
        print_warning "PostgreSQL not running. Starting..."
        (cd "$ROOT_DIR/backend" && docker-compose up -d postgres > /dev/null 2>&1)
        sleep 5
    fi
    
    # Use Rust binary to set admin password (more reliable)
    print_info "Setting admin password..."
    
    if (cd "$ROOT_DIR/backend/rust-api" && cargo run --bin set_admin_password -- "$username" "$password" 2>&1 | grep -q "✅"); then
        print_success "Admin password updated successfully!"
        echo ""
        echo "📧 Username: $username"
        echo "🔑 Password: $password"
        echo ""
        echo "You can now login to the admin panel with these credentials."
    else
        print_error "Failed to update admin password"
        exit 1
    fi
}

cmd_help() {
    cat <<EOF
Debt Tracker Management Script

Usage: $0 [flags] <command> [options]

Flags:
  --verbose, -v                    Show detailed output (default: minimal output)
  --skip-server-build              Skip building server binary (only for commands that build)
  --clear-app-data                 Clear app data before running (only for run-flutter-app)
  --window-size, --size WIDTHxHEIGHT
                                  Set window size for Linux app (only for run-flutter-app linux)
                                  Format: WIDTHxHEIGHT (e.g., 800x600) or WIDTH HEIGHT
                                  Default: 390x844 (phone size)

Database Commands:
  reset-database-complete [backup.zip]
                                  Complete reset + rebuild + optional import (recommended)
                                  Use --skip-server-build to skip server build (faster if binary exists)
  reset-database-only [backup.zip]
                                  Reset PostgreSQL database only, optionally import data
  import-backup <backup.zip>       Import data from Debitum backup (creates events)
  rebuild-database-projections      Rebuild projections from events (via API)

Docker Services Commands:
  start-docker-services [name]     Start Docker services (postgres/redis/all)
  stop-docker-services [name]      Stop Docker services

Server Commands:
  start-server-docker              Start API server (runs directly on system, uses Docker for database/redis)
                                  Use --skip-server-build to skip build if binary exists
  start-server-direct              Start development server (runs directly, not in Docker, with auto-reload)
  start-all-docker-production      Start production server (all services in Docker containers)
  stop-server                      Stop API server (stops both Docker and direct processes)
  restart-server                   Restart API server
                                  Use --skip-server-build to skip build if binary exists
  build-server                     Build the server (cargo build --release)

Flutter App Commands:
  run-flutter-app [platform] [mode] [device]
                                  Run Flutter app (android/web/linux)
                                  Mode: dev (default), debug, release, profile
                                  Use --clear-app-data to clear app data before running
                                  Use --window-size WIDTHxHEIGHT to set custom size (Linux only)
                                  On Hyprland: automatically floats window with fixed size
  show-android-logs                Show filtered Android logs (Flutter/Dart only)
                                  Use this in a separate terminal while Flutter app is running
  run-flutter-web [mode]           Run Flutter web app (dev/prod)
  test-flutter-app [test_file]     Run Flutter tests
  test-flutter-integration [test]   Run Flutter integration tests (with database reset)
                                  Use --skip-server-build to skip server build during reset

Testing Commands:
  test-api-server                  Test API server endpoints

Admin Commands:
  set-admin-password [user] <pass> Set admin panel login password (min 8 chars)

System Commands:
  check                            Check system requirements
  install-deps                     Install system dependencies (Linux)
  status                           Show system status
  logs                             Show server logs (tail -f)
  help                             Show this help message

Examples:
  $0 reset-database-complete                      # Complete reset + rebuild (clean system)
  $0 reset-database-complete backup.zip           # Complete reset + import + rebuild (recommended)
  $0 --skip-server-build reset-database-complete  # Fast reset (skip server build)
  $0 reset-database-only                          # Clean reset (no data)
  $0 import-backup backup.zip                     # Import data (keeps existing data)
  $0 set-admin-password admin mypass              # Set admin panel login password
  $0 start-all-docker-production                  # Start production (all in Docker)
  $0 start-server-direct                          # Start development (Rust directly, faster, auto-reload)
  $0 start-server-docker                          # Start server (runs on system, uses Docker for DB/Redis)
  $0 restart-server                               # Restart server
  $0 status                                        # Check what's running
  $0 run-flutter-app android                      # Run Android app (dev mode)
  $0 run-flutter-app android release              # Run Android app in release mode
  $0 run-flutter-app linux dev                    # Run Linux app in dev mode (phone size, floating on Hyprland)
  $0 run-flutter-app linux dev --window-size 800x600  # Run Linux app with custom size
  $0 run-flutter-app android --clear-app-data     # Run Android app with cleared data
  $0 run-flutter-app android release <device-id>  # Run Android app in release mode on specific device
  $0 show-android-logs                            # Show filtered Android logs (in separate terminal)
  $0 run-flutter-web dev                          # Run web app in dev mode
  $0 test-flutter-app                             # Run all Flutter tests
  $0 test-api-server                              # Test server endpoints
  $0 test-flutter-integration ui                  # Run UI integration tests
  $0 check                                         # Check system requirements

Environment Variables:
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD  Database connection settings

Note: By default, only confirming messages and errors are shown. Use --verbose for detailed output.

EOF
}

# Main command dispatcher
COMMAND="${1:-help}"

case "$COMMAND" in
    reset-database-complete)
        cmd_reset_database_complete "${2:-}"
        ;;
    reset-database-only)
        cmd_reset_database_only "${2:-}"
        ;;
    import-backup)
        if [ -z "$2" ]; then
            print_error "Import requires a backup file"
            echo "Usage: $0 import-backup <backup.zip>"
            exit 1
        fi
        cmd_import_backup "$2"
        ;;
    rebuild-database-projections)
        cmd_rebuild_database_projections
        ;;
    start-docker-services)
        cmd_start_docker_services "${2:-}"
        ;;
    stop-docker-services)
        cmd_stop_docker_services "${2:-}"
        ;;
    start-server-docker)
        cmd_start_server_docker
        ;;
    start-all-docker-production)
        cmd_start_all_docker_production
        ;;
    start-server-direct)
        cmd_start_server_direct
        ;;
    stop-server)
        cmd_stop_server
        ;;
    restart-server)
        cmd_restart_server
        ;;
    build-server)
        cmd_build_server
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    run-flutter-app)
        cmd_run_flutter_app "${2:-android}" "${3:-dev}" "${4:-}"
        ;;
    show-android-logs)
        cmd_show_android_logs
        ;;
    run-flutter-web)
        cmd_run_flutter_web "${2:-prod}"
        ;;
    test-flutter-app)
        cmd_test_flutter_app "${2:-}"
        ;;
    test-api-server)
        cmd_test_api_server
        ;;
    test-flutter-integration)
        cmd_test_flutter_integration "${2:-integration_test/ui_integration_test.dart}" "${@:3}"
        ;;
    check)
        cmd_check
        ;;
    install-deps)
        cmd_install_deps
        ;;
    set-admin-password)
        cmd_set_admin_password "${2:-admin}" "${3:-}"
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        echo ""
        cmd_help
        exit 1
        ;;
esac
