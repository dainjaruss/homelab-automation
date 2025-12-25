#!/bin/bash
################################################################################
# Improved Media Stack Backup Script - HOT BACKUP (No Container Stopping)
################################################################################
# Description: Safely backs up media stack configurations WITHOUT stopping
#              containers. Uses hot backup strategies to prevent database
#              corruption and service interruption.
#
# Key Improvements:
#   - Hot backups (containers stay running)
#   - SQLite-aware Plex database backup
#   - Backup verification (size checks)
#   - Retention policy (keeps last 5 backups from 2 weeks)
#   - Comprehensive logging with timestamps
#   - Proper exit codes for monitoring integration
#
# Backed Up Services:
#   Local (9): Plex, Sonarr, Radarr, Overseerr, Tautulli, Heimdall,
#              Scrypted, Uptime Kuma, Frigate
#   Remote (2): Sabnzbd (192.168.4.99), Nginx Proxy Manager (192.168.1.236)
#
# Schedule: Every 3 days at midnight (via n8n)
# Retention: 2 backups)
#
# Author: Homelab Automation Project
# Version: 2.1.0
# Last Updated: 2025-12-24
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

BACKUP_DIR="/mnt/server/backup/media-stack"
REMOTE_HOST="192.168.4.99"
REMOTE_USER="dainja"
BACKUP_DATE=$(date +%Y-%m-%d)
LOG_FILE="/mnt/server/logs/backup_improved.log"
RETENTION_COUNT=2  # Keep last 2 backups (6 day retenion with every-3-days schedule)

# Service directories - Local (on 192.168.1.142)
PLEX_DIR="/mnt/server/plex"
SONARR_DIR="/mnt/server/sonarr"
RADARR_DIR="/mnt/server/radarr"
OVERSEERR_DIR="/mnt/server/overseerr"
TAUTULLI_DIR="/mnt/server/tautulli"
HEIMDALL_DIR="/mnt/server/tools/heimdall"
SCRYPTED_DIR="/mnt/server/scrypted"
UPTIME_KUMA_DIR="/mnt/server/tools/uptime_kuma"
FRIGATE_DIR="/mnt/server/frigate"

# Service directories - Remote
REMOTE_SAB_DIR="/home/dainja/sabnzbd"
REMOTE_SAB_HOST="192.168.4.99"
REMOTE_NPM_DIR="/opt/npm"
REMOTE_NPM_HOST="192.168.1.236"

# Plex database path (critical for hot backup)
PLEX_DB_DIR="$PLEX_DIR/config/Library/Application Support/Plex Media Server/Plug-in Support/Databases"

################################################################################
# Functions
################################################################################

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error logging
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Verify backup file exists and meets a universal minimum size
verify_backup() {
    local backup_file="$1"
    local service_name="$2"
    # Enforce a universal minimum file size of 5KB for all backups
    local min_size_kb=5

    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    local file_size_kb=$(du -k "$backup_file" | cut -f1)

    if [ "$file_size_kb" -lt "$min_size_kb" ]; then
        log_error "$service_name backup too small: ${file_size_kb}KB (minimum: ${min_size_kb}KB)"
        return 1
    fi

    log "✓ $service_name backup verified: ${file_size_kb}KB"
    return 0
}

# Hot backup for Plex database using SQLite backup command
backup_plex_database() {
    log "Backing up Plex database (hot backup)..."
    
    local plex_db="$PLEX_DB_DIR/com.plexapp.plugins.library.db"
    local backup_db="/tmp/plex_db_backup_${BACKUP_DATE}.db"
    
    if [ ! -f "$plex_db" ]; then
        log_error "Plex database not found at: $plex_db"
        return 1
    fi
    
    # Use SQLite's backup command for safe hot backup
    # This handles WAL (Write-Ahead Logging) properly
    if command -v sqlite3 &> /dev/null; then
        log "Using SQLite backup command for safe hot backup..."
        sqlite3 "$plex_db" ".backup '$backup_db'" 2>&1 | tee -a "$LOG_FILE"
        
        if [ $? -eq 0 ] && [ -f "$backup_db" ]; then
            log "✓ Plex database hot backup successful"
            # Move to final location (will be included in tar backup)
            mv "$backup_db" "$PLEX_DB_DIR/backup_$(date +%Y%m%d_%H%M%S).db"
        else
            log_error "SQLite backup command failed"
            return 1
        fi
    else
        log "⚠ SQLite3 not found, using rsync fallback (less safe but acceptable)..."
        # Fallback: use rsync with special flags for database files
        rsync -ah --no-whole-file --inplace "$plex_db"* "/tmp/" 2>&1 | tee -a "$LOG_FILE"
    fi
}

