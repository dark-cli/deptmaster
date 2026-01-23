# Reset Database

## Overview

Use the unified `manage.sh` script to reset the PostgreSQL database and import data from a Debitum backup ZIP file.

## Usage

### Basic Usage (with default backup file)

```bash
./manage.sh reset
```

This will reset the database and EventStore.

### Reset and Import from Backup

```bash
./manage.sh reset /path/to/your/backup.zip
```

Or use the full-flash command (recommended):

```bash
./manage.sh full-flash /path/to/your/backup.zip
```

### Reset Database Only

```bash
./manage.sh reset-db
```

## What the Script Does

1. **Checks prerequisites**:
   - Verifies backup file exists
   - Checks Docker is running
   - Ensures PostgreSQL container is running

2. **Resets database**:
   - Drops existing `debt_tracker` database
   - Creates fresh database
   - Terminates existing connections

3. **Runs migrations**:
   - Applies all database migrations
   - Creates tables and schema

4. **Imports data**:
   - Extracts Debitum backup ZIP
   - Finds SQLite database in backup
   - Migrates data from SQLite to PostgreSQL
   - Imports contacts and transactions

## Prerequisites

1. **Docker and Docker Compose**:
   ```bash
   # Start Docker services
   cd backend
   docker-compose up -d
   ```

2. **Python dependencies**:
   ```bash
   pip3 install sqlalchemy psycopg2-binary
   ```

3. **Backup file**:
   - Place your `debitum-backup-*.zip` file in the project root
   - Or provide full path when running script

## Environment Variables

You can customize database connection:

```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=debt_tracker
export DB_USER=debt_tracker
export DB_PASSWORD=dev_password

./RESET_DATABASE.sh
```

## Example Output

```
🔄 Resetting database and importing Debitum backup...
📦 Backup file: debitum-backup-2026-01-18T05_51_03.zip

🗑️  Dropping existing database...
✅ Database reset complete

📝 Running migrations...
✅ Migrations complete

📥 Importing data from Debitum backup...
📂 Extracting backup to: /tmp/tmp.XXXXXX
📊 Found SQLite database: /tmp/tmp.XXXXXX/debitum.db
🔄 Running migration script...
✅ Database reset and import complete!

📊 You can now:
   - View data in admin panel: http://localhost:8000/admin
   - Start the server: ./START_SERVER.sh
   - View in Flutter app: http://localhost:8080
```

## Troubleshooting

### Backup File Not Found

```
❌ Backup file not found: debitum-backup-2026-01-18T05_51_03.zip
```

**Solution**: Provide the full path to your backup file:
```bash
./RESET_DATABASE.sh /path/to/debitum-backup-2026-01-18T05_51_03.zip
```

### Docker Not Running

```
❌ Docker is not running. Please start Docker first.
```

**Solution**: Start Docker and containers:
```bash
cd backend
docker-compose up -d
```

### Python Dependencies Missing

```
❌ Failed to import data
💡 Make sure you have required Python packages: pip3 install sqlalchemy psycopg2-binary
```

**Solution**: Install Python dependencies:
```bash
pip3 install sqlalchemy psycopg2-binary
```

### No SQLite Database in Backup

```
❌ No SQLite database found in backup file
```

**Solution**: Verify your backup file contains a `.db`, `.sqlite`, or `.sqlite3` file. The backup should be a ZIP file containing the Debitum SQLite database.

## Notes

- **This script will DELETE all existing data** in the database
- Make sure you have a backup if you need to preserve current data
- The script automatically handles database connection termination
- Migrations are run automatically after database reset
- The script cleans up temporary files after import

## Related Scripts

- `START_SERVER.sh` - Start the backend server
- `scripts/migrate_debitum.py` - Python script that does the actual data migration
- `scripts/import_debitum_backup.sh` - Alternative import script (if exists)
