#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/mnt/server/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/docker-update-$(date +%F).log"

# Local compose project directories
LOCAL_COMPOSE_DIRS=(
  "/mnt/server/tools/uptime_kuma"  # uptime kuma compose dir
  "/mnt/server/plex"              # plex/sonarr/radarr/overseerr/tautulli compose dir
  #"/mnt/server"                   # any other compose project dir that has a compose file
)

# Remote Sabnzbd compose project
REMOTE_HOST="192.168.4.99"
REMOTE_USER="dainja"
REMOTE_SAB_DIR="/home/dainja/sabnzbd"

echo "=== $(date -Is) Starting docker compose update (pull + up -d) ===" | tee -a "$LOG_FILE"

update_local_dir () {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    echo "WARN: $dir does not exist, skipping" | tee -a "$LOG_FILE"
    return 0
  fi

  local file=""
  if [[ -f "$dir/docker-compose.yml" ]]; then
    file="$dir/docker-compose.yml"
  elif [[ -f "$dir/docker-compose.yaml" ]]; then
    file="$dir/docker-compose.yaml"
  elif [[ -f "$dir/compose.yml" ]]; then
    file="$dir/compose.yml"
  else
    echo "WARN: No compose file found in $dir, skipping" | tee -a "$LOG_FILE"
    return 0
  fi

  echo "--- $(date -Is) Local pull + restart in $dir ($file) ---" | tee -a "$LOG_FILE"

  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$file" pull | tee -a "$LOG_FILE"
    docker compose -f "$file" up -d --remove-orphans | tee -a "$LOG_FILE"
  else
    docker-compose -f "$file" pull | tee -a "$LOG_FILE"
    docker-compose -f "$file" up -d --remove-orphans | tee -a "$LOG_FILE"
  fi
}

update_remote_dir () {
  local host="$1"
  local user="$2"
  local dir="$3"

  echo "--- $(date -Is) Remote pull + restart on $user@$host:$dir ---" | tee -a "$LOG_FILE"

  ssh -o BatchMode=yes -o ConnectTimeout=10 "${user}@${host}" "
    set -e
    cd '${dir}'
    if docker compose version >/dev/null 2>&1; then
      docker compose pull
      docker compose up -d --remove-orphans
    else
      docker-compose pull
      docker-compose up -d --remove-orphans
    fi
  " | tee -a "$LOG_FILE"
}

# Update local projects
for dir in "${LOCAL_COMPOSE_DIRS[@]}"; do
  update_local_dir "$dir"
done

# Update remote sabnzbd project
update_remote_dir "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_SAB_DIR"

echo "=== $(date -Is) Done docker compose update ===" | tee -a "$LOG_FILE"

# Optional: keep only 30 days of logs
find "$LOG_DIR" -name 'docker-update-*.log' -mtime +30 -delete || true
