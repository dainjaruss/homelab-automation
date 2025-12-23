#!/usr/bin/env bash
set -euo pipefail

# (Optional hardening for cron)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

PUSH_BASE="http://192.168.1.142:3001/api/push/hM6oDQYkfH"

# containers expected on main host
containers=(plex sonarr radarr overseerr tautulli)

bad=0
msg=""

for c in "${containers[@]}"; do
  if ! docker inspect -f '{{.State.Status}}' "$c" >/dev/null 2>&1; then
    bad=1; msg+="$c:missing "
    continue
  fi

  st="$(docker inspect -f '{{.State.Status}}' "$c")"
  if [[ "$st" != "running" ]]; then
    bad=1; msg+="$c:$st "
  fi

  # If container has a healthcheck, also enforce it
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c")"
  if [[ "$health" != "none" && "$health" != "healthy" ]]; then
    bad=1; msg+="$c:health=$health "
  fi
done

if [[ "$bad" -eq 0 ]]; then
  curl -fsS -m 10 --retry 3 -G \
    --data-urlencode "status=up" \
    --data-urlencode "msg=Containers OK" \
    "$PUSH_BASE" >/dev/null
else
  fail_msg="Containers BAD: ${msg}"
  curl -fsS -m 10 --retry 3 -G \
    --data-urlencode "status=down" \
    --data-urlencode "msg=$fail_msg" \
    "$PUSH_BASE" >/dev/null || true
fi
