#!/bin/bash
# Unified management script for Debt Tracker
# Usage: ./manage.sh <command> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

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

# Helper functions
print_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
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
    
    print_info "Waiting for $name to be ready..."
    for i in $(seq 1 $max_retries); do
        if curl -f "$url" > /dev/null 2>&1; then
            print_success "$name is ready"
            return 0
        fi
        sleep $delay
    done
    print_error "$name failed to start"
    return 1
}

# Commands
cmd_reset() {
    local import_file="${1:-}"
    
    print_info "Resetting system (database + EventStore)..."
    
    check_docker
    
    # Stop server if running
    print_info "Stopping server..."
    pkill -f "debt-tracker-api" || true
    sleep 2
    
    # Reset EventStore
    cmd_reset_eventstore
    
    # Reset database
    cmd_reset_database
    
    # If import file provided, import data
    if [ -n "$import_file" ]; then
        cmd_import "$import_file"
    else
        print_info "No import file provided. Database is clean and ready."
    fi
}

cmd_reset_database() {
    print_info "Resetting PostgreSQL database..."
    
    check_docker
    
    # Ensure PostgreSQL is running
    if ! docker ps | grep -q "debt_tracker_postgres"; then
        print_warning "PostgreSQL not running. Starting..."
        cd backend
        docker-compose up -d postgres
        sleep 5
        cd ..
    fi
    
    print_info "Terminating all connections..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres <<EOF
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();
EOF
    
    print_info "Dropping database..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
EOF
    sleep 1
    
    print_info "Creating fresh database..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres <<EOF
CREATE DATABASE $DB_NAME;
EOF
    
    print_info "Running migrations..."
    cd backend/rust-api
    
    if command -v sqlx &> /dev/null; then
        sqlx migrate run --database-url "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
    else
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/001_initial_schema.sql
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/002_remove_transaction_settled.sql 2>/dev/null || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/003_add_due_date.sql 2>/dev/null || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/004_user_settings.sql 2>/dev/null || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/005_create_default_user.sql 2>/dev/null || true
        docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/006_add_username_to_contacts.sql 2>/dev/null || true
    fi
    
    # Ensure only the "max" user exists (clean up any other users)
    print_info "Ensuring only default user exists..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" <<EOF
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
    
    cd "$SCRIPT_DIR"
    print_success "Database reset complete"
}

