#!/bin/bash
# Rewrite number 3. Yay.

# Exit on errors
set -e

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Define directories and log file
BAC_SERVICES_DIR="/etc/BacServices"
BACKUP_DIR="$BAC_SERVICES_DIR/interface-protection"
LOG_FILE="/var/log/interface-protection.log"

# Create directories if they don’t exist
mkdir -p "$BAC_SERVICES_DIR"
mkdir -p "$BACKUP_DIR"

# Function to log messages with timestamp to file and console
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$1"
}

# Function to detect the active network manager
detect_manager() {
    if [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
        echo "netplan"
    elif systemctl is-active NetworkManager >/dev/null 2>&1; then
        echo "networkmanager"
    elif systemctl is-active systemd-networkd >/dev/null 2>&1 && [ -d /etc/systemd/network ] && ls /etc/systemd/network/*.network >/dev/null 2>&1; then
        echo "systemd-networkd"
    elif [ -f /etc/network/interfaces ]; then
        echo "interfaces"
    elif [ -d /etc/sysconfig/network-scripts ] && ls /etc/sysconfig/network-scripts/ifcfg-* >/dev/null 2>&1; then
        echo "network-scripts"
    else
        echo "unknown"
    fi
}

# Function to get the configuration path for a manager
get_config_path() {
    case "$1" in
        netplan) echo "/etc/netplan" ;;
        networkmanager) echo "/etc/NetworkManager/system-connections" ;;
        systemd-networkd) echo "/etc/systemd/network" ;;
        interfaces) echo "/etc/network/interfaces" ;;
        network-scripts) echo "/etc/sysconfig/network-scripts" ;;
        *) echo "" ;;
    esac
}

# Function to check if the configuration is a directory
get_is_dir() {
    case "$1" in
        netplan|networkmanager|systemd-networkd|network-scripts) echo true ;;
        interfaces) echo false ;;
        *) echo false ;;
    esac
}

# Function to restart a service in a distribution-agnostic way
restart_service() {
    local service="$1"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-units --type=service | grep -q "$service.service"; then
            systemctl restart "$service" || log_message "Failed to restart $service with systemctl"
        else
            log_message "Service $service not found with systemctl"
        fi
    elif command -v service >/dev/null 2>&1; then
        if [ -f "/etc/init.d/$service" ]; then
            service "$service" restart || log_message "Failed to restart $service with service"
        else
            log_message "Service $service not found in /etc/init.d"
        fi
    else
        log_message "Cannot restart service: no systemctl or service command found"
    fi
}

# Function to apply configurations based on the manager
apply_config() {
    local manager="$1"
    case "$manager" in
        netplan)
            netplan apply || log_message "Failed to apply netplan"
            ;;
        networkmanager)
            restart_service "NetworkManager"
            for device in $(nmcli -t -f GENERAL.DEVICE device show | cut -d':' -f2 | grep -v lo); do
                nmcli device reapply "$device" || log_message "Warning: Failed to reapply configuration for $device"
            done
            ;;
        systemd-networkd)
            restart_service "systemd-networkd"
            ;;
        interfaces)
            restart_service "networking"
            ;;
        network-scripts)
            restart_service "network"
            ;;
    esac
}

# Backup Configuration
backup_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    rm -rf "$MANAGER_BACKUP_DIR"
    mkdir -p "$MANAGER_BACKUP_DIR"
    if [ "$IS_DIR" = "true" ]; then
        if [ "$(ls -A "$CONFIG_PATH")" ]; then
            cp -r "$CONFIG_PATH"/* "$MANAGER_BACKUP_DIR/" || {
                log_message "Failed to backup $CONFIG_PATH for $manager"
                exit 1
            }
        else
            log_message "Configuration directory $CONFIG_PATH is empty for $manager, no files to backup"
        fi
    else
        cp "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" || {
            log_message "Failed to backup $CONFIG_PATH for $manager"
            exit 1
        }
    fi
    log_message "Backup created for $manager"
}

# Check for Changes in Configuration
check_config_changes() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    if [ ! -d "$MANAGER_BACKUP_DIR" ]; then
        log_message "No backup found for $manager"
        return 1
    fi

    if [ "$IS_DIR" = "true" ]; then
        diff -r "$CONFIG_PATH" "$MANAGER_BACKUP_DIR" > /dev/null 2>&1
        [ $? -ne 0 ] && log_message "Changes detected in $CONFIG_PATH for $manager" && return 1
        return 0
    else
        diff "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" > /dev/null 2>&1
        [ $? -ne 0 ] && log_message "Changes detected in $CONFIG_PATH for $manager" && return 1
        return 0
    fi
}

# Restore Configuration
restore_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    if [ "$IS_DIR" = "true" ]; then
        rm -rf "$CONFIG_PATH"/*
        cp -rf "$MANAGER_BACKUP_DIR"/* "$CONFIG_PATH/" || {
            log_message "Failed to restore $CONFIG_PATH for $manager"
            exit 1
        }
    else
        cp "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" "$CONFIG_PATH" || {
            log_message "Failed to restore $CONFIG_PATH for $manager"
            exit 1
        }
    fi
    log_message "Configuration restored for $manager"
    apply_config "$manager"
}

# Display Usage
display_usage() {
    echo "Usage: $0 [backup|check|conf-check|reset]"
    echo "  backup: Delete existing backups and create new ones for the active manager"
    echo "  check: Manually check for changes in configurations for the active manager"
    echo "  conf-check: Perform a single check-and-restore cycle for the active manager"
    echo "  reset: Delete all existing backups"
}

# Main Logic
if [ $# -eq 0 ]; then
    display_usage
    exit 0
fi

ACTION="$1"
manager=$(detect_manager)

if [ "$manager" = "unknown" ] && [ "$ACTION" != "reset" ]; then
    log_message "Unknown network manager, cannot proceed with $ACTION"
    exit 1
fi

case "$ACTION" in
    backup)
        backup_config "$manager"
        ;;
    check)
        check_config_changes "$manager"
        ;;
    conf-check)
        if ! check_config_changes "$manager"; then
            log_message "Changes detected, restoring configuration for $manager"
            restore_config "$manager"
        else
            log_message "No changes detected for $manager"
        fi
        ;;
    reset)
        rm -rf "$BACKUP_DIR"/*
        log_message "All backups deleted"
        ;;
    *)
        echo "Invalid argument: $ACTION"
        display_usage
        exit 1
        ;;
esac
