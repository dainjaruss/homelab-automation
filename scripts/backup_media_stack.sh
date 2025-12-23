#!/bin/bash
# Backup script for media stack configs
# Sabnzbd on 192.168.4.99, others on localhost (192.168.1.142)
# Backups to /mnt/server/backup/media-stack/

set -e

BACKUP_DIR="/mnt/server/backup/media-stack"
REMOTE_HOST="192.168.4.99"
REMOTE_USER="dainja"
MAIN_COMPOSE_DIR="/mnt/server/plex"  # Update this path
SAB_COMPOSE_DIR="/home/dainja/sabnzbd"   # Update this path on remote if needed

mkdir -p "$BACKUP_DIR"

echo "Stopping containers..."

# Stop local containers
cd "$MAIN_COMPOSE_DIR"
docker compose down

# Stop remote Sabnzbd (assumes docker-compose is in ~/ or adjust path)
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $SAB_COMPOSE_DIR && docker compose down"

echo "Backing up configs..."

# Local backups
tar -cvpzf "$BACKUP_DIR/plex_backup.tar.gz" /mnt/server/plex/
tar -cvpzf "$BACKUP_DIR/sonarr_backup.tar.gz" /mnt/server/sonarr/
tar -cvpzf "$BACKUP_DIR/radarr_backup.tar.gz" /mnt/server/radarr/
tar -cvpzf "$BACKUP_DIR/overseerr_backup.tar.gz" /mnt/server/overseerr/
tar -cvpzf "$BACKUP_DIR/tautulli_backup.tar.gz" /mnt/server/tautulli/

# Remote Sabnzbd backup (tar over SSH)
ssh "$REMOTE_USER@$REMOTE_HOST" "tar -cvpzf - /home/dainja/sabnzbd/" > "$BACKUP_DIR/sabnzbd_backup.tar.gz"

echo "Restarting containers..."

# Restart local
cd "$MAIN_COMPOSE_DIR"
docker compose up -d

# Restart remote
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $SAB_COMPOSE_DIR && docker compose up -d"

echo "Backup complete. Files in $BACKUP_DIR"
