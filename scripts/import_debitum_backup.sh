#!/bin/bash
# Import Debitum backup into Debt Tracker

set -e

BACKUP_FILE="${1}"

if [ -z "${BACKUP_FILE}" ]; then
    echo "Usage: $0 <path-to-debitum-backup.zip>"
    echo ""
    echo "Example:"
    echo "  $0 ~/Downloads/debitum-backup-2026-01-18T05_51_03.zip"
    exit 1
fi

if [ ! -f "${BACKUP_FILE}" ]; then
    echo "Error: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

echo "📦 Importing Debitum backup: ${BACKUP_FILE}"
echo ""

# Extract backup
TEMP_DIR=$(mktemp -d)
echo "📂 Extracting backup to ${TEMP_DIR}..."
unzip -q "${BACKUP_FILE}" -d "${TEMP_DIR}"

# Check for database file
if [ ! -f "${TEMP_DIR}/debitum.db" ]; then
    echo "Error: debitum.db not found in backup"
    exit 1
fi

echo "✅ Backup extracted"
echo ""

# Run Python migration script
echo "🔄 Migrating data..."
python3 scripts/migrate_debitum.py "${TEMP_DIR}/debitum.db"

echo ""
echo "✅ Migration complete!"
echo ""
echo "🧹 Cleaning up..."
rm -rf "${TEMP_DIR}"

echo ""
echo "✅ Done! Your Debitum data has been imported."
