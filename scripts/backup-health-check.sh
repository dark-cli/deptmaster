#!/bin/bash
# Backup health check script
# Checks if backups are being created regularly and are valid

set -e

BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
MIN_BACKUP_SIZE=1024  # 1KB minimum
MAX_HOURS_SINCE_LAST_BACKUP=24
EXIT_CODE=0

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
    EXIT_CODE=1
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log "Starting backup health check..."

# Check if backups directory exists
if [ ! -d "${BACKUP_DIR}" ]; then
    log_error "Backup directory not found: ${BACKUP_DIR}"
    exit 1
fi
log_success "Backup directory exists"

# Check for recent backups (within last MAX_HOURS_SINCE_LAST_BACKUP hours)
RECENT_BACKUPS=$(find "${BACKUP_DIR}" -name "debitum_backup_*" -type f -mtime -$(echo "scale=2; ${MAX_HOURS_SINCE_LAST_BACKUP}/24" | bc) 2>/dev/null | wc -l)

if [ "${RECENT_BACKUPS}" -eq 0 ]; then
    log_error "No backups found in the last ${MAX_HOURS_SINCE_LAST_BACKUP} hours"
    EXIT_CODE=1
else
    log_success "Found ${RECENT_BACKUPS} backup(s) in the last ${MAX_HOURS_SINCE_LAST_BACKUP} hours"
fi

# Find most recent backup
MOST_RECENT=$(find "${BACKUP_DIR}" -name "debitum_backup_*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "${MOST_RECENT}" ]; then
    HOURS_AGO=$(echo "($(date +%s) - $(stat -c %Y "${MOST_RECENT}" 2>/dev/null || stat -f %m "${MOST_RECENT}")) / 3600" | bc)
    log "Most recent backup: ${MOST_RECENT} (${HOURS_AGO} hours ago)"
    
    if [ "${HOURS_AGO}" -gt "${MAX_HOURS_SINCE_LAST_BACKUP}" ]; then
        log_error "Most recent backup is ${HOURS_AGO} hours old (threshold: ${MAX_HOURS_SINCE_LAST_BACKUP} hours)"
        EXIT_CODE=1
    fi
fi

# Check backup sizes
log "Checking backup file sizes..."
SUSPICIOUS_BACKUPS=0
for backup in "${BACKUP_DIR}"/debitum_backup_*; do
    if [ -f "${backup}" ]; then
        SIZE=$(stat -f%z "${backup}" 2>/dev/null || stat -c%s "${backup}" 2>/dev/null)
        if [ "${SIZE}" -lt "${MIN_BACKUP_SIZE}" ]; then
            log_warning "Backup ${backup} is suspiciously small (${SIZE} bytes)"
            SUSPICIOUS_BACKUPS=$((SUSPICIOUS_BACKUPS + 1))
        fi
    fi
done

if [ "${SUSPICIOUS_BACKUPS}" -gt 0 ]; then
    log_warning "Found ${SUSPICIOUS_BACKUPS} suspicious backup(s)"
else
    log_success "All backup sizes look reasonable"
fi

# Check backup log
if [ -f "${BACKUP_DIR}/backup.log" ]; then
    LOG_SIZE=$(stat -f%z "${BACKUP_DIR}/backup.log" 2>/dev/null || stat -c%s "${BACKUP_DIR}/backup.log" 2>/dev/null)
    if [ "${LOG_SIZE}" -gt 0 ]; then
        log_success "Backup log exists and has content"
        
        # Check for recent errors in log
        RECENT_ERRORS=$(grep -i "error\|failed" "${BACKUP_DIR}/backup.log" | tail -5 | wc -l)
        if [ "${RECENT_ERRORS}" -gt 0 ]; then
            log_warning "Found ${RECENT_ERRORS} recent error(s) in backup log"
        fi
    else
        log_warning "Backup log is empty"
    fi
else
    log_warning "Backup log not found"
fi

# Check disk space
log "Checking available disk space..."
AVAILABLE_SPACE=$(df -h "${BACKUP_DIR}" | tail -1 | awk '{print $4}')
log "Available space: ${AVAILABLE_SPACE}"

# Summary
echo ""
if [ "${EXIT_CODE}" -eq 0 ]; then
    log_success "Backup health check passed"
else
    log_error "Backup health check failed - please investigate"
fi

exit ${EXIT_CODE}
