#!/bin/bash
# Reset database and import Debitum backup data
# Usage: ./RESET_DATABASE.sh [path-to-backup.zip]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Default backup file
DEFAULT_BACKUP="debitum-backup-2026-01-18T05_51_03.zip"
BACKUP_FILE="${1:-$DEFAULT_BACKUP}"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Backup file not found: $BACKUP_FILE"
    echo ""
    echo "Usage: $0 [path-to-backup.zip]"
    echo ""
    echo "Looking for backup file in current directory..."
    ls -la *.zip 2>/dev/null || echo "No .zip files found in current directory"
    exit 1
fi

echo "🔄 Resetting database and importing Debitum backup..."
echo "📦 Backup file: $BACKUP_FILE"
echo ""

# Check if Docker is running
if ! docker ps > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Check if PostgreSQL container is running
if ! docker ps | grep -q "debt_tracker_postgres"; then
    echo "⚠️  PostgreSQL container not running. Starting Docker services..."
    cd backend
    docker-compose up -d postgres redis eventstore
    echo "⏳ Waiting for PostgreSQL and EventStore to be ready..."
    sleep 5
    cd ..
fi

# Check if EventStore container is running
if ! docker ps | grep -q "debt_tracker_eventstore"; then
    echo "⚠️  EventStore container not running. Starting EventStore..."
    cd backend
    docker-compose up -d eventstore
    echo "⏳ Waiting for EventStore to be ready..."
    sleep 5
    cd ..
fi

# Database connection details
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-debt_tracker}"
DB_USER="${DB_USER:-debt_tracker}"
DB_PASSWORD="${DB_PASSWORD:-dev_password}"

export PGPASSWORD="$DB_PASSWORD"

echo "🗑️  Flushing all old database data..."
echo ""

# Step 1: Terminate all connections to the database
echo "   1️⃣  Terminating all connections to '$DB_NAME'..."
docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres <<EOF
-- Force terminate all connections to the database
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();
EOF
echo "   ✅ All connections terminated"
echo ""

# Step 2: Drop the database completely
echo "   2️⃣  Dropping database '$DB_NAME'..."
docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres <<EOF
-- Drop database if it exists (this will fail if there are still connections)
DROP DATABASE IF EXISTS $DB_NAME;
EOF

# Wait a moment for the drop to complete
sleep 1

# Step 3: Verify database is gone
echo "   3️⃣  Verifying database is completely removed..."
DB_EXISTS=$(docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || echo "0")

if [ "$DB_EXISTS" = "1" ]; then
    echo "   ⚠️  Database still exists, trying force drop..."
    # Try to drop again with more aggressive connection termination
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres <<EOF
-- Terminate all connections more aggressively
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$DB_NAME';

-- Wait a moment
SELECT pg_sleep(1);

-- Drop database
DROP DATABASE IF EXISTS $DB_NAME;
EOF
    sleep 1
    DB_EXISTS=$(docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null || echo "0")
    
    if [ "$DB_EXISTS" = "1" ]; then
        echo "   ❌ ERROR: Could not drop database. There may be active connections."
        echo "   💡 Try stopping the backend server first: ./STOP_SERVER.sh"
        exit 1
    fi
fi
echo "   ✅ Database successfully dropped"
echo ""

# Step 4: Create fresh empty database
echo "   4️⃣  Creating fresh empty database..."
docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres <<EOF
CREATE DATABASE $DB_NAME;
EOF

