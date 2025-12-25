#!/usr/bin/env bash
#
# docker_update_improved.sh
# Phase 3: Docker Image Update Automation with Health Checks and Rollback
#
# Updates all local and remote containers with:
# - Pre-update health checks
# - Image pulling and container recreation
# - Post-update health checks
# - Automatic rollback on failure
# - Detailed logging and summary reporting
#
# Local containers (9): plex, sonarr, radarr, overseerr, tautulli, heimdall, scrypted, uptime-kuma, frigate
# Remote containers (2): sabnzbd @ 192.168.4.99, nginx-proxy-manager @ 192.168.1.236

set -euo pipefail

# Hardening for cron environments
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ============================================================================
# Configuration
# ============================================================================

LOG_DIR="/mnt/server/logs"
LOG_FILE="${LOG_DIR}/docker_update_improved.log"
START_TIME=$(date +%s)

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Local Docker Compose project directories with their service names
declare -A LOCAL_PROJECTS
LOCAL_PROJECTS["/mnt/server/plex"]="plex,sonarr,radarr,overseerr,tautulli"
LOCAL_PROJECTS["/mnt/server/tools/heimdall"]="heimdall"
LOCAL_PROJECTS["/mnt/server/tools/uptime_kuma"]="uptime-kuma"
LOCAL_PROJECTS["/mnt/server/scrypted"]="scrypted"
LOCAL_PROJECTS["/mnt/server/frigate"]="frigate"

# Remote SSH configurations
declare -A REMOTE_PROJECTS
REMOTE_PROJECTS["dainja@192.168.4.99:/home/dainja/sabnzbd"]="sabnzbd"
REMOTE_PROJECTS["dainja@192.168.1.236:/opt/npm"]="nginx-proxy-manager"

# Tracking arrays
declare -a UPDATED_SERVICES=()
declare -a FAILED_SERVICES=()
declare -a WARNINGS=()

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log_header() {
    log "============================================================================"
    log "$*"
    log "============================================================================"
}

log_section() {
    log "----------------------------------------------------------------------------"
    log "$*"
    log "----------------------------------------------------------------------------"
}

# ============================================================================
# Health Check Functions
# ============================================================================

# Check if a single container is healthy
# Args: container_name
# Returns: 0 if healthy, 1 if unhealthy
check_container_health() {
    local container="$1"
    
    # Check if container exists
    if ! docker inspect -f '{{.State.Status}}' "$container" >/dev/null 2>&1; then
        log "  ⚠️  Container '$container' not found"
        return 1
    fi
    
    # Check if container is running
    local status
    status=$(docker inspect -f '{{.State.Status}}' "$container")
    if [[ "$status" != "running" ]]; then
        log "  ❌ Container '$container' status: $status (expected: running)"
        return 1
    fi
    
    # Check health status if healthcheck is defined
    local health
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container")
    if [[ "$health" != "none" && "$health" != "healthy" ]]; then
        log "  ❌ Container '$container' health: $health (expected: healthy)"
        return 1
    fi
    
    log "  ✅ Container '$container' is healthy (status: $status, health: $health)"
    return 0
}

# Check health of all services in a comma-separated list
# Args: service_names (comma-separated)
# Returns: 0 if all healthy, 1 if any unhealthy
check_services_health() {
    local services="$1"
    local all_healthy=0
    
    IFS=',' read -ra SERVICE_ARRAY <<< "$services"
    for service in "${SERVICE_ARRAY[@]}"; do
        if ! check_container_health "$service"; then
            all_healthy=1
        fi
    done
    
    return $all_healthy
}

