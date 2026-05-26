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
CYAN='\033[0;36m'
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
SEPARATE_INSTANCE=false  # Linux: run with isolated XDG data (no shared data with other instances)
INSTANCES=""  # When set with --instances N (and Linux + separate-instance), spawn N instances and show unified log viewer

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
    ["run-flutter-app"]="verbose,clear-app-data,window-size,separate-instance,instances"
    ["run-flutter-web"]="verbose"
    ["test-integration"]="verbose"
    ["test-api-server"]="verbose"
    ["test-flutter-integration"]="verbose,skip-server-build"
    ["test-flutter-integration-multi-app"]="verbose"
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
        --separate-instance|--sandbox)
            SEPARATE_INSTANCE=true
            shift
            ;;
        --instances)
            if [ -z "$2" ] || ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 9 ]; then
                echo -e "${RED}❌ --instances requires a number from 1 to 9${NC}" >&2
                exit 1
            fi
            INSTANCES="$2"
            shift 2
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
                    "window-size")
                        echo "  --window-size, --size WIDTHxHEIGHT"
                        ;;
                    "separate-instance")
                        echo "  --separate-instance, --sandbox"
                        ;;
                    "instances")
                        echo "  --instances N (N=1..9, spawn N instances; requires --separate-instance on Linux)"
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
    
    if [ "$SEPARATE_INSTANCE" = true ] && [[ ! " ${FLAGS[@]} " =~ " separate-instance " ]]; then
        print_error "Flag --separate-instance is not valid for command '$command'"
        echo ""
        echo "This flag is only valid for 'run-flutter-app' command."
        exit 1
    fi

    if [ -n "$INSTANCES" ] && [[ ! " ${FLAGS[@]} " =~ " instances " ]]; then
        print_error "Flag --instances is not valid for command '$command'"
        echo ""
        echo "This flag is only valid for 'run-flutter-app' command (Linux + --separate-instance)."
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
    local import_username="${2:-}"
    local import_wallet="${3:-}"
    
    validate_flags "reset-database-complete"
    
    # When importing, username and wallet are required
    if [ -n "$import_file" ]; then
        if [ -z "$import_username" ] || [ -z "$import_wallet" ]; then
            print_error "Username and wallet are required when importing from a backup."
            echo ""
            echo "Usage: $0 reset-database-complete <backup.zip> <username> <wallet>"
            echo "  username  User to import as (e.g. max)"
            echo "  wallet    Wallet name to import into (created if it does not exist)"
            exit 1
        fi
    fi
    
    print_step "Complete Database Reset: Resetting system..."
    
    check_docker
    
    # Stop server if running
    pkill -f "debt-tracker-api" > /dev/null 2>&1 || true
    sleep 2
    
    # Reset database (no import here; we import after server is started)
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
        cmd_import_backup "$import_file" "$import_username" "$import_wallet"
    else
        print_step "Rebuilding projections..."
        cmd_rebuild_database_projections
    fi
    
    # Reset admin password to default (ensures admin access after reset)
    # Must be at least 8 chars (set_admin_password binary requirement)
    print_info "Resetting admin password..."
    local default_admin_password="admin123"
    
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
    echo "📧 Regular user: max"
    echo "🔑 Regular user password: 12345678"
    echo ""
}

cmd_reset_database_only() {
    validate_flags "reset-database-only"
    
    local import_file="${1:-}"
    local import_username="${2:-}"
    local import_wallet="${3:-}"
    
    # When importing, username and wallet are required
    if [ -n "$import_file" ]; then
        if [ -z "$import_username" ] || [ -z "$import_wallet" ]; then
            print_error "Username and wallet are required when importing from a backup."
            echo ""
            echo "Usage: $0 reset-database-only <backup.zip> <username> <wallet>"
            echo "  username  User to import as (e.g. max)"
            echo "  wallet    Wallet name to import into (created if it does not exist)"
            exit 1
        fi
    fi
    
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
    # Generate password hash for "12345678" (bcrypt cost 12) to match the password we advertise
    MAX_USER_PASSWORD="12345678"
    MAX_PASSWORD_HASH="\$2b\$12\$MzvHQ6CeZgenzzwkEV2WeeDQscVKQed1kTh8NxB7w2bXCXe2qFjxK"  # Fallback: "1234" if bcrypt unavailable
    if command -v python3 &> /dev/null; then
        NEW_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'$MAX_USER_PASSWORD', bcrypt.gensalt(rounds=12)).decode())" 2>/dev/null)
        if [ -n "$NEW_HASH" ]; then
            MAX_PASSWORD_HASH="$NEW_HASH"
        fi
    fi
    
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1 <<EOF
-- Delete all users except "max"
DELETE FROM users_projection WHERE email != 'max';
-- Ensure "max" user exists with password 12345678 (migration 005 may have created it, but we set the hash)
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
    
    # Run wallet migrations after "max" exists so default wallet is assigned to max (not to pre-005 user)
    if [ "$USE_SQLX" = false ]; then
        print_info "Running wallet migrations (011, 012)..."
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/011_create_wallets.sql" > /dev/null 2>&1 || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < "$ROOT_DIR/backend/rust-api/migrations/012_add_wallet_id_to_tables.sql" > /dev/null 2>&1 || true
    else
        # Sqlx already ran 001-012; block above may have replaced users. Ensure every user has a wallet.
        print_info "Ensuring all users have a wallet..."
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1 <<WALLETEOF
INSERT INTO wallet_users (wallet_id, user_id, role)
SELECT w.id, u.id, 'owner' FROM users_projection u
CROSS JOIN (SELECT id FROM wallets WHERE is_active = true LIMIT 1) w
WHERE NOT EXISTS (SELECT 1 FROM wallet_users wu WHERE wu.user_id = u.id);
WALLETEOF
    fi
    
    print_success "Database reset complete"
    
    # If import file provided, import data (server must be running; cmd_import_backup will start it if needed)
    if [ -n "$import_file" ]; then
        cmd_import_backup "$import_file" "$import_username" "$import_wallet"
    else
        print_info "No import file provided. Database is clean and ready."
    fi
}

