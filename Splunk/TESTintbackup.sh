#!/bin/bash

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

# Set D-Bus environment for NetworkManager (needed for cron)
if [ -z "$DBUS_SYSTEM_BUS_ADDRESS" ]; then
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/var/run/dbus/system_bus_socket
fi

### Detect Network Manager
detect_network_manager() {
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

# Detect the active network manager
NETWORK_MANAGER=$(detect_network_manager)
if [ "$NETWORK_MANAGER" = "unknown" ]; then
    log_message "Unsupported network management tool detected"
    exit 1
fi
log_message "Detected network manager: $NETWORK_MANAGER"

### Configure Paths and Types
case "$NETWORK_MANAGER" in
    networkmanager)
        CONFIG_PATH="/etc/NetworkManager/system-connections"
        IS_DIR=true
        ;;
    netplan)
        CONFIG_PATH="/etc/netplan"
        IS_DIR=true
        ;;
    systemd-networkd)
        CONFIG_PATH="/etc/systemd/network"
        IS_DIR=true
        ;;
    interfaces)
        CONFIG_PATH="/etc/network/interfaces"
        IS_DIR=false
        ;;
    network-scripts)
        CONFIG_PATH="/etc/sysconfig/network-scripts"
        IS_DIR=true
        ;;
esac

# Set backup directory for this manager
MANAGER_BACKUP_DIR="$BACKUP_DIR/$NETWORK_MANAGER"

### Backup Configuration
backup_config() {
    # Remove existing backups and create fresh ones
    rm -rf "$MANAGER_BACKUP_DIR"
    mkdir -p "$MANAGER_BACKUP_DIR"
    if $IS_DIR; then
        cp -r "$CONFIG_PATH"/* "$MANAGER_BACKUP_DIR/" || {
            log_message "Failed to backup $CONFIG_PATH"
            exit 1
        }
    else
        cp "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" || {
            log_message "Failed to backup $CONFIG_PATH"
            exit 1
        }
    fi
    log_message "Backup created for $NETWORK_MANAGER"
}

### Check for Changes
check_changes() {
    if [ ! -d "$MANAGER_BACKUP_DIR" ]; then
        log_message "No backup found for $NETWORK_MANAGER"
        return 1
    fi
    if $IS_DIR; then
        diff -r "$CONFIG_PATH" "$MANAGER_BACKUP_DIR" > /tmp/diff_output 2>&1
        diff_status=$?
    else
        diff "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" > /tmp/diff_output 2>&1
        diff_status=$?
    fi
    if [ $diff_status -eq 0 ]; then
        log_message "No changes detected in $NETWORK_MANAGER configurations"
        rm /tmp/diff_output
        return 0
    elif [ $diff_status -eq 1 ]; then
        log_message "Changes detected in $NETWORK_MANAGER configurations:"
        cat /tmp/diff_output >> "$LOG_FILE"
        rm /tmp/diff_output
        return 1
    else
        log_message "Error running diff: $diff_status"
        rm /tmp/diff_output
        exit 1
    fi
}

### Restore Configuration
restore_config() {
    if $IS_DIR; then
        rm -rf "$CONFIG_PATH"/*
        cp -r "$MANAGER_BACKUP_DIR"/* "$CONFIG_PATH/" || {
            log_message "Failed to restore $CONFIG_PATH"
            exit 1
        }
    else
        cp "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" "$CONFIG_PATH" || {
            log_message "Failed to restore $CONFIG_PATH"
            exit 1
        }
    fi
    # Apply changes based on network manager
    case "$NETWORK_MANAGER" in
        networkmanager)
            nmcli connection reload || log_message "Failed to reload NetworkManager"
            ;;
        netplan)
            netplan apply || log_message "Failed to apply Netplan"
            ;;
        systemd-networkd)
            systemctl restart systemd-networkd || log_message "Failed to restart systemd-networkd"
            ;;
        interfaces)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart networking || log_message "Failed to restart networking"
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service networking restart || log_message "Failed to restart networking"
            else
                log_message "Cannot restart networking service"
            fi
            ;;
        network-scripts)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart network || log_message "Failed to restart network"
            elif command -v service >/dev/null 2>&1; then
                service network restart || log_message "Failed to restart network"
            else
                log_message "Cannot restart network service"
            fi
            ;;
    esac
    log_message "Configuration restored for $NETWORK_MANAGER"
}

### Check and Restore (conf-check)
conf_check() {
    if [ ! -d "$MANAGER_BACKUP_DIR" ]; then
        log_message "No backup found for $NETWORK_MANAGER. Please run 'backup' first."
        exit 1
    fi
    if ! check_changes; then
        log_message "Restoring configuration for $NETWORK_MANAGER"
        restore_config
    fi
}

### Reset Backups
reset_backups() {
    rm -rf "$MANAGER_BACKUP_DIR"
    log_message "Backups deleted for $NETWORK_MANAGER"
}

### Setup Cron Job
setup_cron() {
    PRO_INT_DIR="/etc/pro-int"
    mkdir -p "$PRO_INT_DIR"
    SCRIPT_NAME=$(basename "$0")
    cp "$0" "$PRO_INT_DIR/$SCRIPT_NAME"
    chmod +x "$PRO_INT_DIR/$SCRIPT_NAME"
    log_message "Script copied to $PRO_INT_DIR/$SCRIPT_NAME"
    CRON_COMMAND="* * * * * $PRO_INT_DIR/$SCRIPT_NAME conf-check"
    (crontab -l 2>/dev/null; echo "$CRON_COMMAND") | crontab -
    log_message "Cron job created to run $PRO_INT_DIR/$SCRIPT_NAME conf-check every minute"
}

### Display Usage
display_usage() {
    echo "Usage: $0 [backup|check|conf-check|reset|--setup-cron]"
    echo "  backup: Delete existing backups and create new ones"
    echo "  check: Manually check for changes in configurations"
    echo "  conf-check: Perform a single check-and-restore cycle"
    echo "  reset: Delete existing backups"
    echo "  --setup-cron: Setup cron job to run conf-check every minute"
}

### Main Logic
if [ $# -eq 0 ]; then
    display_usage
    exit 0
fi

ACTION="$1"

case "$ACTION" in
    reset)
        reset_backups
        ;;
    backup)
        backup_config
        ;;
    check)
        check_changes
        ;;
    conf-check)
        conf_check
        ;;
    --setup-cron)
        setup_cron
        ;;
    *)
        echo "Invalid argument: $ACTION"
        display_usage
        exit 1
        ;;
esac