# Step 5: Verify database is empty
echo "   5️⃣  Verifying database is completely empty..."
TABLE_COUNT=$(docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" != "0" ]; then
    echo "   ⚠️  WARNING: Database contains $TABLE_COUNT tables (should be 0)"
    echo "   🧹 Cleaning up any remaining tables..."
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" <<EOF
-- Drop all tables if any exist
DO \$\$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE';
    END LOOP;
END \$\$;
EOF
    echo "   ✅ Remaining tables cleaned up"
else
    echo "   ✅ Database is completely empty"
fi

echo ""
echo "✅ Database completely flushed and reset"
echo ""

echo "📝 Running migrations..."
cd backend/rust-api

# Try to run migrations using sqlx-cli if available
if command -v sqlx &> /dev/null; then
    echo "   Using sqlx-cli..."
    sqlx migrate run --database-url "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
else
    echo "   sqlx-cli not found, running migrations manually via psql..."
    # Run migrations directly via psql (from backend/rust-api directory)
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/001_initial_schema.sql
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/002_remove_transaction_settled.sql 2>/dev/null || true
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/003_add_due_date.sql 2>/dev/null || true
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/004_user_settings.sql 2>/dev/null || true
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/005_create_default_user.sql 2>/dev/null || true
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/006_add_username_to_contacts.sql 2>/dev/null || true
fi

cd ../..

echo "✅ Migrations complete"
echo ""

echo "🗑️  Resetting EventStore (must be clean before importing)..."
# EventStore must be reset BEFORE importing data so events are created naturally
if docker ps | grep -q "debt_tracker_eventstore"; then
    echo "   Stopping EventStore container..."
    docker stop debt_tracker_eventstore || true
    docker rm debt_tracker_eventstore || true
    echo "   Removing EventStore data volume..."
    docker volume rm eventstore_data 2>/dev/null || true
    echo "   Starting fresh EventStore..."
    cd backend
    docker-compose up -d eventstore
    echo "⏳ Waiting for EventStore to be ready..."
    sleep 10
    cd ..
    echo "   ✅ EventStore reset complete"
else
    echo "   ⚠️  EventStore container not running, starting it..."
    cd backend
    docker-compose up -d eventstore
    echo "⏳ Waiting for EventStore to be ready..."
    sleep 10
    cd ..
    echo "   ✅ EventStore started"
fi

echo ""
echo "🚀 Starting API server (required for natural data insertion)..."
# Stop any existing server
pkill -f "debt-tracker-api" || true
sleep 2

# Start the server in the background
cd backend/rust-api
if [ -f "target/release/debt-tracker-api" ]; then
    echo "   Using release build..."
    nohup target/release/debt-tracker-api > /tmp/debt-tracker-api.log 2>&1 &
else
    echo "   Building and starting server (this may take a minute)..."
    cargo build --release
    nohup target/release/debt-tracker-api > /tmp/debt-tracker-api.log 2>&1 &
fi

cd "$SCRIPT_DIR"

# Wait for server to be ready
echo "⏳ Waiting for server to start..."
for i in {1..30}; do
    if curl -f http://localhost:8000/health > /dev/null 2>&1; then
        echo "   ✅ Server is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "   ❌ Server failed to start after 30 seconds"
        echo "   Check logs: tail -f /tmp/debt-tracker-api.log"
        exit 1
    fi
    sleep 1
done

echo ""
echo "📥 Importing data from Debitum backup via API (creates EventStore events naturally)..."
cd scripts

# Check if Python script exists
if [ ! -f "migrate_debitum_via_api.py" ]; then
    echo "❌ migrate_debitum_via_api.py not found in scripts directory"
    exit 1
fi

# Check if requests library is available
if ! python3 -c "import requests" 2>/dev/null; then
    echo "⚠️  Python 'requests' library not found. Installing..."
    pip3 install requests || {
        echo "❌ Failed to install requests library"
        echo "💡 Try: pip3 install requests"
        exit 1
    }
fi

# Extract backup to temp directory
TEMP_DIR=$(mktemp -d)
echo "📂 Extracting backup to: $TEMP_DIR"

unzip -q "$SCRIPT_DIR/$BACKUP_FILE" -d "$TEMP_DIR" || {
    echo "❌ Failed to extract backup file"
    rm -rf "$TEMP_DIR"
    exit 1
}

# Find the SQLite database in the extracted files
SQLITE_DB=$(find "$TEMP_DIR" -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" | head -1)

if [ -z "$SQLITE_DB" ]; then
    echo "❌ No SQLite database found in backup file"
    echo "📁 Contents of backup:"
    find "$TEMP_DIR" -type f | head -10
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "📊 Found SQLite database: $SQLITE_DB"
echo ""

# Run Python migration script via API
echo "🔄 Running migration via API (this creates EventStore events naturally)..."
python3 migrate_debitum_via_api.py "$SQLITE_DB" || {
    echo "❌ Failed to import data via API"
    echo "💡 Check server logs: tail -f /tmp/debt-tracker-api.log"
    rm -rf "$TEMP_DIR"
    exit 1
}

# Cleanup
rm -rf "$TEMP_DIR"

cd "$SCRIPT_DIR"

echo ""
echo "✅ Database and EventStore reset and import complete!"
echo ""
echo "📊 Server is running and data has been imported with EventStore events!"
echo ""
echo "🌐 You can now:"
echo "   - View data in admin panel: http://localhost:8000/admin"
echo "   - View EventStore UI: http://localhost:2113 (admin/changeit)"
echo "   - Check EventStore events: All contacts and transactions have events!"
echo "   - View in Flutter app: http://localhost:8080"
echo ""
echo "📝 Note: The server is already running. To restart it:"
echo "   ./RESTART_SERVER.sh"
echo ""