cmd_import_backup() {
    validate_flags "import-backup"
    
    local backup_file="${1:-}"
    local import_username="${2:-}"
    local import_wallet="${3:-}"
    
    # Backup file is required
    if [ -z "$backup_file" ]; then
        print_error "Backup file is required."
        echo "Usage: $0 import-backup <path-to-backup.zip> <username> <wallet>"
        exit 1
    fi
    
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
    
    # Username and wallet are required for import
    if [ -z "$import_username" ] || [ -z "$import_wallet" ]; then
        print_error "Username and wallet are required for import."
        echo ""
        echo "Usage: $0 import-backup <path-to-backup.zip> <username> <wallet>"
        echo "  username  User to import as (must exist)"
        echo "  wallet    Wallet name to import into (created if it does not exist)"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        echo ""
        echo "Usage: $0 import-backup <path-to-backup.zip> <username> <wallet>"
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
    
    print_step "Importing data from: $backup_file (user: $import_username, wallet: $import_wallet)"
    
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
    
    # Run migration (username and wallet required; wallet is created if it does not exist)
    print_info "Running migration via API..."
    if [ "$VERBOSE" = true ]; then
        python3 "$migrate_script" "$backup_file" "$import_username" "$import_wallet" || {
            print_error "Failed to import data"
            print_error "Check the output above for details"
            exit 1
        }
    else
        # Show output on error, but suppress success messages
        if ! python3 "$migrate_script" "$backup_file" "$import_username" "$import_wallet" 2>&1 | tee /tmp/import_output.log | grep -E "(error|Error|ERROR|failed|Failed|FAILED)" || [ ${PIPESTATUS[0]} -eq 0 ]; then
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
    
    # Build so we run the latest code (use --skip-server-build to skip and use existing binary)
    if [ "$SKIP_SERVER_BUILD" != true ]; then
        print_step "Building server (this may take a minute)..."
        if [ "$VERBOSE" = true ]; then
            (cd "$ROOT_DIR/backend/rust-api" && cargo build --release) || {
                print_error "Build failed. Check Rust version (requires 1.88+). Run: rustup update"
                exit 1
            }
        else
            (cd "$ROOT_DIR/backend/rust-api" && cargo build --release 2>&1 | tee /tmp/cargo-build.log) || true
            if [ "${PIPESTATUS[0]}" -ne 0 ]; then
                print_error "Build failed. Check Rust version (requires 1.88+). Run: rustup update"
                print_error "Build log: /tmp/cargo-build.log"
                exit 1
            fi
        fi
    elif [ ! -f "$ROOT_DIR/backend/rust-api/target/release/debt-tracker-api" ]; then
        print_error "Server binary not found and --skip-server-build was used. Build first: $0 build-server"
        exit 1
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
    export RATE_LIMIT_REQUESTS="${RATE_LIMIT_REQUESTS:-0}"
    
    # Run server with cargo. Use cargo-watch only if explicitly requested and the real binary exists.
    CARGO_WATCH_BIN=""
    if [[ -n "${USE_CARGO_WATCH:-}" ]] || [[ -n "${CARGO_WATCH:-}" ]]; then
        if [[ -x "$HOME/.cargo/bin/cargo-watch" ]]; then
            CARGO_WATCH_BIN="$HOME/.cargo/bin/cargo-watch"
        elif command -v cargo-watch &> /dev/null; then
            CARGO_WATCH_BIN="cargo-watch"
        fi
    fi
    if [[ -n "$CARGO_WATCH_BIN" ]]; then
        print_info "Using cargo-watch for auto-reload (USE_CARGO_WATCH=1)"
        (cd "$ROOT_DIR/backend/rust-api" && "$CARGO_WATCH_BIN" \
            --watch "$ROOT_DIR/backend/rust-api/src" \
            --watch "$ROOT_DIR/backend/rust-api/static" \
            -x 'run --bin debt-tracker-api')
    else
        print_info "Starting server (restart manually after code changes)"
        print_info "For auto-reload: USE_CARGO_WATCH=1 $0 start-server-direct (after: cargo install cargo-watch)"
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

# Resolve Flutter binary: FLUTTER_CMD, then PATH, then FLUTTER_SDK_ROOT, then common path.
# Outputs the command (e.g. "flutter" or "/path/to/flutter") or exits with 1 if not found.
resolve_flutter_cmd() {
    if [ -n "${FLUTTER_CMD:-}" ]; then
        echo "$FLUTTER_CMD"
        return 0
    fi
    if command -v flutter &> /dev/null; then
        echo "flutter"
        return 0
    fi
    if [ -n "${FLUTTER_SDK_ROOT:-}" ] && [ -x "$FLUTTER_SDK_ROOT/bin/flutter" ]; then
        echo "$FLUTTER_SDK_ROOT/bin/flutter"
        return 0
    fi
    if [ -x "$HOME/flutter/bin/flutter" ]; then
        echo "$HOME/flutter/bin/flutter"
        return 0
    fi
    return 1
}

# Build and prepare Rust bridge so Dart and native lib are in sync. Call before run-flutter-app.
prepare_rust_bridge_for_flutter() {
    local platform="$1"
    local crate_dir="$ROOT_DIR/crates/debitum_client_core"
    local jni_libs_dir="$ROOT_DIR/mobile/android/app/src/main/jniLibs"
    
    print_info "Preparing Rust bridge (codegen + build for $platform)..."
    
    # 1. Regenerate Dart/Rust bindings so content hash matches
    if [ ! -f "$SCRIPT_DIR/codegen-rust-bridge.sh" ]; then
        print_error "codegen script not found: $SCRIPT_DIR/codegen-rust-bridge.sh"
        exit 1
    fi
    "$SCRIPT_DIR/codegen-rust-bridge.sh" 2>/dev/null || {
        print_error "Flutter Rust Bridge codegen failed. Install: cargo install flutter_rust_bridge_codegen"
        exit 1
    }
    
    # 2. Build Rust for the target platform
    if [ "$platform" = "android" ]; then
        if ! command -v cargo-ndk &>/dev/null; then
            print_error "cargo-ndk is required for Android but is not installed."
            echo "Install with: cargo install cargo-ndk"
            echo "Then add Android targets: rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android"
            echo "Ensure Android NDK is installed (e.g. Android Studio SDK Manager) and ANDROID_NDK_HOME is set."
            exit 1
        fi
        # Try to find NDK if ANDROID_NDK_HOME not set (cargo-ndk uses ANDROID_NDK_HOME)
        if [ -z "${ANDROID_NDK_HOME:-}" ]; then
            _sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
            # Prefer NDK installed by scripts/install-android-ndk.sh (r27d LTS)
            if [ -d "$_sdk/ndk/android-ndk-r27d" ] && { [ -f "$_sdk/ndk/android-ndk-r27d/ndk-build" ] || [ -f "$_sdk/ndk/android-ndk-r27d/source.properties" ]; }; then
                export ANDROID_NDK_HOME="$_sdk/ndk/android-ndk-r27d"
                print_info "Using NDK: $ANDROID_NDK_HOME"
            else
                for sdk in "$HOME/Android/Sdk" "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
                    [ -z "$sdk" ] || [ ! -d "$sdk/ndk" ] && continue
                    _ndk=$(find "$sdk/ndk" -maxdepth 1 -type d -name "[0-9]*" 2>/dev/null | sort -V | tail -1)
                    if [ -n "$_ndk" ] && [ -f "$_ndk/ndk-build" ] || [ -f "$_ndk/source.properties" ]; then
                        export ANDROID_NDK_HOME="$_ndk"
                        print_info "Using NDK: $ANDROID_NDK_HOME"
                        break
                    fi
                done
            fi
        fi
        if [ -z "${ANDROID_NDK_HOME:-}" ]; then
            print_error "Android NDK not found. Set ANDROID_NDK_HOME to your NDK root, or install NDK via Android Studio (SDK Manager → SDK Tools → NDK)."
            exit 1
        fi
        print_info "Building Rust for Android (cargo-ndk)..."
        mkdir -p "$jni_libs_dir"
        (cd "$crate_dir" && cargo ndk -o "$jni_libs_dir" build 2>&1) || {
            print_error "cargo ndk build failed."
            echo "  ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-<not set>}"
            echo "  Check: the path must exist and be the NDK root (contains source.properties, toolchains/, etc.)."
            echo "  List installed NDKs: ls \$HOME/Android/Sdk/ndk"
            echo "  If empty, install NDK: Android Studio → Settings → Android SDK → SDK Tools → NDK (Side by side) → Apply."
            exit 1
        }
        # Verify at least one ABI has the .so (cargo-ndk puts them in arm64-v8a, armeabi-v7a, etc.)
        local so_count
        so_count=$(find "$jni_libs_dir" -name "libdebitum_client_core.so" 2>/dev/null | wc -l)
        if [ "${so_count:-0}" -eq 0 ]; then
            print_error "No libdebitum_client_core.so found under $jni_libs_dir. cargo ndk may have written to a different path."
            exit 1
        fi
        print_success "Rust Android libs ready in jniLibs/ ($so_count ABI(s))"
    elif [ "$platform" = "linux" ]; then
        print_info "Building Rust for Linux..."
        if (cd "$crate_dir" && cargo build --release 2>&1); then
            :
        else
            (cd "$crate_dir" && cargo build 2>&1) || exit 1
            if [ -f "$crate_dir/target/debug/libdebitum_client_core.so" ]; then
                mkdir -p "$crate_dir/target/release"
                cp -f "$crate_dir/target/debug/libdebitum_client_core.so" "$crate_dir/target/release/" 2>/dev/null || true
            fi
        fi
        print_success "Rust Linux lib ready"
    fi
    # web: no native lib, codegen already done
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
    
    # Resolve Flutter binary (script may run in env where flutter is not in PATH)
    local flutter_bin
    flutter_bin=$(resolve_flutter_cmd) || {
        print_error "Flutter not found. Install Flutter SDK or set FLUTTER_CMD or FLUTTER_SDK_ROOT."
        exit 1
    }
    
    # Build and prepare Rust bridge so Dart hash and native lib match (all-in-one)
    if [ "$platform" = "android" ] || [ "$platform" = "linux" ]; then
        prepare_rust_bridge_for_flutter "$platform"
    fi
    
    # Build flutter run command with mode flag
    local flutter_cmd="$flutter_bin run"
    if [ -n "$mode_flag" ]; then
        flutter_cmd="$flutter_cmd $mode_flag"
    fi
    
    if [ "$platform" = "android" ]; then
        if [ "$SEPARATE_INSTANCE" = true ]; then
            print_warning "--separate-instance is only supported for Linux; ignored for Android"
        fi
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
        if [ "$SEPARATE_INSTANCE" = true ]; then
            print_warning "--separate-instance is only supported for Linux; ignored for web"
        fi
        if [ -n "$device_id" ]; then
            (cd "$ROOT_DIR/mobile" && $flutter_cmd -d "$device_id")
        else
            (cd "$ROOT_DIR/mobile" && $flutter_cmd -d chrome)
        fi
    elif [ "$platform" = "linux" ]; then
        if [ -n "$INSTANCES" ] && [ "$INSTANCES" -ge 2 ] && [ "$SEPARATE_INSTANCE" != true ]; then
            print_error "--instances N (N>=2) requires --separate-instance on Linux."
            exit 1
        fi
        # Rust FFI: loader looks for libdebitum_client_core.so in target/release
        local rust_lib_dir="$ROOT_DIR/crates/debitum_client_core/target/release"
        if [ -f "$rust_lib_dir/libdebitum_client_core.so" ]; then
            export LD_LIBRARY_PATH="$rust_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        else
            echo -e "${YELLOW}⚠ Rust lib not found at $rust_lib_dir - run: cd crates/debitum_client_core && cargo build --release (or: cp target/debug/libdebitum_client_core.so target/release/)${NC}" >&2
        fi
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
        
        # Multi-instance: spawn N separate instances, unified log viewer, instance window titles
        if [ "$SEPARATE_INSTANCE" = true ] && [ -n "$INSTANCES" ] && [ "$INSTANCES" -ge 2 ] && [ -z "$device_id" ]; then
            local real_home="$HOME"
            [ -z "$real_home" ] && real_home="$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f6)"
            local log_dir="${TMPDIR:-/tmp}/debitum-multi-logs-$$"
            local pids_file="${TMPDIR:-/tmp}/debitum-multi-pids-$$"
            mkdir -p "$log_dir"
            : > "$pids_file"
            print_step "Spawning $INSTANCES instances (logs in $log_dir); press 1-$INSTANCES to switch, q to quit viewer"
            local i=1
            while [ $i -le "$INSTANCES" ]; do
                local instance_base="${TMPDIR:-/tmp}/debitum-instance-$$-$i"
                mkdir -p "$instance_base/Documents" "$instance_base/.local/share" "$instance_base/.config"
                (
                    export PUB_CACHE="${real_home}/.pub-cache"
                    export HOME="$instance_base"
                    export XDG_DATA_HOME="$instance_base/.local/share"
                    export XDG_CONFIG_HOME="$instance_base/.config"
                    export DEBITUM_INSTANCE_ID="$i"
                    cd "$ROOT_DIR/mobile" && LD_LIBRARY_PATH="$rust_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
                        $flutter_cmd -d linux \
                        > "$log_dir/instance_$i.log" 2>&1
                ) &
                echo $! >> "$pids_file"
                i=$((i + 1))
                [ $i -le "$INSTANCES" ] && sleep 4
            done
            sleep 2
            python3 "$SCRIPT_DIR/multi_instance_log_viewer.py" --log-dir "$log_dir" --count "$INSTANCES" --pids-file "$pids_file" || true
            print_info "Log viewer exited. App windows keep running; close them to stop instances."
            return 0
        fi
        
        # Separate instance: use isolated HOME so Documents + XDG paths do not share data with other instances
        if [ "$SEPARATE_INSTANCE" = true ]; then
            local real_home="$HOME"
            [ -z "$real_home" ] && real_home="$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f6)"
            local instance_base="${TMPDIR:-/tmp}/debitum-instance-$$"
            mkdir -p "$instance_base/Documents" "$instance_base/.local/share" "$instance_base/.config"
            export PUB_CACHE="${real_home}/.pub-cache"
            export HOME="$instance_base"
            export XDG_DATA_HOME="$instance_base/.local/share"
            export XDG_CONFIG_HOME="$instance_base/.config"
            export DEBITUM_INSTANCE_ID="1"
            print_info "Using separate instance data: $instance_base (no shared data with other runs)"
        fi
        
        # Launch Flutter app and configure window for Hyprland
        local linux_extra=""
        if [ -n "$device_id" ]; then
            (cd "$ROOT_DIR/mobile" && LD_LIBRARY_PATH="$rust_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" $flutter_cmd $linux_extra -d "$device_id")
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
                
                # Launch Flutter (foreground)
                (cd "$ROOT_DIR/mobile" && LD_LIBRARY_PATH="$rust_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" $flutter_cmd $linux_extra -d linux)
                
                # Clean up background process if still running
                kill $config_pid 2>/dev/null || true
            else
                # Not on Hyprland, just run normally
                (cd "$ROOT_DIR/mobile" && LD_LIBRARY_PATH="$rust_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" $flutter_cmd $linux_extra -d linux)
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

cmd_test_integration() {
    validate_flags "test-integration"
    
    print_step "Running client-core integration tests (Rust)..."
    
    (cd "$ROOT_DIR/crates/debitum_client_core" && cargo test --test integration -- --ignored)
    
    print_success "Integration tests complete"
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

cmd_test_flutter_integration_multi_app() {
    validate_flags "test-flutter-integration-multi-app"
    
    # Parse test selection arguments (e.g., "2" for file 2, "2.2" for test 2 in file 2, "4.1 4.2" for multiple tests)
    # Store selections as associative arrays: file_num -> array of test numbers (empty array means all tests in file)
    declare -A SELECTED_FILES
    declare -A SELECTED_TESTS  # file_num -> space-separated list of test numbers
    
    # Get arguments after the command name (skip the first argument which is the command)
    local TEST_ARGS=("${ARGS[@]:1}")
    
    if [ ${#TEST_ARGS[@]} -gt 0 ]; then
        for selection in "${TEST_ARGS[@]}"; do
            if [[ "$selection" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
                # Format: X.Y (file X, test Y)
                local file_num="${BASH_REMATCH[1]}"
                local test_num="${BASH_REMATCH[2]}"
                SELECTED_FILES["$file_num"]=1
                # Add test number to the list for this file
                if [ -z "${SELECTED_TESTS[$file_num]}" ]; then
                    SELECTED_TESTS["$file_num"]="$test_num"
                else
                    SELECTED_TESTS["$file_num"]="${SELECTED_TESTS[$file_num]} $test_num"
                fi
            elif [[ "$selection" =~ ^[0-9]+$ ]]; then
                # Format: X (file X only - all tests)
                SELECTED_FILES["$selection"]=1
                # Empty test list means all tests in this file
                if [ -z "${SELECTED_TESTS[$selection]}" ]; then
                    SELECTED_TESTS["$selection"]=""
                fi
            else
                print_error "Invalid test selection: $selection"
                print_info "Usage: $0 test-flutter-integration-multi-app [SELECTIONS...]"
                print_info "Examples:"
                print_info "  $0 test-flutter-integration-multi-app 2           # Run file 2 (all tests)"
                print_info "  $0 test-flutter-integration-multi-app 2.2        # Run test 2 in file 2"
                print_info "  $0 test-flutter-integration-multi-app 4.1 4.2    # Run tests 1 and 2 in file 4"
                print_info "  $0 test-flutter-integration-multi-app 2 4.1      # Run all tests in file 2, and test 1 in file 4"
                exit 1
            fi
        done
    fi
    
    # Temporarily disable exit on error so we can continue even if tests fail
    set +e
    
    print_step "Running multi-app integration test suites..."
    
    # Check if server is running
    print_info "Checking if server is running..."
    if ! curl -s http://localhost:8000/health > /dev/null 2>&1; then
        print_error "Server is not running at http://localhost:8000"
        print_warning "Please start the server first:"
        echo "  $0 start-server-direct"
        exit 1
    fi
    print_success "Server is running"
    echo ""
    
    # Flutter path
    local FLUTTER_CMD
    if command -v flutter &> /dev/null; then
        FLUTTER_CMD="flutter"
    elif [ -f "/home/max/flutter/bin/flutter" ]; then
        FLUTTER_CMD="/home/max/flutter/bin/flutter"
    else
        print_error "Flutter not found. Please install Flutter SDK."
        exit 1
    fi
    
    local TEST_DIR="integration_test/multi_app/scenarios"
    local DEVICE="linux"
    
    # Change to mobile directory first to discover tests
    cd "$ROOT_DIR/mobile" || exit 1
    
    # Dynamically discover all test files in the scenarios directory
    if [ ! -d "$TEST_DIR" ]; then
        print_error "Test directory not found: $TEST_DIR"
        exit 1
    fi
    
    # Find all .dart files and sort them alphabetically
    declare -a TEST_SUITES
    # Use a more portable approach
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            # Get just the filename without path
            local filename=$(basename "$file")
            TEST_SUITES+=("$filename")
        fi
    done < <(find "$TEST_DIR" -maxdepth 1 -name "*.dart" -type f | sort)
    
    if [ ${#TEST_SUITES[@]} -eq 0 ]; then
        print_error "No test files found in $TEST_DIR"
        exit 1
    fi
    
    # Generate display names from filenames
    # Convert snake_case to Title Case (e.g., "basic_sync_scenarios" -> "Basic Sync Scenarios")
    declare -a TEST_NAMES
    for test_file in "${TEST_SUITES[@]}"; do
        # Remove .dart extension
        local name="${test_file%.dart}"
        # Replace underscores with spaces
        name="${name//_/ }"
        # Convert to title case (capitalize first letter of each word)
        local title_case=""
        for word in $name; do
            # Capitalize first letter, lowercase the rest
            local first_char=$(echo "${word:0:1}" | tr '[:lower:]' '[:upper:]')
            local rest_chars=$(echo "${word:1}" | tr '[:upper:]' '[:lower:]')
            if [ -z "$title_case" ]; then
                title_case="${first_char}${rest_chars}"
            else
                title_case="${title_case} ${first_char}${rest_chars}"
            fi
        done
        TEST_NAMES+=("$title_case")
    done
    
    # Results tracking
    declare -a TEST_RESULTS
    declare -a FILE_TEST_COUNTS      # Number of tests that actually ran per file
    declare -a FILE_TEST_PASSED      # Number of passed tests per file
    declare -a FILE_TEST_FAILED      # Number of failed tests per file
    declare -a FILE_RAN_TESTS        # Track which files actually ran tests (1 = ran, 0 = skipped)
    declare -A FILE_FAILED_TEST_NAMES  # Track failed test numbers per file (e.g., "3.5 7.1")
    local TOTAL_TESTS=${#TEST_SUITES[@]}
    local TOTAL_INDIVIDUAL_TESTS=0
    local TOTAL_PASSED=0
    local TOTAL_FAILED=0
    
    print_info "════════════════════════════════════════════════════════════════"
    print_info "Discovered $TOTAL_TESTS Integration Test Suites"
    print_info "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Run each test suite
    for i in "${!TEST_SUITES[@]}"; do
        local TEST_FILE="${TEST_SUITES[$i]}"
        local TEST_NAME="${TEST_NAMES[$i]}"
        local TEST_NUM=$((i + 1))
        
        # Skip this file if specific files were selected and this isn't one of them
        if [ ${#SELECTED_FILES[@]} -gt 0 ] && [ -z "${SELECTED_FILES[$TEST_NUM]}" ]; then
            continue
        fi
        
        # Show file-level progress
        if [ ${#SELECTED_FILES[@]} -gt 0 ] && [ -n "${SELECTED_FILES[$TEST_NUM]}" ]; then
            local test_selection="${SELECTED_TESTS[$TEST_NUM]}"
            if [ -n "$test_selection" ]; then
                echo -e "${BLUE}[File $TEST_NUM]${NC} ${YELLOW}$TEST_NAME${NC} ${BLUE}→ Tests: $test_selection${NC}"
            else
                echo -e "${BLUE}[File $TEST_NUM]${NC} ${YELLOW}$TEST_NAME${NC} ${BLUE}→ All tests${NC}"
            fi
        else
            echo -e "${BLUE}[File $TEST_NUM]${NC} ${YELLOW}$TEST_NAME${NC}"
        fi
        
        # Parse test names directly from source file FIRST (needed for test selection)
        # CRITICAL: Declare as local array to avoid contamination between iterations
        local -a INDIVIDUAL_TESTS=()
        local TEST_COUNT=0
        
        # Use awk to extract test names - more reliable than bash regex
        # Look for: ^    test('Test Name', () async {
        # CRITICAL: Only match lines that are actual test declarations, not test names in strings
        local test_names=$(awk '
            /^[[:space:]]+test\(['\''"]/ && !/^[[:space:]]*['\''"]/ {
                # Extract test name from test('Name', or test("Name",
                match($0, /test\(['\''"]([^'\''"]+)['\''"]/, arr)
                if (arr[1] != "" && length(arr[1]) > 0 && length(arr[1]) < 200) {
                    print arr[1]
                }
            }
        ' "$TEST_DIR/$TEST_FILE" 2>/dev/null)
        
        # Clear the array first to avoid contamination
        INDIVIDUAL_TESTS=()
        TEST_COUNT=0
        
        if [ -n "$test_names" ]; then
            while IFS= read -r test_name || [ -n "$test_name" ]; do
                # Trim whitespace
                test_name=$(echo "$test_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Skip empty lines
                if [ -z "$test_name" ]; then
                    continue
                fi
                
                if [ ${#test_name} -gt 0 ] && [ ${#test_name} -lt 200 ]; then
                    # Check for duplicates
                    local is_duplicate=false
                    for existing in "${INDIVIDUAL_TESTS[@]}"; do
                        if [ "$existing" = "$test_name" ]; then
                            is_duplicate=true
                            break
                        fi
                    done
                    if [ "$is_duplicate" = "false" ]; then
                        INDIVIDUAL_TESTS+=("$test_name")
                        ((TEST_COUNT++))
                    fi
                fi
            done <<< "$test_names"
        fi
        
        # CRITICAL: Only use tests from source file, ignore any that might have been added elsewhere
        # The array should now only contain tests from THIS file
        
        # Run test and capture output
        local TEMP_OUTPUT=$(mktemp)
        local TEST_EXIT_CODE=0
        
        # Build Flutter test command with JSON reporter for reliable parsing
        local FLUTTER_TEST_CMD="$FLUTTER_CMD test \"$TEST_DIR/$TEST_FILE\" -d \"$DEVICE\" --reporter json"
        
        # If specific tests were selected for this file, use --name to run only those tests
        local selected_tests_for_file="${SELECTED_TESTS[$TEST_NUM]}"
        if [ -n "$selected_tests_for_file" ] && [ ${#INDIVIDUAL_TESTS[@]} -gt 0 ]; then
            # Build regex pattern for test names to run
            local test_patterns=()
            for test_num_str in $selected_tests_for_file; do
                local test_idx=$((test_num_str - 1))
                if [ $test_idx -ge 0 ] && [ $test_idx -lt ${#INDIVIDUAL_TESTS[@]} ]; then
                    local test_name="${INDIVIDUAL_TESTS[$test_idx]}"
                    # Escape special regex characters but keep the test name
                    local escaped_test_name=$(echo "$test_name" | sed 's/[[\.*^$()+?{|]/\\&/g')
                    test_patterns+=("$escaped_test_name")
                else
                    print_warning "Test number $test_num_str not found in file $TEST_NUM (only ${#INDIVIDUAL_TESTS[@]} tests available)"
                fi
            done
            
            if [ ${#test_patterns[@]} -gt 0 ]; then
                # Combine patterns with | (OR) for regex matching
                local combined_pattern=$(IFS='|'; echo "${test_patterns[*]}")
                FLUTTER_TEST_CMD="$FLUTTER_CMD test \"$TEST_DIR/$TEST_FILE\" -d \"$DEVICE\" --reporter json --name \"$combined_pattern\""
            else
                print_error "No valid tests selected for file $TEST_NUM"
                continue
            fi
        fi
        
        # Run the test and capture output (JSON to one file, stderr to another for verbose mode)
        local TEMP_JSON_OUTPUT=$(mktemp)
        if [ "$VERBOSE" = "true" ]; then
            # In verbose mode, show all output in real-time AND capture JSON
            # Use tee to both display and capture output
            eval "$FLUTTER_TEST_CMD" 2>&1 | tee "$TEMP_JSON_OUTPUT" || TEST_EXIT_CODE=${PIPESTATUS[0]}
            cp "$TEMP_JSON_OUTPUT" "$TEMP_OUTPUT"
        else
            # In non-verbose mode, suppress warnings but capture JSON
            eval "$FLUTTER_TEST_CMD" > "$TEMP_JSON_OUTPUT" 2>&1 || TEST_EXIT_CODE=$?
            # Filter out warnings but keep JSON lines
            grep -v "warning:" "$TEMP_JSON_OUTPUT" | grep -v "json.hpp" > "$TEMP_OUTPUT" 2>&1 || true
        fi
        
        # Track individual test results for this file
        local FILE_PASSED_COUNT=0
        local FILE_FAILED_COUNT=0
        
        # Parse and show results after test completes
        # CRITICAL: Only show tests that were found in THIS file's source code
        # Do NOT parse test names from output - only show what we found in source
        # Use the actual array size as the authoritative count
        local actual_test_count=${#INDIVIDUAL_TESTS[@]}
        
        # If array size doesn't match TEST_COUNT, something went wrong - use array size
        if [ "$actual_test_count" -ne "$TEST_COUNT" ] 2>/dev/null; then
            TEST_COUNT=$actual_test_count
        fi
        
        # Track how many tests actually ran (for counting purposes)
        local TESTS_RAN_COUNT=0
        
        if [ "$TEST_COUNT" -gt 0 ] 2>/dev/null && [ ${#INDIVIDUAL_TESTS[@]} -gt 0 ]; then
            local test_idx=0
            # Only iterate over tests we actually found in the source file
            for test_name in "${INDIVIDUAL_TESTS[@]}"; do
                ((test_idx++))
                local test_num=$test_idx
                local test_total=$TEST_COUNT
                
                # Skip this test if specific tests were selected and this isn't one of them
                local selected_tests_for_file="${SELECTED_TESTS[$TEST_NUM]}"
                local should_run_test=true
                if [ -n "$selected_tests_for_file" ]; then
                    # Check if this test number is in the selected list
                    local is_selected=false
                    for selected_test_num in $selected_tests_for_file; do
                        if [ "$test_num" -eq "$selected_test_num" ]; then
                            is_selected=true
                            break
                        fi
                    done
                    if [ "$is_selected" = "false" ]; then
                        should_run_test=false
                    fi
                fi
                
                # Skip if this test shouldn't run
                if [ "$should_run_test" = "false" ]; then
                    continue
                fi
                
                # This test will run - increment counter
                ((TESTS_RAN_COUNT++))
                
                # Parse test result from JSON output (much more reliable than text parsing)
                local test_result="UNKNOWN"
                
                # Escape test name for JSON matching (escape special regex chars but keep it searchable)
                # The test name in JSON appears as "Group Name Test Name", so we need to match just the test name part
                local escaped_test_name=$(echo "$test_name" | sed 's/\[/\\[/g; s/\]/\\]/g; s/\./\\./g; s/\*/\\*/g; s/\^/\\^/g; s/\$/\\$/g; s/(/\\(/g; s/)/\\)/g; s/+/\\+/g; s/?/\\?/g; s/{/\\{/g; s/}/\\}/g; s/|/\\|/g')
                
                # JSON format: {"test":{"id":5,"name":"Group Name Test Name",...},"type":"testStart",...}
                # Then: {"testID":5,"result":"success","skipped":false,"type":"testDone",...}
                # We need to find testStart with the test name, get the ID, then find testDone with that ID
                
                # Find testStart event - test name in JSON includes group name, so match the test name anywhere in the name field
                local test_id=""
                
                # Try to find testStart line with this test name (case-insensitive, match anywhere in name)
                local test_start_line=$(grep -i "\"type\":\"testStart\"" "$TEMP_JSON_OUTPUT" 2>/dev/null | \
                    grep -i "$escaped_test_name" | head -1)
                
                if [ -n "$test_start_line" ]; then
                    # Extract test ID from the testStart event
                    # Format: {"test":{"id":5,"name":"...",...},...}
                    test_id=$(echo "$test_start_line" | grep -oE "\"test\":\{[^}]*\"id\":([0-9]+)" | \
                        grep -oE "\"id\":([0-9]+)" | \
                        grep -oE "[0-9]+" | head -1)
                fi
                
                if [ -n "$test_id" ]; then
                    # Found test ID, now look for testDone event with this ID
                    local test_done_line=$(grep "\"testID\":$test_id," "$TEMP_JSON_OUTPUT" 2>/dev/null | \
                        grep "\"type\":\"testDone\"" | head -1)
                    
                    if [ -n "$test_done_line" ]; then
                        # Check the result field and skip hidden tests (setUp/tearDown)
                        if echo "$test_done_line" | grep -qE "\"hidden\":true"; then
                            # Hidden test (setUp/tearDown) - skip it
                            continue
                        elif echo "$test_done_line" | grep -qE "\"result\":\"success\""; then
                            test_result="PASSED"
                        elif echo "$test_done_line" | grep -qE "\"result\":\"error\"|\"result\":\"failure\""; then
                            test_result="FAILED"
                        elif echo "$test_done_line" | grep -qE "\"skipped\":true"; then
                            test_result="SKIPPED"
                        else
                            # Unknown result type
                            test_result="UNKNOWN"
                        fi
                    fi
                fi
                
                # Fallback: if we couldn't find the test in JSON, use exit code
                if [ "$test_result" = "UNKNOWN" ]; then
                    if [ $TEST_EXIT_CODE -eq 0 ]; then
                        # File passed - assume test passed if we can't determine
                        test_result="PASSED"
                    else
                        # File failed - assume test failed if we can't determine
                        test_result="FAILED"
                    fi
                fi
                
                # Truncate long test names
                local display_name="$test_name"
                if [ ${#display_name} -gt 60 ]; then
                    display_name="${display_name:0:57}..."
                fi
                
                # Show test with result - format: [FILE_NUM.TEST_NUM] Test Name
                printf "  [%d.%d] %-60s" "$TEST_NUM" "$test_num" "$display_name"
                
                # Show result and count
                if [ "$test_result" = "PASSED" ]; then
                    echo -e " ${GREEN}✓ PASSED${NC}"
                    ((FILE_PASSED_COUNT++))
                    ((TOTAL_PASSED++))
                else
                    echo -e " ${RED}✗ FAILED${NC}"
                    ((FILE_FAILED_COUNT++))
                    ((TOTAL_FAILED++))
                    # Track failed test for verbose message
                    if [ ${#FAILED_TEST_NAMES[@]} -eq 0 ]; then
                        FAILED_TEST_NAMES=("$TEST_NUM.$test_num")
                    else
                        FAILED_TEST_NAMES+=("$TEST_NUM.$test_num")
                    fi
                fi
            done
            
            # Store counts for this file - use actual number of tests that ran, not total in file
            FILE_TEST_COUNTS[$i]=$TESTS_RAN_COUNT
            FILE_TEST_PASSED[$i]=$FILE_PASSED_COUNT
            FILE_TEST_FAILED[$i]=$FILE_FAILED_COUNT
            if [ $TESTS_RAN_COUNT -gt 0 ]; then
                FILE_RAN_TESTS[$i]=1
                ((TOTAL_INDIVIDUAL_TESTS += TESTS_RAN_COUNT))
                # Store failed test names for this file
                if [ ${#FAILED_TEST_NAMES[@]} -gt 0 ]; then
                    local failed_tests_str=$(IFS=' '; echo "${FAILED_TEST_NAMES[*]}")
                    FILE_FAILED_TEST_NAMES[$i]="$failed_tests_str"
                fi
            else
                FILE_RAN_TESTS[$i]=0
            fi
        else
            echo "  Running tests..."
            FILE_TEST_COUNTS[$i]=0
            FILE_TEST_PASSED[$i]=0
            FILE_TEST_FAILED[$i]=0
            FILE_RAN_TESTS[$i]=0
        fi
        
        # Clean up
        rm -f "$TEMP_OUTPUT" "$TEMP_JSON_OUTPUT"
        
        # Set file result (no message printed - info is in summary table)
        if [ $TEST_EXIT_CODE -eq 0 ]; then
            TEST_RESULTS[$i]="PASSED"
        else
            TEST_RESULTS[$i]="FAILED"
        fi
        echo ""
    done
    
    # Print summary table
    echo ""
    
    # Prepare data for Python table formatter
    local TEMP_TABLE_DATA=$(mktemp)
    {
        echo "Test Suite|Result|Passed / Failed / Total"
        for i in "${!TEST_SUITES[@]}"; do
            # Skip files that didn't run any tests
            if [ "${FILE_RAN_TESTS[$i]:-0}" -eq 0 ]; then
                continue
            fi
            
            local TEST_NAME="${TEST_NAMES[$i]}"
            local RESULT="${TEST_RESULTS[$i]}"
            local TEST_COUNT="${FILE_TEST_COUNTS[$i]:-0}"
            local PASSED_COUNT="${FILE_TEST_PASSED[$i]:-0}"
            local FAILED_COUNT="${FILE_TEST_FAILED[$i]:-0}"
            
            # Truncate long names if needed
            local display_name="$TEST_NAME"
            if [ ${#display_name} -gt 50 ]; then
                display_name="${display_name:0:47}..."
            fi
            
            # Format result
            local result_str=""
            if [ "$RESULT" = "PASSED" ]; then
                result_str="✓ PASSED"
            else
                result_str="✗ FAILED"
            fi
            
            # Format counts
            local counts_str=""
            if [ "$TEST_COUNT" -gt 0 ] 2>/dev/null; then
                counts_str="${PASSED_COUNT} / ${FAILED_COUNT} / ${TEST_COUNT}"
            else
                counts_str="N/A"
            fi
            
            echo "${display_name}|${result_str}|${counts_str}"
        done
    } > "$TEMP_TABLE_DATA"
    
    # Use Python rich library for beautiful colored tables (if available), otherwise use simple printf
    GREEN="$GREEN" RED="$RED" YELLOW="$YELLOW" NC="$NC" python3 - "$TEMP_TABLE_DATA" << 'PYTHON_EOF'
import sys
import os

# Get color codes from environment
GREEN = os.environ.get('GREEN', '\033[0;32m')
RED = os.environ.get('RED', '\033[0;31m')
YELLOW = os.environ.get('YELLOW', '\033[1;33m')
NC = os.environ.get('NC', '\033[0m')

try:
    from rich.console import Console
    from rich.table import Table
    from rich import box
    
    # Force terminal rendering so colors show even if stdout isn't detected as a TTY
    console = Console(force_terminal=True, color_system="standard")
    table = Table(show_header=True, header_style="bold", box=box.SQUARE, pad_edge=True)
    table.add_column("Test Suite", style="", no_wrap=False)
    table.add_column("Result", style="", justify="left")
    table.add_column("Passed / Failed / Total", style="", justify="left")
    
    # Read data from file
    if len(sys.argv) < 2:
        sys.exit(0)
    
    table_file = sys.argv[1]
    if not os.path.exists(table_file):
        sys.exit(0)
    
    with open(table_file, 'r') as f:
        lines = f.readlines()
    
    if len(lines) < 2:
        sys.exit(0)
    
    # Skip header line, process data rows
    for line in lines[1:]:
        parts = line.strip().split('|')
        if len(parts) != 3:
            continue
        
        test_suite, result, counts = parts
        
        # Colorize result
        if result == "✓ PASSED":
            result_colored = f"[green]✓ PASSED[/green]"
        elif result == "✗ FAILED":
            result_colored = f"[red]✗ FAILED[/red]"
        else:
            result_colored = result
        
        # Colorize counts
        if counts != "N/A":
            count_parts = counts.split(" / ")
            if len(count_parts) == 3:
                passed, failed, total = count_parts
                counts_colored = f"[green]{passed}[/green] / [red]{failed}[/red] / {total}"
            else:
                counts_colored = f"[yellow]{counts}[/yellow]"
        else:
            counts_colored = f"[yellow]N/A[/yellow]"
        
        table.add_row(test_suite, result_colored, counts_colored)
    
    console.print(table)
    
except ImportError:
    # Fallback: Use simple printf-based table with colors
    if len(sys.argv) < 2:
        sys.exit(0)
    
    table_file = sys.argv[1]
    if not os.path.exists(table_file):
        sys.exit(0)
    
    with open(table_file, 'r') as f:
        lines = f.readlines()
    
    if len(lines) < 2:
        sys.exit(0)
    
    # Calculate max width for first column
    max_width = 0
    data_rows = []
    for line in lines[1:]:
        parts = line.strip().split('|')
        if len(parts) == 3:
            if len(parts[0]) > max_width:
                max_width = len(parts[0])
            data_rows.append(parts)
    
    max_width = max(max_width, 30)
    
    # Print table with colors using printf
    print(f"┌{'─' * (max_width + 2)}┬{'─' * 18}┬{'─' * 40}┐")
    print(f"│ {'Test Suite':<{max_width}} │ {'Result':<16} │ {'Passed / Failed / Total':<38} │")
    print(f"├{'─' * (max_width + 2)}┼{'─' * 18}┼{'─' * 40}┤")
    
    for test_suite, result, counts in data_rows:
        # Colorize result
        if result == "✓ PASSED":
            result_str = f"{GREEN}✓ PASSED{NC}"
        elif result == "✗ FAILED":
            result_str = f"{RED}✗ FAILED{NC}"
        else:
            result_str = result
        
        # Colorize counts
        if counts != "N/A":
            count_parts = counts.split(" / ")
            if len(count_parts) == 3:
                passed, failed, total = count_parts
                counts_str = f"{GREEN}{passed}{NC} / {RED}{failed}{NC} / {total}"
            else:
                counts_str = f"{YELLOW}{counts}{NC}"
        else:
            counts_str = f"{YELLOW}N/A{NC}"
        
        # Calculate visible lengths for padding (without color codes)
        # Use the original plain text values
        result_plain_len = len(result)
        counts_plain_len = len(counts)
        
        result_padding = max(0, 16 - result_plain_len)
        counts_padding = max(0, 38 - counts_plain_len)
        
        # Print row with proper padding (color codes don't count toward width)
        print(f"│ {test_suite:<{max_width}} │ {result_str}{' ' * result_padding} │ {counts_str}{' ' * counts_padding} │")
    
    print(f"└{'─' * (max_width + 2)}┴{'─' * 18}┴{'─' * 40}┘")
    
except Exception:
    pass
PYTHON_EOF
    
    # Clean up
    rm -f "$TEMP_TABLE_DATA"
    echo ""
    # Count files that actually ran tests
    local FILES_RAN_COUNT=0
    for ran in "${FILE_RAN_TESTS[@]}"; do
        if [ "${ran:-0}" -eq 1 ]; then
            ((FILES_RAN_COUNT++))
        fi
    done
    
    # Calculate pass rate
    local pass_rate="N/A"
    if [ -n "$TOTAL_INDIVIDUAL_TESTS" ] && [ "$TOTAL_INDIVIDUAL_TESTS" -gt 0 ] 2>/dev/null; then
        pass_rate=$((TOTAL_PASSED * 100 / TOTAL_INDIVIDUAL_TESTS))
    fi
    
    # Print summary as a table
    printf "┌─%-30s─┬─%s─┐\n" "$(printf '─%.0s' $(seq 1 30))" "$(printf '─%.0s' $(seq 1 20))"
    printf "│ %-30s │ %-20s │\n" "Metric" "Value"
    printf "├─%-30s─┼─%s─┤\n" "$(printf '─%.0s' $(seq 1 30))" "$(printf '─%.0s' $(seq 1 20))"
    printf "│ %-30s │ %-20d │\n" "Total Test Files" "$FILES_RAN_COUNT"
    printf "│ %-30s │ %-20d │\n" "Total Individual Tests" "$TOTAL_INDIVIDUAL_TESTS"
    printf "│ %-30s │ %b%-20d%b │\n" "Passed" "$GREEN" "$TOTAL_PASSED" "$NC"
    printf "│ %-30s │ %b%-20d%b │\n" "Failed" "$RED" "$TOTAL_FAILED" "$NC"
    printf "│ %-30s │ %-20s │\n" "Pass Rate" "${pass_rate}%"
    printf "└─%-30s─┴─%s─┘\n" "$(printf '─%.0s' $(seq 1 30))" "$(printf '─%.0s' $(seq 1 20))"
    echo ""
    
    # Re-enable exit on error
    set -e
    
    # Exit with appropriate code
    if [ -n "$TOTAL_FAILED" ] && [ "$TOTAL_FAILED" -gt 0 ] 2>/dev/null; then
        echo ""
        print_error "⚠️  Some tests failed."
        echo ""
        echo -e "${YELLOW}To see detailed error output for failed tests, run:${NC}"
        echo ""
        
        # Collect all failed test numbers
        local all_failed_tests=()
        for i in "${!FILE_FAILED_TEST_NAMES[@]}"; do
            local failed_tests="${FILE_FAILED_TEST_NAMES[$i]}"
            if [ -n "$failed_tests" ]; then
                # Split space-separated test numbers and add to array
                for test_num in $failed_tests; do
                    all_failed_tests+=("$test_num")
                done
            fi
        done
        
        if [ ${#all_failed_tests[@]} -gt 0 ]; then
            local failed_tests_str=$(IFS=' '; echo "${all_failed_tests[*]}")
            echo -e "  ${CYAN}$0 test-flutter-integration-multi-app --verbose $failed_tests_str${NC}"
        else
            echo -e "  ${CYAN}$0 test-flutter-integration-multi-app --verbose${NC}"
        fi
        echo ""
        return 1
    else
        print_success "🎉 All tests passed!"
        return 0
    fi
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
  --separate-instance, --sandbox   Run Linux app with isolated data (no shared data with other instances)
  --instances N (1-9)              Spawn N instances at once (Linux + --separate-instance only).
                                  Single terminal shows one instance's logs; press 1-9 to switch, q to quit.
                                  Window titles become "Instance 1", "Instance 2", etc.

Database Commands:
  reset-database-complete [backup.zip [username] [wallet]]
                                  Complete reset + rebuild + optional import (recommended)
                                  If backup.zip is given, username and wallet are required.
                                  Wallet is created if it does not exist.
                                  Use --skip-server-build to skip server build (faster if binary exists)
  reset-database-only [backup.zip [username] [wallet]]
                                  Reset PostgreSQL database only, optionally import data
                                  If backup.zip is given, username and wallet are required.
  import-backup <backup.zip> <username> <wallet>
                                  Import data from Debitum backup (creates events).
                                  Username must exist; wallet is created if it does not exist.
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
                                  Use --separate-instance to run Linux app with isolated data (no shared state)
                                  Use --instances N to spawn N instances with unified log viewer (1-9 switch, q quit)
                                  On Hyprland: automatically floats window with fixed size
  show-android-logs                Show filtered Android logs (Flutter/Dart only)
                                  Use this in a separate terminal while Flutter app is running
  run-flutter-web [mode]           Run Flutter web app (dev/prod)
  test-integration                 Run client-core integration tests (Rust, requires server)
  test-flutter-integration [test]   Run Flutter integration tests (with database reset)
                                  Use --skip-server-build to skip server build during reset
  test-flutter-integration-multi-app [SELECTIONS...]
                                  Run all multi-app sync integration test suites
                                  Dynamically discovers all test files in integration_test/multi_app/scenarios/
                                  Requires server to be running (use start-server-direct)
                                  
                                  Optional arguments (can specify multiple):
                                    FILE_NUM              Run all tests in the specified file (e.g., 2)
                                    FILE_NUM.TEST_NUM     Run only the specified test in the file (e.g., 2.2)
                                    
                                  Examples:
                                    $0 test-flutter-integration-multi-app                    # Run all tests
                                    $0 test-flutter-integration-multi-app 2                 # Run file 2 only
                                    $0 test-flutter-integration-multi-app 2.2               # Run test 2 in file 2
                                    $0 test-flutter-integration-multi-app 4.1 4.2           # Run tests 1 and 2 in file 4
                                    $0 test-flutter-integration-multi-app 2 4.1             # Run all tests in file 2, and test 1 in file 4

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
  $0 reset-database-complete backup.zip max MyWallet   # Complete reset + import + rebuild (recommended)
  $0 --skip-server-build reset-database-complete  # Fast reset (skip server build)
  $0 reset-database-only                          # Clean reset (no data)
  $0 reset-database-only backup.zip max MyWallet # Reset and import into user max, wallet MyWallet
  $0 import-backup backup.zip max MyWallet       # Import data (wallet created if needed)
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
  $0 run-flutter-app linux --separate-instance    # Run Linux app with isolated data (no shared state)
  $0 run-flutter-app linux --separate-instance --instances 3   # Spawn 3 instances, one terminal, switch logs with 1-3
  $0 run-flutter-app android release <device-id>  # Run Android app in release mode on specific device
  $0 show-android-logs                            # Show filtered Android logs (in separate terminal)
  $0 run-flutter-web dev                          # Run web app in dev mode
  $0 test-integration                              # Run client-core integration tests
  $0 test-api-server                               # Test server endpoints
  $0 test-flutter-integration ui                  # Run UI integration tests
  $0 test-flutter-integration-multi-app                    # Run all multi-app sync tests
  $0 test-flutter-integration-multi-app 2                 # Run file 2 only
  $0 test-flutter-integration-multi-app 2.2               # Run test 2 in file 2
  $0 test-flutter-integration-multi-app 4.1 4.2            # Run tests 1 and 2 in file 4
  $0 test-flutter-integration-multi-app 2 4.1              # Run all tests in file 2, and test 1 in file 4
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
        cmd_reset_database_complete "${2:-}" "${3:-}" "${4:-}"
        ;;
    reset-database-only)
        cmd_reset_database_only "${2:-}" "${3:-}" "${4:-}"
        ;;
    import-backup)
        if [ -z "$2" ]; then
            print_error "Import requires a backup file, username, and wallet"
            echo "Usage: $0 import-backup <backup.zip> <username> <wallet>"
            exit 1
        fi
        cmd_import_backup "$2" "${3:-}" "${4:-}"
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
    test-integration)
        cmd_test_integration
        ;;
    test-api-server)
        cmd_test_api_server
        ;;
    test-flutter-integration)
        cmd_test_flutter_integration "${2:-integration_test/ui_integration_test.dart}" "${@:3}"
        ;;
    test-flutter-integration-multi-app)
        cmd_test_flutter_integration_multi_app
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