# Check health of remote container via SSH
# Args: ssh_target, container_name
# Returns: 0 if healthy, 1 if unhealthy
check_remote_container_health() {
    local ssh_target="$1"
    local container="$2"
    
    local status health
    
    # Check if container exists and get status
    if ! status=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_target" \
        "docker inspect -f '{{.State.Status}}' '$container' 2>/dev/null"); then
        log "  ⚠️  Remote container '$container' not found on $ssh_target"
        return 1
    fi
    
    if [[ "$status" != "running" ]]; then
        log "  ❌ Remote container '$container' status: $status (expected: running)"
        return 1
    fi
    
    # Check health status
    health=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_target" \
        "docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' '$container'")
    
    if [[ "$health" != "none" && "$health" != "healthy" ]]; then
        log "  ❌ Remote container '$container' health: $health (expected: healthy)"
        return 1
    fi
    
    log "  ✅ Remote container '$container' is healthy (status: $status, health: $health)"
    return 0
}

# ============================================================================
# Docker Compose Detection
# ============================================================================

# Find docker-compose file in directory
# Args: directory_path
# Returns: path to compose file, or empty string if not found
find_compose_file() {
    local dir="$1"
    
    if [[ -f "$dir/docker-compose.yml" ]]; then
        echo "$dir/docker-compose.yml"
    elif [[ -f "$dir/docker-compose.yaml" ]]; then
        echo "$dir/docker-compose.yaml"
    elif [[ -f "$dir/compose.yml" ]]; then
        echo "$dir/compose.yml"
    elif [[ -f "$dir/compose.yaml" ]]; then
        echo "$dir/compose.yaml"
    else
        echo ""
    fi
}

# Get docker compose command (handles both 'docker compose' and 'docker-compose')
get_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# ============================================================================
# Update Functions - Local
# ============================================================================

# Update a local Docker Compose project
# Args: project_directory, service_names
# Returns: 0 on success, 1 on failure
update_local_project() {
    local project_dir="$1"
    local services="$2"
    local compose_cmd
    
    log_section "Updating Local Project: $project_dir"
    log "Services: $services"
    
    # Validate directory exists
    if [[ ! -d "$project_dir" ]]; then
        log "❌ ERROR: Directory '$project_dir' does not exist"
        FAILED_SERVICES+=("$services (directory not found)")
        return 1
    fi
    
    # Find compose file
    local compose_file
    compose_file=$(find_compose_file "$project_dir")
    if [[ -z "$compose_file" ]]; then
        log "❌ ERROR: No docker-compose file found in '$project_dir'"
        FAILED_SERVICES+=("$services (no compose file)")
        return 1
    fi
    
    log "Using compose file: $compose_file"
    compose_cmd=$(get_compose_cmd)
    log "Using command: $compose_cmd"
    
    # Pre-update health check
    log ""
    log "Step 1/4: Pre-update health check"
    if ! check_services_health "$services"; then
        WARNINGS+=("$services had unhealthy containers before update")
        log "⚠️  WARNING: Some containers were unhealthy before update"
    fi
    
    # Pull latest images
    log ""
    log "Step 2/4: Pulling latest images"
    if ! $compose_cmd -f "$compose_file" pull 2>&1 | tee -a "$LOG_FILE"; then
        log "❌ ERROR: Failed to pull images for '$services'"
        FAILED_SERVICES+=("$services (pull failed)")
        return 1
    fi
    
    # Recreate containers with new images
    log ""
    log "Step 3/4: Recreating containers"
    if ! $compose_cmd -f "$compose_file" up -d --remove-orphans 2>&1 | tee -a "$LOG_FILE"; then
        log "❌ ERROR: Failed to recreate containers for '$services'"
        FAILED_SERVICES+=("$services (up failed)")
        
        # Attempt restart as rollback
        log "🔄 Attempting rollback via restart..."
        $compose_cmd -f "$compose_file" restart 2>&1 | tee -a "$LOG_FILE" || true
        return 1
    fi
    
    # Wait a few seconds for containers to start
    log "Waiting 10 seconds for containers to stabilize..."
    sleep 10
    
    # Post-update health check
    log ""
    log "Step 4/4: Post-update health check"
    if ! check_services_health "$services"; then
        log "❌ ERROR: Post-update health check failed for '$services'"
        FAILED_SERVICES+=("$services (post-update unhealthy)")
        
        # Attempt restart as rollback
        log "🔄 Attempting rollback via restart..."
        if $compose_cmd -f "$compose_file" restart 2>&1 | tee -a "$LOG_FILE"; then
            log "Waiting 10 seconds after restart..."
            sleep 10
            
            if check_services_health "$services"; then
                log "✅ Rollback successful - containers recovered"
                UPDATED_SERVICES+=("$services (with rollback)")
                return 0
            else
                log "❌ Rollback failed - manual intervention required"
                return 1
            fi
        else
            log "❌ Rollback restart failed - manual intervention required"
            return 1
        fi
    fi
    
    # Success
    log "✅ Successfully updated: $services"
    UPDATED_SERVICES+=("$services")
    return 0
}

