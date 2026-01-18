# Backup Scripts

This directory contains scripts for automated database backups using Docker.

## Scripts

### `backup.sh`
Main backup script that runs inside the Docker backup container.
- Dumps PostgreSQL database
- Compresses backup
- Encrypts backup (if encryption key provided)
- Uploads to S3/MinIO (if configured)
- Cleans up old backups

**Usage**: Automatically runs via cron, or manually:
```bash
docker-compose exec backup /backup.sh
```

### `restore.sh`
Restore database from a backup file.
- Decrypts backup if encrypted
- Decompresses backup
- Restores to PostgreSQL
- Restarts services

**Usage**:
```bash
# Restore from local backup
./restore.sh /backups/debitum_backup_20240115_120000.sql.gz.enc

# Force restore (skip confirmation)
./restore.sh /backups/debitum_backup_20240115_120000.sql.gz.enc --force
```

### `verify-backup.sh`
Verify backup file integrity.
- Checks file size
- Tests decryption (if encrypted)
- Tests decompression
- Validates SQL dump format

**Usage**:
```bash
./verify-backup.sh /backups/debitum_backup_20240115_120000.sql.gz.enc
```

### `backup-health-check.sh`
Health check for backup system.
- Checks if backups are being created regularly
- Verifies backup file sizes
- Checks backup log for errors
- Monitors disk space

**Usage**:
```bash
./backup-health-check.sh
```

## Configuration

Set these environment variables in your `.env` file or Docker Compose:

```bash
# Database
DB_HOST=postgres
DB_NAME=debitum_prod
DB_USER=debitum
DB_PASSWORD=your_password

# Backup
BACKUP_ENCRYPTION_KEY=your_32_char_encryption_key
BACKUP_RETENTION_DAYS=30
BACKUP_SCHEDULE="0 */6 * * *"  # Every 6 hours

# Optional: S3/MinIO
S3_ENDPOINT=http://minio:9000
S3_ACCESS_KEY=your_access_key
S3_SECRET_KEY=your_secret_key
S3_BUCKET=debitum-backups
```

## Backup Schedule Examples

- **Every 6 hours**: `0 */6 * * *`
- **Every 4 hours**: `0 */4 * * *`
- **Every hour**: `0 * * * *`
- **Every 30 minutes**: `*/30 * * * *`
- **Daily at 2 AM**: `0 2 * * *`

## Backup Retention

Backups are automatically cleaned up based on `BACKUP_RETENTION_DAYS`:
- Default: 30 days
- Old backups are deleted automatically
- Only local backups are cleaned (S3 backups managed separately)

## Encryption

All backups are encrypted using AES-256-CBC with PBKDF2 key derivation.

**Generate encryption key**:
```bash
openssl rand -base64 32
```

## Restore Procedure

1. **Stop services** (optional, but recommended):
   ```bash
   docker-compose stop api worker
   ```

2. **Restore database**:
   ```bash
   ./restore.sh /backups/debitum_backup_20240115_120000.sql.gz.enc
   ```

3. **Restart services**:
   ```bash
   docker-compose start api worker
   ```

## Monitoring

### Check backup status
```bash
# View backup log
tail -f /backups/backup.log

# List recent backups
ls -lth /backups/debitum_backup_* | head -10

# Run health check
./backup-health-check.sh
```

### Set up monitoring alerts

Add to cron or monitoring system:
```bash
# Run health check every hour
0 * * * * /path/to/backup-health-check.sh || send-alert.sh
```

## Troubleshooting

### Backup fails
1. Check PostgreSQL is running: `docker-compose ps postgres`
2. Check backup log: `tail -f /backups/backup.log`
3. Test manual backup: `docker-compose exec backup /backup.sh`

### Restore fails
1. Verify backup file: `./verify-backup.sh <backup_file>`
2. Check disk space: `df -h`
3. Check PostgreSQL logs: `docker-compose logs postgres`

### Encryption issues
1. Verify encryption key is set: `echo $BACKUP_ENCRYPTION_KEY`
2. Test decryption manually:
   ```bash
   openssl enc -d -aes-256-cbc -pbkdf2 \
     -in backup.enc \
     -out backup.gz \
     -pass pass:your_key
   ```

## Best Practices

1. **Test restores regularly** - Monthly at minimum
2. **Monitor backup health** - Set up alerts for failures
3. **Multiple locations** - Use both local and S3 storage
4. **Encryption** - Always encrypt sensitive data
5. **Documentation** - Keep restore procedures documented
6. **Automation** - Fully automated, no manual steps
7. **Versioning** - Keep multiple backup versions
