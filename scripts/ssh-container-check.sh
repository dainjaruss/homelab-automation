#!/bin/bash
set -euo pipefail

# Containers to check (local)
containers=(plex sonarr radarr overseerr tautulli heimdall uptime-kuma)

bad=0
msg=""
all_status=""

# Local checks
for c in "${containers[@]}"; do
  if ! docker inspect -f '{{.State.Status}}' "$c" >/dev/null 2>&1; then
    bad=1
    msg+="$c:missing "
    all_status+="$c:missing "
    continue
  fi

  st="$(docker inspect -f '{{.State.Status}}' "$c")"
  all_status+="$c:$st "
  
  if [[ "$st" != "running" ]]; then
    bad=1
    msg+="$c:$st "
  fi

  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c")"
  if [[ "$health" != "none" && "$health" != "healthy" ]]; then
    bad=1
    msg+="$c:health=$health "
    all_status+=" (health:$health)"
  fi
done

# Remote checks (update users if needed)
# sabnzbd on 192.168.4.99
remote_user="dainja"  # Update to correct user for this host
remote_host="192.168.4.99"
remote_container="sabnzbd"
if ! ssh "$remote_user@$remote_host" "docker inspect -f '{{.State.Status}}' '$remote_container'" >/dev/null 2>&1; then
  bad=1
  msg+="$remote_container@$remote_host:missing "
  all_status+="$remote_container@$remote_host:missing "
else
  st="$(ssh "$remote_user@$remote_host" "docker inspect -f '{{.State.Status}}' '$remote_container'")"
  all_status+="$remote_container@$remote_host:$st "
  if [[ "$st" != "running" ]]; then
    bad=1
    msg+="$remote_container@$remote_host:$st "
  fi
  health="$(ssh "$remote_user@$remote_host" "docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' '$remote_container'")"
  if [[ "$health" != "none" && "$health" != "healthy" ]]; then
    bad=1
    msg+="$remote_container@$remote_host:health=$health "
    all_status+=" (health:$health)"
  fi
fi

# nginx-proxy-manager on 192.168.1.236
remote_user="dainja"  # Update to correct user for this host
remote_host="192.168.1.236"
remote_container="nginx-proxy-manager"
if ! ssh "$remote_user@$remote_host" "docker inspect -f '{{.State.Status}}' '$remote_container'" >/dev/null 2>&1; then
  bad=1
  msg+="$remote_container@$remote_host:missing "
  all_status+="$remote_container@$remote_host:missing "
else
  st="$(ssh "$remote_user@$remote_host" "docker inspect -f '{{.State.Status}}' '$remote_container'")"
  all_status+="$remote_container@$remote_host:$st "
  if [[ "$st" != "running" ]]; then
    bad=1
    msg+="$remote_container@$remote_host:$st "
  fi
  health="$(ssh "$remote_user@$remote_host" "docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' '$remote_container'")"
  if [[ "$health" != "none" && "$health" != "healthy" ]]; then
    bad=1
    msg+="$remote_container@$remote_host:health=$health "
    all_status+=" (health:$health)"
  fi
fi

# Trim trailing spaces
all_status="${all_status% }"
msg="${msg% }"

if [[ "$bad" -eq 0 ]]; then
  echo "STATUS:OK"
  echo "MESSAGE:All containers running"
  echo "DETAILS:$all_status"
else
  echo "STATUS:FAIL"
  echo "MESSAGE:$msg"
  echo "DETAILS:$all_status"
fi