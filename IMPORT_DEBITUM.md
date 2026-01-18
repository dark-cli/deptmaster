# Import Debitum Backup

## Quick Import

```bash
./scripts/import_debitum_backup.sh <path-to-your-backup.zip>
```

## Example

If your backup is in Downloads:
```bash
./scripts/import_debitum_backup.sh ~/Downloads/debitum-backup-2026-01-18T05_51_03.zip
```

Or if it's in the current directory:
```bash
./scripts/import_debitum_backup.sh ./debitum-backup-2026-01-18T05_51_03.zip
```

## What It Does

1. Extracts the Debitum backup ZIP
2. Reads the SQLite database
3. Converts Debitum data to event-sourced format:
   - Persons → Contacts (with events)
   - Transactions → Transactions (with events)
4. Imports into PostgreSQL
5. Creates all necessary events

## Manual Import (if script doesn't work)

```bash
# Extract backup
unzip debitum-backup-2026-01-18T05_51_03.zip -d temp_backup

# Run migration
python3 scripts/migrate_debitum.py temp_backup/debitum.db
```

## After Import

1. Restart the server (if running)
2. View data at: http://localhost:8000/admin
3. Your Debitum data is now in the new system!

## Notes

- Images are not migrated (you'll need to handle those separately)
- All data is converted to event-sourced format
- Original Debitum data structure is preserved in events
