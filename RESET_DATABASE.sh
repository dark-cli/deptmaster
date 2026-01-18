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
    docker-compose up -d postgres redis
    echo "⏳ Waiting for PostgreSQL to be ready..."
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

echo "🗑️  Dropping existing database..."
docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d postgres <<EOF
-- Terminate existing connections
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();

-- Drop and recreate database
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME;
EOF

echo "✅ Database reset complete"
echo ""

echo "📝 Running migrations..."
cd backend/rust-api

# Try to run migrations using sqlx-cli if available
if command -v sqlx &> /dev/null; then
    echo "   Using sqlx-cli..."
    sqlx migrate run --database-url "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
else
    echo "   sqlx-cli not found, running migrations manually via psql..."
    # Run migrations directly via psql
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/001_initial_schema.sql
    docker exec -i debt_tracker_postgres psql -U "$DB_USER" -d "$DB_NAME" < migrations/002_remove_transaction_settled.sql 2>/dev/null || true
fi

cd ../..

echo "✅ Migrations complete"
echo ""

echo "📥 Importing data from Debitum backup..."
cd scripts

# Check if Python script exists
if [ ! -f "migrate_debitum.py" ]; then
    echo "❌ migrate_debitum.py not found in scripts directory"
    exit 1
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

# Run Python migration script
echo "🔄 Running migration script..."
python3 migrate_debitum.py "$SQLITE_DB" || {
    echo "❌ Failed to import data"
    echo "💡 Make sure you have required Python packages: pip3 install sqlalchemy psycopg2-binary"
    rm -rf "$TEMP_DIR"
    exit 1
}

# Cleanup
rm -rf "$TEMP_DIR"

cd "$SCRIPT_DIR"

echo ""
echo "✅ Database reset and import complete!"
echo ""
echo "📊 You can now:"
echo "   - View data in admin panel: http://localhost:8000/admin"
echo "   - Start the server: ./START_SERVER.sh"
echo "   - View in Flutter app: http://localhost:8080"
echo ""
