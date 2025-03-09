#!/bin/bash

# Exit on errors
set -e

# Ensure script runs as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Define paths and constants
LOG_FILE="/var/log/interface-protection.log"
LOCK_FILE="/tmp/restore_lock"
BACKUP_DIR="/etc/BacServices/interface-protection"
NETWORK_SCRIPTS_DIR="/etc/sysconfig/network-scripts"
DEBOUNCE_TIME=5  # Seconds to debounce events
RESTORE_TIMEOUT=15  # Seconds to ignore events post-restore

# Create necessary directories and files
mkdir -p "$BACKUP_DIR/network-scripts"
touch "$LOG_FILE"

# Log function with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$1"
}

# Install inotify-tools if missing
if ! command -v inotifywait >/dev/null; then
    log_message "Installing inotify-tools..."
    yum install -y inotify-tools || {
        log_message "Failed to install inotify-tools"
        exit 1
    }
    log_message "inotify-tools installed successfully"
fi

# Backup network-scripts
backup_config() {
    log_message "Creating backup for network-scripts"
    if [ -d "$NETWORK_SCRIPTS_DIR" ]; then
        cp -r "$NETWORK_SCRIPTS_DIR"/* "$BACKUP_DIR/network-scripts/" || {
            log_message "Backup failed"
            exit 1
        }
    else
        log_message "Directory $NETWORK_SCRIPTS_DIR does not exist, skipping backup"
    fi
}

# Restore configuration atomically
restore_config() {
    if [ ! -d "$NETWORK_SCRIPTS_DIR" ]; then
        log_message "Target directory $NETWORK_SCRIPTS_DIR does not exist, cannot restore"
        return 1
    fi
    log_message "Restoring configuration for network-scripts"
    touch "$LOCK_FILE"
    echo "$(date +%s)" > "$LOCK_FILE"
    
    # Atomic restore: move existing dir aside, sync backup, clean up
    TEMP_DIR="/tmp/network_scripts_temp"
    mv "$NETWORK_SCRIPTS_DIR" "$TEMP_DIR"
    cp -r "$BACKUP_DIR/network-scripts"/* "$NETWORK_SCRIPTS_DIR/" || {
        log_message "Restore failed, reverting"
        mv "$TEMP_DIR" "$NETWORK_SCRIPTS_DIR"
        rm -f "$LOCK_FILE"
        return 1
    }
    rm -rf "$TEMP_DIR"
    
    log_message "Configuration restored, restarting network"
    systemctl restart network || log_message "Network restart failed"
    rm -f "$LOCK_FILE"
}

# Monitor changes
monitor_config() {
    log_message "Monitoring network-scripts"
    while true; do
        # Wait for events with debounce
        while inotifywait -r -e modify,create,delete --timeout "$DEBOUNCE_TIME" "$NETWORK_SCRIPTS_DIR" >/dev/null; do
            log_message "Event detected, debouncing"
        done
        
        # Check if recent restore occurred
        if [ -f "$LOCK_FILE" ]; then
            restore_time=$(cat "$LOCK_FILE")
            current_time=$(date +%s)
            if [ $((current_time - restore_time)) -lt "$RESTORE_TIMEOUT" ]; then
                log_message "Ignoring event due to recent restore"
                continue
            fi
        fi
        
        # Compare with backup
        if [ -d "$NETWORK_SCRIPTS_DIR" ] && [ -d "$BACKUP_DIR/network-scripts" ]; then
            if ! diff -r "$BACKUP_DIR/network-scripts" "$NETWORK_SCRIPTS_DIR" >/dev/null 2>&1; then
                log_message "Differences detected in network-scripts:"
                diff -r "$BACKUP_DIR/network-scripts" "$NETWORK_SCRIPTS_DIR" >> "$LOG_FILE" 2>> "$LOG_FILE" || echo " (diff output unavailable)" >> "$LOG_FILE"
                restore_config
            else
                log_message "No significant changes after debounce"
            fi
        else
            log_message "Cannot compare: directories missing"
        fi
    done
}

# Main execution
log_message "Starting script"
backup_config
monitor_config &

# Keep script running
wait
