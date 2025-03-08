#!/bin/bash

# Exit on errors
set -e

# Ensure the script is run as root
if [ "$(id -u)" != "0"]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Directories and log file
BACKUP_DIR="/etc/BacServices/interface-protection"
LOG_FILE="/var/log/interface-protection.log"

# Create directories if they don’t exist
mkdir -p "$BACKUP_DIR"

# Log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Set D-Bus environment for nmcli (needed in cron/non-interactive shells)
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/var/run/dbus/system_bus_socket

# Get NetworkManager connections
get_interfaces() {
    nmcli -t -f NAME con show | grep -v '^lo$'
}

# Backup configuration
backup_config() {
    for conn in $(get_interfaces); do
        nmcli -t -f connection.id,connection.type,connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns con show "$conn" > "$BACKUP_DIR/$conn.fields.backup" 2>> "$LOG_FILE" || log_message "Failed to backup fields for $conn"
    done
    log_message "Backup created for NetworkManager connections"
}

# Check for changes
check_changes() {
    local changes_detected=0
    for conn in $(get_interfaces); do
        local backup_fields="$BACKUP_DIR/$conn.fields.backup"
        local temp_fields="/tmp/$conn.fields.current"
        if [ ! -f "$backup_fields" ]; then
            log_message "No backup found for connection $conn"
            changes_detected=1
            continue
        fi
        nmcli -t -f connection.id,connection.type,connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns con show "$conn" > "$temp_fields" 2>> "$LOG_FILE"
        if [ $? -ne 0 ]; then
            log_message "Failed to get current fields for $conn"
            rm -f "$temp_fields"
            continue
        fi
        if ! cmp -s "$temp_fields" "$backup_fields"; then
            log_message "Changes detected in connection $conn. Differences:"
            diff -u "$backup_fields" "$temp_fields" >> "$LOG_FILE" 2>&1
            changes_detected=1
        fi
        rm -f "$temp_fields"
    done
    if [ $changes_detected -eq 0 ]; then
        log_message "No changes detected in NetworkManager connections"
        return 0
    else
        return 1
    fi
}

# Restore configuration
restore_config() {
    for conn in $(get_interfaces); do
        local backup_fields="$BACKUP_DIR/$conn.fields.backup"
        if [ -f "$backup_fields" ]; then
            # Bring connection down to ensure changes apply
            nmcli con down "$conn" 2>> "$LOG_FILE" || log_message "Failed to bring down $conn"
            # Restore each field
            while IFS=':' read -r field value; do
                case "$field" in
                    connection.id) ;; # Skip
                    connection.type)
                        nmcli con mod "$conn" connection.type "$value" 2>> "$LOG_FILE"
                        [ $? -ne 0 ] && log_message "Failed to set connection.type to $value for $conn"
                        ;;
                    connection.interface-name)
                        nmcli con mod "$conn" connection.interface-name "$value" 2>> "$LOG_FILE"
                        [ $? -ne 0 ] && log_message "Failed to set connection.interface-name to $value for $conn"
                        ;;
                    ipv4.method)
                        nmcli con mod "$conn" ipv4.method "$value" 2>> "$LOG_FILE"
                        [ $? -ne 0 ] && log_message "Failed to set ipv4.method to $value for $conn"
                        ;;
                    ipv4.addresses)
                        nmcli con mod "$conn" ipv4.addresses "$value" 2>> "$LOG_FILE"
                        [ $? -ne 0 ] && log_message "Failed to set ipv4.addresses to $value for $conn"
                        ;;
                    ipv4.gateway)
                        nmcli con mod "$conn" ipv4.gateway "$value" 2>> "$LOG_FILE"
                        [ $? -ne 0 ] && log_message "Failed to set ipv4.gateway to $value for $conn"
                        ;;
                    ipv4.dns)
                        nmcli con mod "$conn" ipv4.dns "$value" 2>> "$LOG_FILE"
                        [ $? -ne 0 ] && log_message "Failed to set ipv4.dns to $value for $conn"
                        ;;
                esac
            done < "$backup_fields"
            # Bring connection up to apply changes
            nmcli con up "$conn" 2>> "$LOG_FILE" || log_message "Failed to bring up $conn after restoration"
            log_message "Restored configuration for $conn"
        fi
    done
}

# Ensure backups exist
ensure_backups() {
    if ! ls "$BACKUP_DIR"/*.fields.backup >/dev/null 2>&1; then
        log_message "No backups found. Creating backups..."
        backup_config
    fi
}

# Main logic
case "$1" in
    backup)
        rm -rf "$BACKUP_DIR"/*
        backup_config
        ;;
    conf-check)
        ensure_backups
        if ! check_changes; then
            log_message "Changes detected, restoring configuration"
            restore_config
        fi
        log_message "Conf-check cycle completed"
        ;;
    *)
        echo "Usage: $0 [backup|conf-check]"
        exit 1
        ;;
esac