# Backup local services with hot backup strategy
backup_local_services() {
    log "Starting hot backup of local services..."
    
    local backup_failed=0
    
    # Backup Plex (special handling for database)
    log "Backing up Plex..."
    if backup_plex_database; then
        tar -czf "$BACKUP_DIR/plex_${BACKUP_DATE}.tar.gz" \
            --exclude='*/Cache/*' \
            --exclude='*/Crash Reports/*' \
            --exclude='*/Logs/*' \
            -C "$(dirname "$PLEX_DIR")" "$(basename "$PLEX_DIR")" 2>&1 | tee -a "$LOG_FILE"
        verify_backup "$BACKUP_DIR/plex_${BACKUP_DATE}.tar.gz" "Plex" 10000 || backup_failed=1
    else
        backup_failed=1
    fi
    
    # Backup Sonarr (hot backup - safe for running containers)
    log "Backing up Sonarr..."
    tar -czf "$BACKUP_DIR/sonarr_${BACKUP_DATE}.tar.gz" \
        --exclude='*/logs/*' \
        --exclude='*/MediaCover/*' \
        -C "$(dirname "$SONARR_DIR")" "$(basename "$SONARR_DIR")" 2>&1 | tee -a "$LOG_FILE"
    verify_backup "$BACKUP_DIR/sonarr_${BACKUP_DATE}.tar.gz" "Sonarr" 500 || backup_failed=1
    
    # Backup Radarr (hot backup - safe for running containers)
    log "Backing up Radarr..."
    tar -czf "$BACKUP_DIR/radarr_${BACKUP_DATE}.tar.gz" \
        --exclude='*/logs/*' \
        --exclude='*/MediaCover/*' \
        -C "$(dirname "$RADARR_DIR")" "$(basename "$RADARR_DIR")" 2>&1 | tee -a "$LOG_FILE"
    verify_backup "$BACKUP_DIR/radarr_${BACKUP_DATE}.tar.gz" "Radarr" 500 || backup_failed=1
    
    # Backup Overseerr (hot backup - safe for running containers)
    log "Backing up Overseerr..."
    tar -czf "$BACKUP_DIR/overseerr_${BACKUP_DATE}.tar.gz" \
        --exclude='*/logs/*' \
        -C "$(dirname "$OVERSEERR_DIR")" "$(basename "$OVERSEERR_DIR")" 2>&1 | tee -a "$LOG_FILE"
    verify_backup "$BACKUP_DIR/overseerr_${BACKUP_DATE}.tar.gz" "Overseerr" 100 || backup_failed=1
    
    # Backup Tautulli (hot backup - safe for running containers)
    log "Backing up Tautulli..."
    tar -czf "$BACKUP_DIR/tautulli_${BACKUP_DATE}.tar.gz" \
        --exclude='*/logs/*' \
        -C "$(dirname "$TAUTULLI_DIR")" "$(basename "$TAUTULLI_DIR")" 2>&1 | tee -a "$LOG_FILE"
    verify_backup "$BACKUP_DIR/tautulli_${BACKUP_DATE}.tar.gz" "Tautulli" 500 || backup_failed=1
    
    # Backup Heimdall (hot backup - safe for running containers)
    log "Backing up Heimdall..."
    tar -czf "$BACKUP_DIR/heimdall_${BACKUP_DATE}.tar.gz" \
        --exclude='*/logs/*' \
        -C "$(dirname "$HEIMDALL_DIR")" "$(basename "$HEIMDALL_DIR")" 2>&1 | tee -a "$LOG_FILE"
    verify_backup "$BACKUP_DIR/heimdall_${BACKUP_DATE}.tar.gz" "Heimdall" 100 || backup_failed=1
    
    # Backup Scrypted (hot backup - safe for running containers)
    log "Backing up Scrypted..."
    tar -czf "$BACKUP_DIR/scrypted_${BACKUP_DATE}.tar.gz" \
        --exclude='*/logs/*' \
        -C "$(dirname "$SCRYPTED_DIR")" "$(basename "$SCRYPTED_DIR")" 2>&1 | tee -a "$LOG_FILE"
    verify_backup "$BACKUP_DIR/scrypted_${BACKUP_DATE}.tar.gz" "Scrypted" 100 || backup_failed=1
    
    # Backup Uptime Kuma (hot backup - safe for running containers)
    log "Backing up Uptime Kuma..."
    tar -czf "$BACKUP_DIR/uptime-kuma_${BACKUP_DATE}.tar.gz" \
        --exclude='*/logs/*' \
        -C "$(dirname "$UPTIME_KUMA_DIR")" "$(basename "$UPTIME_KUMA_DIR")" 2>&1 | tee -a "$LOG_FILE"
    verify_backup "$BACKUP_DIR/uptime-kuma_${BACKUP_DATE}.tar.gz" "Uptime-Kuma" 500 || backup_failed=1
    
    # Backup Frigate (hot backup - safe for running containers)
    log "Backing up Frigate..."
    tar -czf "$BACKUP_DIR/frigate_${BACKUP_DATE}.tar.gz" \
        --exclude='*/logs/*' \
        --exclude='*/clips/*' \
        --exclude='*/recordings/*' \
        --exclude='*/cache/*' \
        -C "$(dirname "$FRIGATE_DIR")" "$(basename "$FRIGATE_DIR")" 2>&1 | tee -a "$LOG_FILE"
    verify_backup "$BACKUP_DIR/frigate_${BACKUP_DATE}.tar.gz" "Frigate" 100 || backup_failed=1
    
    return $backup_failed
}