# ============================================================================
# Update Functions - Remote
# ============================================================================

# Update a remote Docker Compose project via SSH
# Args: ssh_target, project_directory, service_names
# Returns: 0 on success, 1 on failure
update_remote_project() {
    local ssh_target="$1"
    local project_dir="$2"
    local services="$3"
    
    log_section "Updating Remote Project: $ssh_target:$project_dir"
    log "Services: $services"
    
    # Extract container name (first service in comma-separated list)
    local container_name
    container_name=$(echo "$services" | cut -d',' -f1)
    
    # Pre-update health check
    log ""
    log "Step 1/4: Pre-update health check"
    if ! check_remote_container_health "$ssh_target" "$container_name"; then
        WARNINGS+=("$services on $ssh_target had unhealthy container before update")
        log "⚠️  WARNING: Container was unhealthy before update"
    fi
    
    # Pull and update via SSH
    log ""
    log "Step 2/4: Pulling latest images (remote)"
    log "Step 3/4: Recreating containers (remote)"
    
    if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_target" "
        set -e
        cd '$project_dir'
        
        # Determine compose command
        if docker compose version >/dev/null 2>&1; then
            compose_cmd='docker compose'
        else
            compose_cmd='docker-compose'
        fi
        
        echo \"Using command: \$compose_cmd\"
        
        # Pull and recreate
        \$compose_cmd pull
        \$compose_cmd up -d --remove-orphans
    " 2>&1 | tee -a "$LOG_FILE"; then
        log "❌ ERROR: Failed to update remote project '$services' on $ssh_target"
        FAILED_SERVICES+=("$services @ $ssh_target")
        
        # Attempt restart as rollback
        log "🔄 Attempting rollback via restart..."
        ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_target" "
            cd '$project_dir'
            if docker compose version >/dev/null 2>&1; then
                docker compose restart
            else
                docker-compose restart
            fi
        " 2>&1 | tee -a "$LOG_FILE" || true
        return 1
    fi
    
    # Wait for container to start
    log "Waiting 10 seconds for container to stabilize..."
    sleep 10
    
    # Post-update health check
    log ""
    log "Step 4/4: Post-update health check"
    if ! check_remote_container_health "$ssh_target" "$container_name"; then
        log "❌ ERROR: Post-update health check failed for '$services' on $ssh_target"
        FAILED_SERVICES+=("$services @ $ssh_target (post-update unhealthy)")
        
        # Attempt restart as rollback
        log "🔄 Attempting rollback via restart..."
        if ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_target" "
            cd '$project_dir'
            if docker compose version >/dev/null 2>&1; then
                docker compose restart
            else
                docker-compose restart
            fi
        " 2>&1 | tee -a "$LOG_FILE"; then
            log "Waiting 10 seconds after restart..."
            sleep 10
            
            if check_remote_container_health "$ssh_target" "$container_name"; then
                log "✅ Rollback successful - container recovered"
                UPDATED_SERVICES+=("$services @ $ssh_target (with rollback)")
                return 0
            else
                log "❌ Rollback failed - manual intervention required"
                return 1
            fi
        else
            log "❌ Rollback restart failed - manual intervention required"
            return 1
        fi
    fi
    
    # Success
    log "✅ Successfully updated: $services @ $ssh_target"
    UPDATED_SERVICES+=("$services @ $ssh_target")
    return 0
}

