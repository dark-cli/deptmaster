#!/bin/bash
# Restore script for Debitum database
# Usage: ./restore.sh <backup_file> [--force]

set -e

BACKUP_FILE="${1}"
FORCE="${2}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Configuration
DB_HOST="${DB_HOST:-postgres}"
DB_NAME="${DB_NAME:-debitum_prod}"
DB_USER="${DB_USER:-debitum}"
TEMP_DIR="/tmp/restore_$$"

if [ -z "${BACKUP_FILE}" ]; then
    log_error "Usage: $0 <backup_file> [--force]"
    echo ""
    echo "Available backups:"
    ls -lh /backups/debitum_backup_* 2>/dev/null | tail -10 || echo "No backups found"
    exit 1
fi

# Check if backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    log_error "Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

log "Starting restore from: ${BACKUP_FILE}"

# Create temp directory
mkdir -p "${TEMP_DIR}"
cd "${TEMP_DIR}"

# Decrypt if needed
if [[ "${BACKUP_FILE}" == *.enc ]]; then
    log "Backup is encrypted, decrypting..."
    DECRYPTED_FILE="${TEMP_DIR}/backup_decrypted.gz"
    
    if [ -z "${BACKUP_ENCRYPTION_KEY}" ]; then
        read -sp "Enter encryption key: " ENCRYPTION_KEY
        echo
    else
        ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY}"
    fi
    
    if echo "${ENCRYPTION_KEY}" | \
        openssl enc -d -aes-256-cbc -pbkdf2 \
        -in "${BACKUP_FILE}" \
        -out "${DECRYPTED_FILE}" \
        -pass stdin 2>/dev/null; then
        log_success "Backup decrypted"
        BACKUP_FILE="${DECRYPTED_FILE}"
    else
        log_error "Decryption failed"
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
fi

# Decompress if needed
if [[ "${BACKUP_FILE}" == *.gz ]]; then
    log "Decompressing backup..."
    DECOMPRESSED_FILE="${TEMP_DIR}/backup.sql"
    if gunzip -c "${BACKUP_FILE}" > "${DECOMPRESSED_FILE}" 2>/dev/null; then
        log_success "Backup decompressed"
        BACKUP_FILE="${DECOMPRESSED_FILE}"
    else
        log_error "Decompression failed"
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
fi

# Verify SQL file
if ! head -n 1 "${BACKUP_FILE}" | grep -q "PostgreSQL database dump"; then
    log_warning "File doesn't appear to be a PostgreSQL dump, continuing anyway..."
fi

# Confirm restore
if [ "${FORCE}" != "--force" ]; then
    log_warning "This will OVERWRITE the current database!"
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        log "Restore cancelled"
        rm -rf "${TEMP_DIR}"
        exit 0
    fi
fi

# Stop services (if docker-compose is available)
if command -v docker-compose &> /dev/null; then
    log "Stopping application services..."
    docker-compose stop api 2>/dev/null || log_warning "Could not stop services (may not be running)"
fi

# Wait for PostgreSQL to be ready
log "Waiting for PostgreSQL to be ready..."
until pg_isready -h "${DB_HOST}" -U "${DB_USER}" > /dev/null 2>&1; do
    log "PostgreSQL is not ready yet, waiting..."
    sleep 2
done

# Drop existing database and recreate (or just restore)
log "Restoring database..."
log_warning "This may take a while for large databases..."

if docker-compose exec -T postgres psql -U "${DB_USER}" -d "${DB_NAME}" < "${BACKUP_FILE}" 2>&1; then
    log_success "Database restored successfully"
else
    # Try alternative method
    log "Trying alternative restore method..."
    if docker-compose exec -T postgres bash -c "psql -U ${DB_USER} -d ${DB_NAME} < /dev/stdin" < "${BACKUP_FILE}" 2>&1; then
        log_success "Database restored successfully"
    else
        log_error "Database restore failed"
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
fi

# Restart services
if command -v docker-compose &> /dev/null; then
    log "Restarting application services..."
    docker-compose start api 2>/dev/null || log_warning "Could not start services"
fi

# Cleanup
rm -rf "${TEMP_DIR}"

log_success "Restore completed successfully!"
log "Database: ${DB_NAME}"
log "Backup file: ${1}"
