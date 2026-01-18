#!/bin/bash
# Verify backup integrity
# Usage: ./verify-backup.sh <backup_file>

set -e

BACKUP_FILE="${1}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

if [ -z "${BACKUP_FILE}" ]; then
    log_error "Usage: $0 <backup_file>"
    exit 1
fi

if [ ! -f "${BACKUP_FILE}" ]; then
    log_error "Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

log "Verifying backup: ${BACKUP_FILE}"

# Check file exists and is readable
if [ ! -r "${BACKUP_FILE}" ]; then
    log_error "Backup file is not readable"
    exit 1
fi
log_success "File is readable"

# Check file size (should be > 0)
FILE_SIZE=$(stat -f%z "${BACKUP_FILE}" 2>/dev/null || stat -c%s "${BACKUP_FILE}" 2>/dev/null)
if [ "${FILE_SIZE}" -eq 0 ]; then
    log_error "Backup file is empty"
    exit 1
fi
log_success "File size: $(numfmt --to=iec-i --suffix=B ${FILE_SIZE})"

# Check if encrypted
TEMP_FILE=""
if [[ "${BACKUP_FILE}" == *.enc ]]; then
    log "Backup is encrypted, testing decryption..."
    
    if [ -z "${BACKUP_ENCRYPTION_KEY}" ]; then
        log_warning "BACKUP_ENCRYPTION_KEY not set, skipping encryption test"
    else
        TEMP_FILE="/tmp/backup_verify_$$.gz"
        if echo "${BACKUP_ENCRYPTION_KEY}" | \
            openssl enc -d -aes-256-cbc -pbkdf2 \
            -in "${BACKUP_FILE}" \
            -out "${TEMP_FILE}" \
            -pass stdin 2>/dev/null; then
            log_success "Decryption successful"
            BACKUP_FILE="${TEMP_FILE}"
        else
            log_error "Decryption failed - backup may be corrupted or wrong key"
            exit 1
        fi
    fi
fi

# Check if compressed
if [[ "${BACKUP_FILE}" == *.gz ]] || [ -n "${TEMP_FILE}" ]; then
    log "Testing decompression..."
    if gunzip -t "${BACKUP_FILE}" 2>/dev/null; then
        log_success "Compression is valid"
    else
        log_error "Compression is corrupted"
        [ -n "${TEMP_FILE}" ] && rm -f "${TEMP_FILE}"
        exit 1
    fi
fi

# Check if it's a valid SQL dump
log "Checking SQL dump validity..."
DECOMPRESSED="/tmp/backup_sql_$$.sql"

if [[ "${BACKUP_FILE}" == *.gz ]]; then
    gunzip -c "${BACKUP_FILE}" > "${DECOMPRESSED}"
else
    cp "${BACKUP_FILE}" "${DECOMPRESSED}"
fi

# Check for PostgreSQL dump header
if head -n 1 "${DECOMPRESSED}" | grep -q "PostgreSQL database dump"; then
    log_success "Valid PostgreSQL dump header found"
else
    log_warning "PostgreSQL dump header not found, but file may still be valid"
fi

# Check for SQL syntax (basic check)
if grep -q "CREATE TABLE\|INSERT INTO\|COPY" "${DECOMPRESSED}" 2>/dev/null; then
    log_success "Contains SQL statements"
else
    log_warning "No obvious SQL statements found"
fi

# Cleanup
rm -f "${DECOMPRESSED}"
[ -n "${TEMP_FILE}" ] && rm -f "${TEMP_FILE}"

log_success "Backup verification completed successfully!"
log "Backup file appears to be valid and restorable"