# ============================================================================
# Cleanup Functions
# ============================================================================

cleanup_old_logs() {
    log_section "Cleaning up old logs"
    
    local deleted_count=0
    while IFS= read -r -d '' file; do
        log "Deleting old log: $file"
        rm -f "$file"
        ((deleted_count++))
    done < <(find "$LOG_DIR" -name 'docker_update_improved.log.*' -mtime +30 -print0 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        log "✅ Deleted $deleted_count old log file(s)"
    else
        log "No old logs to clean up"
    fi
}

# ============================================================================
# Summary and Exit
# ============================================================================

print_summary() {
    local end_time duration_seconds
    end_time=$(date +%s)
    duration_seconds=$((end_time - START_TIME))
    
    log_header "UPDATE SUMMARY"
    
    log "Total Duration: ${duration_seconds}s"
    log ""
    
    # Updated services
    if [[ ${#UPDATED_SERVICES[@]} -gt 0 ]]; then
        log "✅ Successfully Updated (${#UPDATED_SERVICES[@]}):"
        for service in "${UPDATED_SERVICES[@]}"; do
            log "   - $service"
        done
    else
        log "✅ Successfully Updated: None"
    fi
    log ""
    
    # Failed services
    if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
        log "❌ Failed Updates (${#FAILED_SERVICES[@]}):"
        for service in "${FAILED_SERVICES[@]}"; do
            log "   - $service"
        done
    else
        log "❌ Failed Updates: None"
    fi
    log ""
    
    # Warnings
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        log "⚠️  Warnings (${#WARNINGS[@]}):"
        for warning in "${WARNINGS[@]}"; do
            log "   - $warning"
        done
    else
        log "⚠️  Warnings: None"
    fi
    
    log_header "END OF UPDATE"
    
    # Output final status for parsing by n8n
    if [[ ${#FAILED_SERVICES[@]} -eq 0 ]]; then
        echo "STATUS=SUCCESS"
        echo "UPDATED=${#UPDATED_SERVICES[@]}"
        echo "FAILED=0"
        echo "DURATION=${duration_seconds}s"
        echo "WARNINGS=${#WARNINGS[@]}"
        return 0
    else
        echo "STATUS=FAILURE"
        echo "UPDATED=${#UPDATED_SERVICES[@]}"
        echo "FAILED=${#FAILED_SERVICES[@]}"
        echo "DURATION=${duration_seconds}s"
        echo "FAILED_SERVICES=${FAILED_SERVICES[*]}"
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_header "Docker Image Update - Phase 3"
    log "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    log "Log file: $LOG_FILE"
    
    # Rotate current log if it exists
    if [[ -f "$LOG_FILE" ]]; then
        local timestamp
        timestamp=$(date '+%Y%m%d_%H%M%S')
        mv "$LOG_FILE" "${LOG_FILE}.${timestamp}"
        log "Rotated previous log to: ${LOG_FILE}.${timestamp}"
    fi
    
    # Update local projects
    log_header "UPDATING LOCAL PROJECTS"
    for project_dir in "${!LOCAL_PROJECTS[@]}"; do
        update_local_project "$project_dir" "${LOCAL_PROJECTS[$project_dir]}" || true
        log ""
    done
    
    # Update remote projects
    log_header "UPDATING REMOTE PROJECTS"
    for remote_spec in "${!REMOTE_PROJECTS[@]}"; do
        # Parse SSH target and directory from key format: "user@host:/path"
        local ssh_target project_dir
        ssh_target="${remote_spec%%:*}"
        project_dir="${remote_spec#*:}"
        
        update_remote_project "$ssh_target" "$project_dir" "${REMOTE_PROJECTS[$remote_spec]}" || true
        log ""
    done
    
    # Cleanup old logs
    cleanup_old_logs
    log ""
    
    # Print summary and exit
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main