cmd_reset_eventstore() {
    print_info "Resetting EventStore..."
    
    check_docker
    
    if docker ps | grep -q "debt_tracker_eventstore"; then
        print_info "Stopping EventStore..."
        docker stop debt_tracker_eventstore || true
        docker rm debt_tracker_eventstore || true
    fi
    
    print_info "Removing EventStore data volume..."
    docker volume rm eventstore_data 2>/dev/null || true
    
    print_info "Starting fresh EventStore..."
    cd backend
    docker-compose up -d eventstore
    cd ..
    
    wait_for_service "http://localhost:2113/health/live" "EventStore" 30 2
    print_success "EventStore reset complete"
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
    
    print_info "Importing data from: $backup_file"
    
    # Ensure EventStore is running
    if ! docker ps | grep -q "debt_tracker_eventstore"; then
        print_warning "EventStore not running. Starting..."
        cd backend
        docker-compose up -d eventstore
        wait_for_service "http://localhost:2113/health/live" "EventStore" 30 2
        cd ..
    fi
    
    # Ensure server is running
    if ! curl -f http://localhost:8000/health > /dev/null 2>&1; then
        print_warning "Server not running. Starting..."
        cmd_start_server
    fi
    
    # Extract backup
    TEMP_DIR=$(mktemp -d)
    print_info "Extracting backup to: $TEMP_DIR"
    
    unzip -q "$backup_file" -d "$TEMP_DIR" || {
        print_error "Failed to extract backup file"
        rm -rf "$TEMP_DIR"
        exit 1
    }
    
    # Find SQLite database
    SQLITE_DB=$(find "$TEMP_DIR" -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" | head -1)
    
    if [ -z "$SQLITE_DB" ]; then
        print_error "No SQLite database found in backup file"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    print_info "Found SQLite database: $SQLITE_DB"
    
    # Check for Python script and dependencies
    if [ ! -f "scripts/migrate_debitum_via_api.py" ]; then
        print_error "migrate_debitum_via_api.py not found"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    if ! python3 -c "import requests" 2>/dev/null; then
        print_warning "Python 'requests' library not found. Installing..."
        pip3 install requests || {
            print_error "Failed to install requests library"
            rm -rf "$TEMP_DIR"
            exit 1
        }
    fi
    
    # Run migration
    print_info "Running migration via API (creates EventStore events naturally)..."
    python3 scripts/migrate_debitum_via_api.py "$SQLITE_DB" || {
        print_error "Failed to import data"
        rm -rf "$TEMP_DIR"
        exit 1
    }
    
    rm -rf "$TEMP_DIR"
    print_success "Import complete! All data has EventStore events."
}

cmd_start_services() {
    print_info "Starting Docker services..."
    
    check_docker
    
    cd backend
    
    if [ "$1" = "postgres" ] || [ -z "$1" ]; then
        print_info "Starting PostgreSQL..."
        docker-compose up -d postgres
        sleep 5
    fi
    
    if [ "$1" = "eventstore" ] || [ -z "$1" ]; then
        print_info "Starting EventStore..."
        docker-compose up -d eventstore
        wait_for_service "http://localhost:2113/health/live" "EventStore" 30 2
    fi
    
    if [ "$1" = "redis" ] || [ -z "$1" ]; then
        print_info "Starting Redis..."
        docker-compose up -d redis
        sleep 3
    fi
    
    if [ -z "$1" ]; then
        print_info "Starting all services..."
        docker-compose up -d postgres eventstore redis
    fi
    
    cd ..
    print_success "Services started"
}

cmd_stop_services() {
    print_info "Stopping Docker services..."
    
    check_docker
    
    cd backend
    
    if [ "$1" = "postgres" ]; then
        docker-compose stop postgres
    elif [ "$1" = "eventstore" ]; then
        docker-compose stop eventstore
    elif [ "$1" = "redis" ]; then
        docker-compose stop redis
    else
        docker-compose stop
    fi
    
    cd ..
    print_success "Services stopped"
}

cmd_start_server() {
    print_info "Starting API server..."
    
    # Stop any existing server
    pkill -f "debt-tracker-api" || true
    sleep 2
    
    # Ensure services are running
    cmd_start_services
    
    # Build if needed
    if [ ! -f "backend/rust-api/target/release/debt-tracker-api" ]; then
        print_info "Building server (this may take a minute)..."
        cd backend/rust-api
        cargo build --release
        cd "$SCRIPT_DIR"
    fi
    
    # Start server
    print_info "Starting server..."
    nohup backend/rust-api/target/release/debt-tracker-api > /tmp/debt-tracker-api.log 2>&1 &
    
    wait_for_service "http://localhost:8000/health" "API Server" 30 1
    print_success "Server started! Logs: /tmp/debt-tracker-api.log"
}

cmd_stop_server() {
    print_info "Stopping API server..."
    
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

cmd_build() {
    print_info "Building server..."
    
    cd backend/rust-api
    cargo build --release
    cd "$SCRIPT_DIR"
    
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
        
        if docker ps | grep -q "debt_tracker_eventstore"; then
            if curl -f http://localhost:2113/health/live > /dev/null 2>&1; then
                echo "    ✅ EventStore (healthy)"
            else
                echo "    ⚠️  EventStore (running but not healthy)"
            fi
        else
            echo "    ❌ EventStore (not running)"
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
    echo "   - EventStore UI: http://localhost:2113 (admin/changeit)"
    echo "   - Server Logs: tail -f /tmp/debt-tracker-api.log"
}

cmd_logs() {
    if [ -f "/tmp/debt-tracker-api.log" ]; then
        tail -f /tmp/debt-tracker-api.log
    else
        print_error "Log file not found. Server may not be running."
    fi
}

cmd_help() {
    cat <<EOF
Debt Tracker Management Script

Usage: $0 <command> [options]

Commands:
  reset [backup.zip]          Reset database + EventStore, optionally import data
  reset-db                    Reset PostgreSQL database only
  reset-eventstore            Reset EventStore only
  import <backup.zip>         Import data from Debitum backup (creates events)
  
  start-services [name]    Start Docker services (postgres/eventstore/redis/all)
  stop-services [name]      Stop Docker services
  start-server              Start API server
  stop-server               Stop API server
  restart-server            Restart API server
  build                     Build the server (cargo build --release)
  
  status                    Show system status
  logs                      Show server logs (tail -f)
  help                      Show this help message

Examples:
  $0 reset                           # Clean reset (no data)
  $0 reset backup.zip                # Reset and import from backup
  $0 import backup.zip               # Import data (keeps existing data)
  $0 start-server                    # Start everything
  $0 restart-server                  # Restart server
  $0 status                          # Check what's running

Environment Variables:
  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD  Database connection settings

EOF
}

# Main command dispatcher
case "${1:-help}" in
    reset)
        cmd_reset "${2:-}"
        ;;
    reset-db|reset-database)
        cmd_reset_database
        ;;
    reset-eventstore)
        cmd_reset_eventstore
        ;;
    import)
        if [ -z "$2" ]; then
            print_error "Import requires a backup file"
            echo "Usage: $0 import <backup.zip>"
            exit 1
        fi
        cmd_import "$2"
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