# Backup remote Sabnzbd via SSH (hot backup)
backup_remote_sabnzbd() {
    log "Backing up remote Sabnzbd (${REMOTE_SAB_HOST})..."
    
    # Use SSH + tar for hot backup of remote service
    ssh "$REMOTE_USER@$REMOTE_SAB_HOST" \
        "tar -czf - --exclude='*/logs/*' --exclude='*/cache/*' '$REMOTE_SAB_DIR'" \
        > "$BACKUP_DIR/sabnzbd_${BACKUP_DATE}.tar.gz" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        verify_backup "$BACKUP_DIR/sabnzbd_${BACKUP_DATE}.tar.gz" "Sabnzbd" 500
        return $?
    else
        log_error "Remote Sabnzbd backup failed"
        return 1
    fi
}

# Backup remote Nginx Proxy Manager via SSH (hot backup)
backup_remote_npm() {
    log "Backing up remote Nginx Proxy Manager (${REMOTE_NPM_HOST})..."
    
    # Use SSH + tar for hot backup of remote service
    ssh "$REMOTE_USER@$REMOTE_NPM_HOST" \
        "tar -czf - --exclude='*/logs/*' --exclude='*/letsencrypt/archive/*' '$REMOTE_NPM_DIR'" \
        > "$BACKUP_DIR/nginx-proxy-manager_${BACKUP_DATE}.tar.gz" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        verify_backup "$BACKUP_DIR/nginx-proxy-manager_${BACKUP_DATE}.tar.gz" "Nginx-Proxy-Manager" 1000
        return $?
    else
        log_error "Remote Nginx Proxy Manager backup failed"
        return 1
    fi
}

# Implement retention policy (keep last 5 backups from 2 weeks)
cleanup_old_backups() {
    log "Applying retention policy (keeping last $RETENTION_COUNT backups from 2 weeks)..."
    
    local services=("plex" "sonarr" "radarr" "overseerr" "tautulli" "heimdall" "scrypted" "uptime-kuma" "frigate" "sabnzbd" "nginx-proxy-manager")
    
    for service in "${services[@]}"; do
        log "Cleaning up old $service backups..."
        
        # Find and delete old backups, keeping only the most recent ones
        ls -1t "$BACKUP_DIR/${service}_"*.tar.gz 2>/dev/null | tail -n +$((RETENTION_COUNT + 1)) | while read -r old_backup; do
            log "Deleting old backup: $(basename "$old_backup")"
            rm -f "$old_backup"
        done
    done
    
    log "✓ Retention policy applied"
}

# Calculate total backup size
calculate_backup_size() {
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    echo "$total_size"
}

################################################################################
# Main Execution
################################################################################

main() {
    local start_time=$(date +%s)
    local exit_code=0
    
    log "======================================================================="
    log "Starting Media Stack Hot Backup - $BACKUP_DATE"
    log "======================================================================="
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check if services are running (informational - we DON'T stop them)
    log "Checking service status (containers will remain running)..."
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "plex|sonarr|radarr|overseerr|tautulli|heimdall|scrypted|uptime-kuma|frigate" | tee -a "$LOG_FILE" || true
    
    # Perform hot backups
    if ! backup_local_services; then
        log_error "Local services backup had failures"
        exit_code=1
    fi
    
    if ! backup_remote_sabnzbd; then
        log_error "Remote Sabnzbd backup failed"
        exit_code=1
    fi
    
    if ! backup_remote_npm; then
        log_error "Remote Nginx Proxy Manager backup failed"
        exit_code=1
    fi
    
    # Apply retention policy
    cleanup_old_backups
    
    # Calculate and log statistics
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local backup_size=$(calculate_backup_size)
    
    log "======================================================================="
    log "Backup Summary"
    log "======================================================================="
    log "Date: $BACKUP_DATE"
    log "Duration: ${duration} seconds"
    log "Total backup size: $backup_size"
    log "Backup location: $BACKUP_DIR"
    log "Exit code: $exit_code"
    
    if [ $exit_code -eq 0 ]; then
        log "✓ All backups completed successfully!"
    else
        log_error "⚠ Backup completed with errors (exit code: $exit_code)"
    fi
    
    log "======================================================================="
    
    exit $exit_code
}

# Run main function
main
