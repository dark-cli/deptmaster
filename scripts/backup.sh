#!/bin/sh
# Database backup script for Debitum
# Runs inside Docker container

set -e

# Configuration
DB_HOST="${DB_HOST:-postgres}"
DB_NAME="${DB_NAME:-debitum_prod}"
DB_USER="${DB_USER:-debitum}"
BACKUP_DIR="/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/debitum_backup_${TIMESTAMP}.sql"
BACKUP_FILE_GZ="${BACKUP_FILE}.gz"
BACKUP_FILE_ENCRYPTED="${BACKUP_FILE_GZ}.enc"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ ERROR: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ WARNING: $1${NC}"
}

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

log "Starting backup of ${DB_NAME}..."

# Wait for PostgreSQL to be ready
log "Waiting for PostgreSQL to be ready..."
until pg_isready -h "${DB_HOST}" -U "${DB_USER}" > /dev/null 2>&1; do
    log "PostgreSQL is not ready yet, waiting..."
    sleep 2
done
log_success "PostgreSQL is ready"

# Perform database dump
log "Dumping database..."
if pg_dump -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" \
    --no-password \
    --format=plain \
    --verbose \
    --no-owner \
    --no-acl \
    > "${BACKUP_FILE}" 2>&1; then
    log_success "Database dump completed"
else
    log_error "Database dump failed"
    exit 1
fi

# Check if dump file is not empty
if [ ! -s "${BACKUP_FILE}" ]; then
    log_error "Backup file is empty"
    exit 1
fi

# Compress backup
log "Compressing backup..."
if gzip -f "${BACKUP_FILE}"; then
    BACKUP_SIZE=$(du -h "${BACKUP_FILE_GZ}" | cut -f1)
    log_success "Backup compressed: ${BACKUP_FILE_GZ} (${BACKUP_SIZE})"
    BACKUP_FILE="${BACKUP_FILE_GZ}"
else
    log_error "Compression failed"
    exit 1
fi

# Encrypt backup if encryption key is provided
if [ -n "${BACKUP_ENCRYPTION_KEY}" ]; then
    log "Encrypting backup..."
    if echo "${BACKUP_ENCRYPTION_KEY}" | \
        openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "${BACKUP_FILE}" \
        -out "${BACKUP_FILE_ENCRYPTED}" \
        -pass stdin 2>/dev/null; then
        BACKUP_SIZE=$(du -h "${BACKUP_FILE_ENCRYPTED}" | cut -f1)
        log_success "Backup encrypted: ${BACKUP_FILE_ENCRYPTED} (${BACKUP_SIZE})"
        rm -f "${BACKUP_FILE}"  # Remove unencrypted file
        BACKUP_FILE="${BACKUP_FILE_ENCRYPTED}"
    else
        log_error "Encryption failed"
        exit 1
    fi
fi

# Upload to S3/MinIO if configured
if [ -n "${S3_ENDPOINT}" ] && [ -n "${S3_ACCESS_KEY}" ] && [ -n "${S3_SECRET_KEY}" ]; then
    log "Uploading to S3-compatible storage..."
    
    # Install aws-cli if not present
    if ! command -v aws &> /dev/null; then
        log "Installing aws-cli..."
        apk add --no-cache aws-cli > /dev/null 2>&1 || {
            log_warning "Could not install aws-cli, skipping S3 upload"
            S3_ENDPOINT=""
        }
    fi
    
    if [ -n "${S3_ENDPOINT}" ]; then
        # Upload to S3
        S3_FILENAME="debitum_backup_${TIMESTAMP}.${BACKUP_FILE##*.}"
        if aws --endpoint-url="${S3_ENDPOINT}" \
            s3 cp "${BACKUP_FILE}" \
            "s3://${S3_BUCKET}/${S3_FILENAME}" \
            --access-key-id "${S3_ACCESS_KEY}" \
            --secret-access-key "${S3_SECRET_KEY}" \
            --quiet 2>&1; then
            log_success "Backup uploaded to S3: s3://${S3_BUCKET}/${S3_FILENAME}"
        else
            log_warning "S3 upload failed, but local backup is saved"
        fi
    fi
fi

# Calculate final backup size
BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
log_success "Backup completed successfully: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Clean up old backups (local)
log "Cleaning up backups older than ${RETENTION_DAYS} days..."
DELETED_COUNT=$(find "${BACKUP_DIR}" -name "debitum_backup_*" -type f -mtime +${RETENTION_DAYS} -delete -print | wc -l)
if [ "${DELETED_COUNT}" -gt 0 ]; then
    log_success "Cleaned up ${DELETED_COUNT} old backup(s)"
else
    log "No old backups to clean up"
fi

# Log backup completion
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Backup completed: ${BACKUP_FILE} (${BACKUP_SIZE})" >> "${BACKUP_DIR}/backup.log"

# Keep only last 1000 lines of log file
tail -n 1000 "${BACKUP_DIR}/backup.log" > "${BACKUP_DIR}/backup.log.tmp" && \
    mv "${BACKUP_DIR}/backup.log.tmp" "${BACKUP_DIR}/backup.log"

exit 0
