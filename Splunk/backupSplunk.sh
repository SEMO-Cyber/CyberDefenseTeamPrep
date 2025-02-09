#!/bin/bash
#  Quick script to take a backup of Splunk in its entirety
#
#  Samuel Brucker 2024-2025

BACKUP_DIR="/etc/BacService/"
SPLUNK_HOME="/opt/splunk"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup Splunk configurations with timestamp
echo "Backing up latest Splunk configuration."

BACKUP_PATH="$BACKUP_DIR/splunk_${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"

cp -R "$SPLUNK_HOME" "$BACKUP_PATH"

echo "Verifying backup integrity..."
find "$BACKUP_PATH" -type f -size +0 -print0 | xargs -0 md5sum > "$BACKUP_PATH/md5sums.txt"
find "$BACKUP_PATH" -type f -size 0 -delete
