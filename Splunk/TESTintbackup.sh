#!/bin/bash

# Exit on errors
set -e

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Backup directory and log file
BACKUP_DIR="/etc/BacServices/nmcli-protection"
LOG_FILE="/var/log/nmcli-protection.log"

# Create directories if they don't exist
mkdir -p "$BACKUP_DIR"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Set environment variables for D-Bus (needed for nmcli in cron)
if [ -z "$DBUS_SYSTEM_BUS_ADDRESS" ]; then
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/var/run/dbus/system_bus_socket
fi

# **Backup configuration**
backup_config() {
    # Backup the full .nmconnection files for restoration
    cp /etc/NetworkManager/system-connections/*.nmconnection "$BACKUP_DIR/" 2>> "$LOG_FILE" || {
        log_message "Failed to backup NetworkManager connection files"
        return 1
    }
    
    # Backup specific stable fields for change detection
    for conn in $(nmcli -t -f NAME con show); do
        local backup_file="$BACKUP_DIR/$conn.fields.backup"
        nmcli -f connection.id,connection.type,connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns con show "$conn" > "$backup_file" 2>> "$LOG_FILE" || {
            log_message "Failed to backup fields for $conn"
            continue
        }
        chmod 600 "$backup_file" 2>> "$LOG_FILE" || log_message "Failed to set permissions on $backup_file"
    done
    log_message "Backup created for NetworkManager connections"
}

# **Check for changes and log them**
check_changes() {
    local changes_detected=0
    local active_connections=$(nmcli -t -f NAME con show)
    
    # Check for deleted connections
    for backup_file in "$BACKUP_DIR"/*.fields.backup; do
        local conn=$(basename "$backup_file" .fields.backup)
        if ! echo "$active_connections" | grep -q "^$conn$"; then
            log_message "Connection $conn has been deleted"
            changes_detected=1
        fi
    done
    
    # Check for modified connections
    for conn in $active_connections; do
        local backup_fields="$BACKUP_DIR/$conn.fields.backup"
        local temp_fields="/tmp/$conn.fields.current"
        
        if [ ! -f "$backup_fields" ]; then
            log_message "No backup found for connection $conn"
            changes_detected=1
            continue
        fi
        
        nmcli -f connection.id,connection.type,connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns con show "$conn" > "$temp_fields" 2>> "$LOG_FILE"
        if [ $? -ne 0 ]; then
            log_message "Failed to get current fields for $conn (connection may not exist)"
            rm -f "$temp_fields"
            changes_detected=1
            continue
        fi
        
        if ! cmp -s "$temp_fields" "$backup_fields"; then
            log_message "Changes detected in connection $conn. Differences:"
            diff -u "$backup_fields" "$temp_fields" >> "$LOG_FILE" 2>&1
            changes_detected=1
        fi
        
        rm -f "$temp_fields"
    done
    
    # Check for new connections
    for current_file in /etc/NetworkManager/system-connections/*.nmconnection; do
        [ -f "$current_file" ] || continue
        local connection_name=$(basename "$current_file" .nmconnection)
        if [ ! -f "$BACKUP_DIR/$connection_name.nmconnection" ]; then
            log_message "New connection detected: $connection_name"
            changes_detected=1
        fi
    done
    
    if [ $changes_detected -eq 0 ]; then
        log_message "No changes detected in NetworkManager connections"
        return 0
    else
        return 1
    fi
}

# **Restore configuration**
restore_config() {
    # Remove all existing .nmconnection files to ensure a clean state
    rm -f /etc/NetworkManager/system-connections/*.nmconnection 2>> "$LOG_FILE" || {
        log_message "Failed to clear existing NetworkManager connections"
        return 1
    }
    
    # Copy backup .nmconnection files to the system directory
    cp "$BACKUP_DIR"/*.nmconnection /etc/NetworkManager/system-connections/ 2>> "$LOG_FILE" || {
        log_message "Failed to restore NetworkManager connection files"
        return 1
    }
    
    # Ensure proper permissions
    chmod 600 /etc/NetworkManager/system-connections/*.nmconnection 2>> "$LOG_FILE" || {
        log_message "Failed to set permissions on restored connections"
        return 1
    }
    
    # Reload NetworkManager to recognize the new configuration files
    nmcli connection reload 2>> "$LOG_FILE" || {
        log_message "Failed to reload NetworkManager connections"
        return 1
    }
    
    # Bring up all connections to ensure they are active
    for connection in $(nmcli -t -f NAME con show); do
        nmcli con up "$connection" 2>> "$LOG_FILE" || {
            log_message "Failed to bring up $connection"
            continue
        }
    done
    
    log_message "Configuration restored for NetworkManager"
}

# **Ensure backups exist**
ensure_backups() {
    if ! ls "$BACKUP_DIR"/*.nmconnection >/dev/null 2>&1; then
        log_message "No NetworkManager backups found. Creating backups..."
        backup_config
    fi
}

# **Display usage**
display_usage() {
    echo "Usage: $0 [backup|check|conf-check|reset|--setup-cron]"
    echo "  backup: Delete existing backups and create new ones"
    echo "  check: Manually check for changes in configurations"
    echo "  conf-check: Perform a single check-and-restore cycle"
    echo "  reset: Delete existing backups"
    echo "  --setup-cron: Setup cronjob to run conf-check every minute"
}

# **Main logic**
if [ $# -eq 0 ]; then
    ensure_backups
    display_usage
    exit 0
fi

ACTION="$1"

case "$ACTION" in
    reset)
        log_message "Deleting existing backups"
        rm -rf "$BACKUP_DIR"/*
        log_message "Backups deleted"
        ;;
    backup)
        log_message "Deleting existing backups"
        rm -rf "$BACKUP_DIR"/*
        log_message "Creating new backups"
        backup_config
        log_message "Backups created"
        ;;
    check)
        ensure_backups
        if ! check_changes; then
            log_message "Changes detected in configurations"
        else
            log_message "No changes detected in configurations"
        fi
        ;;
    conf-check)
        log_message "Starting configuration check cycle"
        ensure_backups
        if ! check_changes; then
            log_message "Restoring configuration"
            restore_config
        fi
        log_message "Configuration check cycle completed"
        ;;
    --setup-cron)
        PRO_INT_DIR="/etc/pro-int"
        mkdir -p "$PRO_INT_DIR"
        SCRIPT_NAME=$(basename "$0")
        cp "$0" "$PRO_INT_DIR/$SCRIPT_NAME"
        chmod +x "$PRO_INT_DIR/$SCRIPT_NAME"
        log_message "Script copied to $PRO_INT_DIR/$SCRIPT_NAME"
        CRON_COMMAND="* * * * * $PRO_INT_DIR/$SCRIPT_NAME conf-check"
        (crontab -l 2>/dev/null; echo "$CRON_COMMAND") | crontab -
        log_message "Cronjob created to run $PRO_INT_DIR/$SCRIPT_NAME conf-check every minute"
        ;;
    *)
        echo "Invalid argument: $ACTION"
        display_usage
        exit 1
        ;;
esac
