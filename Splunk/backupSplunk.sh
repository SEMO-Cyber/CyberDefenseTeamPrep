#!/bin/bash
#  Quick script to take a backup of Splunk in its entirety
#
#  Samuel Brucker 2024-2025

BACKUP_DIR="/etc/BacService/"
SPLUNK_HOME="/opt/splunk"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup Splunk configurations with timestamp
echo "Backing up latest Splunk configuration."

#Set and make the Splunk backup directory
BACKUP_PATH="$BACKUP_DIR/splunk_${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"

#copy the splunk config to the backup location
cp -R "$SPLUNK_HOME" "$BACKUP_PATH"
