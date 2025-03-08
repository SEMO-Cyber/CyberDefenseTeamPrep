#!/bin/bash

# Exit on errors
set -e

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Define directories and files
BAC_SERVICES_DIR="/etc/BacServices"
BACKUP_DIR="$BAC_SERVICES_DIR/interface-protection"
LOG_FILE="/var/log/interface-protection.log"
LOCK_FILE="/tmp/restore_lock"
DEBOUNCE_TIME=5  # seconds to wait after last event

# Create directories if they don’t exist
mkdir -p "$BAC_SERVICES_DIR"
mkdir -p "$BACKUP_DIR"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$1"
}

# Install inotify-tools if not present
if ! command -v inotifywait > /dev/null; then
    log_message "inotifywait not found, installing inotify-tools..."
    if command -v apt-get > /dev/null; then
        apt-get update && apt-get install -y inotify-tools
    elif command -v dnf > /dev/null; then
        dnf install -y inotify-tools
    elif command -v yum > /dev/null; then
        yum install -y inotify-tools
    elif command -v pacman > /dev/null; then
        pacman -S --noconfirm inotify-tools
    elif command -v zypper > /dev/null; then
        zypper install -y inotify-tools
    elif command -v apk > /dev/null; then
        apk add --no-cache inotify-tools
    else
        log_message "No supported package manager found. Please install inotify-tools manually."
        exit 1
    fi
    if ! command -v inotifywait > /dev/null; then
        log_message "Failed to install inotify-tools. Please install it manually."
        exit 1
    fi
    log_message "inotify-tools installed successfully."
fi

# Detect active network managers
detect_managers() {
    local managers=()
    [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1 && managers+=("netplan")
    systemctl is-active NetworkManager >/dev/null 2>&1 && managers+=("networkmanager")
    systemctl is-active systemd-networkd >/dev/null 2>&1 && [ -d /etc/systemd/network ] && ls /etc/systemd/network/*.network >/dev/null 2>&1 && managers+=("systemd-networkd")
    [ -f /etc/network/interfaces ] && managers+=("interfaces")
    [ -d /etc/sysconfig/network-scripts ] && ls /etc/sysconfig/network-scripts/ifcfg-* >/dev/null 2>&1 && managers+=("network-scripts")
    if [ ${#managers[@]} -eq 0 ]; then
        echo "unknown"
    else
        echo "${managers[@]}"
    fi
}

# Get configuration path for a manager
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

# Check if config is a directory
get_is_dir() {
    case "$1" in
        netplan|networkmanager|systemd-networkd|network-scripts) echo true ;;
        interfaces) echo false ;;
        *) echo false ;;
    esac
}

# Restart a service
restart_service() {
    local service="$1"
    if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service | grep -q "$service.service"; then
        systemctl restart "$service" || log_message "Failed to restart $service with systemctl"
    elif command -v service >/dev/null 2>&1 && [ -f "/etc/init.d/$service" ]; then
        service "$service" restart || log_message "Failed to restart $service with service"
    else
        log_message "Cannot restart $service: no suitable command found"
    fi
}

# Apply configuration
apply_config() {
    local manager="$1"
    case "$manager" in
        netplan) netplan apply || log_message "Failed to apply netplan" ;;
        networkmanager)
            restart_service "NetworkManager"
            for device in $(nmcli -t -f GENERAL.DEVICE device show | cut -d':' -f2 | grep -v lo); do
                nmcli device reapply "$device" || log_message "Warning: Failed to reapply $device"
            done
            ;;
        systemd-networkd) restart_service "systemd-networkd" ;;
        interfaces) restart_service "networking" ;;
        network-scripts) restart_service "network" ;;
    esac
}

# Backup configuration
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
            log_message "Configuration directory $CONFIG_PATH is empty for $manager"
        fi
    else
        cp "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" || {
            log_message "Failed to backup $CONFIG_PATH for $manager"
            exit 1
        }
    fi
    log_message "Backup created for $manager"
}

# Restore configuration
restore_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    # Create lock file to prevent event loop
    touch "$LOCK_FILE"

    if [ "$IS_DIR" = "true" ]; then
        rm -rf "$CONFIG_PATH"/*
        cp -rf "$MANAGER_BACKUP_DIR"/* "$CONFIG_PATH/" || {
            log_message "Failed to restore $CONFIG_PATH for $manager"
            rm -f "$LOCK_FILE"
            exit 1
        }
    else
        cp "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" "$CONFIG_PATH" || {
            log_message "Failed to restore $CONFIG_PATH for $manager"
            rm -f "$LOCK_FILE"
            exit 1
        }
    fi
    log_message "Configuration restored for $manager"
    apply_config "$manager"

    # Remove lock file
    rm -f "$LOCK_FILE"
}

# Monitor configuration changes
monitor_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")

    if [ "$IS_DIR" = "true" ]; then
        inotifywait -m -r -e modify,create,delete "$CONFIG_PATH" | while read -r line; do
            if [ -f "$LOCK_FILE" ]; then
                continue  # Skip if restoring
            fi
            log_message "Change detected in $manager: $line"
            # Debounce: wait for no events
            last_event_time=$(date +%s)
            while [ $(date +%s) -lt $(($last_event_time + $DEBOUNCE_TIME)) ]; do
                inotifywait -q -t 1 "$CONFIG_PATH" || break
            done
            if [ ! -f "$LOCK_FILE" ]; then
                restore_config "$manager"
            fi
        done
    else
        inotifywait -m -e modify "$CONFIG_PATH" | while read -r line; do
            if [ -f "$LOCK_FILE" ]; then
                continue  # Skip if restoring
            fi
            log_message "Change detected in $manager: $line"
            restore_config "$manager"
        done
    fi
}

# Main logic
managers=($(detect_managers))
if [ "${managers[0]}" = "unknown" ]; then
    log_message "No active network managers detected"
    exit 1
fi

for manager in "${managers[@]}"; do
    log_message "Detected active manager: $manager"
    backup_config "$manager"
    monitor_config "$manager" &
done

log_message "Monitoring started for: ${managers[*]}"
