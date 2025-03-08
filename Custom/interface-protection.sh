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

# List of possible network managers, restored to original order
managers=("netplan" "networkmanager" "systemd-networkd" "interfaces" "network-scripts")

# Function to get the service name for a manager
get_service_name() {
    case "$1" in
        networkmanager)
            echo "NetworkManager"
            ;;
        systemd-networkd)
            echo "systemd-networkd"
            ;;
        interfaces)
            echo "networking"
            ;;
        network-scripts)
            echo "network"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to check if a manager is active
is_manager_active() {
    case "$1" in
        netplan)
            [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1
            ;;
        networkmanager)
            systemctl is-active NetworkManager >/dev/null 2>&1
            ;;
        systemd-networkd)
            systemctl is-active systemd-networkd >/dev/null 2>&1 && [ -d /etc/systemd/network ] && ls /etc/systemd/network/*.network >/dev/null 2>&1
            ;;
        interfaces)
            [ -f /etc/network/interfaces ]
            ;;
        network-scripts)
            [ -d /etc/sysconfig/network-scripts ] && ls /etc/sysconfig/network-scripts/ifcfg-* >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to get the configuration path for a manager
get_config_path() {
    case "$1" in
        netplan)
            echo "/etc/netplan"
            ;;
        networkmanager)
            echo "/etc/NetworkManager/system-connections"
            ;;
        systemd-networkd)
            echo "/etc/systemd/network"
            ;;
        interfaces)
            echo "/etc/network/interfaces"
            ;;
        network-scripts)
            echo "/etc/sysconfig/network-scripts"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to check if the configuration is a directory
get_is_dir() {
    case "$1" in
        netplan|networkmanager|systemd-networkd|network-scripts)
            echo true
            ;;
        interfaces)
            echo false
            ;;
        *)
            echo false
            ;;
    esac
}

# Backup Configuration and Device States
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
    if [ "$manager" = "networkmanager" ]; then
        nmcli -t -f GENERAL.DEVICE,IP4.ADDRESS,GENERAL.STATE device show > "$MANAGER_BACKUP_DIR/device_states.backup" || {
            log_message "Failed to backup device states for NetworkManager"
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
        local changes_detected=false
        for backup_file in "$MANAGER_BACKUP_DIR"/*; do
            [ -e "$backup_file" ] || continue
            local file_name=$(basename "$backup_file")
            local current_file="$CONFIG_PATH/$file_name"
            if [ -f "$current_file" ]; then
                diff "$current_file" "$backup_file" > /dev/null 2>&1
                if [ $? -ne 0 ]; then
                    log_message "Changes detected in $current_file"
                    changes_detected=true
                fi
            else
                log_message "File $current_file is missing"
                changes_detected=true
            fi
        done
        if $changes_detected; then
            return 1
        else
            return 0
        fi
    else
        diff "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            log_message "Changes detected in $CONFIG_PATH"
            return 1
        else
            return 0
        fi
    fi
}

# Check for Changes in Device States (for NetworkManager)
check_device_changes() {
    local manager="$1"
    if [ "$manager" != "networkmanager" ]; then
        return 0
    fi
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"
    if [ ! -f "$MANAGER_BACKUP_DIR/device_states.backup" ]; then
        log_message "No device state backup found for NetworkManager"
        return 1
    fi
    nmcli -t -f GENERAL.DEVICE,IP4.ADDRESS,GENERAL.STATE device show > /tmp/current_device_states
    diff /tmp/current_device_states "$MANAGER_BACKUP_DIR/device_states.backup" > /tmp/device_diff_output 2>&1
    diff_status=$?
    if [ $diff_status -eq 0 ]; then
        log_message "No changes detected in device states for NetworkManager"
        rm /tmp/current_device_states /tmp/device_diff_output
        return 0
    elif [ $diff_status -eq 1 ]; then
        log_message "Changes detected in device states for NetworkManager:"
        cat /tmp/device_diff_output >> "$LOG_FILE"
        rm /tmp/current_device_states /tmp/device_diff_output
        return 1
    else
        log_message "Error running diff for device states: $diff_status"
        rm /tmp/current_device_states /tmp/device_diff_output
        exit 1
    fi
}

# Function to check and start service with 5-second delay
check_and_start_service() {
    local service="$1"
    if [ -z "$service" ]; then
        log_message "No service name provided. Skipping."
        return 1
    fi

    # Check if the service unit exists
    if systemctl cat "$service" >/dev/null 2>&1; then
        log_message "Service unit $service exists."
    else
        log_message "Service unit $service does not exist on the system."
        return 1
    fi

    # Get current service status
    local is_active=$(systemctl is-active "$service" 2>/dev/null)
    log_message "Service $service status before check: $is_active"

    if [ "$is_active" = "active" ]; then
        log_message "Service $service is already active. No action needed."
        return 0
    else
        log_message "Service $service is not active (state: $is_active). Attempting to start it."
        systemctl start "$service" 2>>"$LOG_FILE"
        sleep 5  # Wait 5 seconds after starting the service
        is_active=$(systemctl is-active "$service" 2>/dev/null)
        log_message "Service $service status after start attempt: $is_active"
        if [ "$is_active" = "active" ]; then
            log_message "Service $service started successfully."
        else
            log_message "Service $service did not start successfully."
        fi
    fi
}

# Restore Configuration with 5-second delay after service restart
restore_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    if [ "$IS_DIR" = "true" ]; then
        rm -rf "$CONFIG_PATH"/*
        if [ "$(ls -A "$MANAGER_BACKUP_DIR")" ]; then
            cp -rf "$MANAGER_BACKUP_DIR"/* "$CONFIG_PATH/" || {
                log_message "Failed to restore $CONFIG_PATH for $manager"
                echo "Failed to restore $CONFIG_PATH for $manager"
                exit 1
            }
            if [ "$manager" = "networkmanager" ]; then
                chown root:root "$CONFIG_PATH"/*
                chmod 600 "$CONFIG_PATH"/*
            fi
        else
            log_message "Backup directory $MANAGER_BACKUP_DIR is empty for $manager, no files to restore"
            echo "Backup directory $MANAGER_BACKUP_DIR is empty for $manager, no files to restore"
        fi
    else
        cp "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" "$CONFIG_PATH" || {
            log_message "Failed to restore $CONFIG_PATH for $manager"
            exit 1
        }
    fi
    case "$manager" in
        networkmanager)
            systemctl restart NetworkManager || {
                log_message "Failed to restart NetworkManager"
                echo "Failed to restart NetworkManager"
                exit 1
            }
            sleep 5  # Delay after restart
            for device in $(nmcli -t -f DEVICE device show | grep -v lo); do
                nmcli device reapply "$device" || {
                    log_message "Warning: Failed to reapply configuration for $device"
                    echo "Warning: Failed to reapply configuration for $device"
                }
            done
            log_message "NetworkManager configuration restored and reapplied"
            log_message "Device states after restoration:"
            nmcli -t -f GENERAL.DEVICE,IP4.ADDRESS,GENERAL.STATE device show >> "$LOG_FILE"
            ;;
        netplan)
            netplan apply || log_message "Failed to apply Netplan"
            sleep 5  # Delay after apply
            ;;
        systemd-networkd)
            systemctl restart systemd-networkd || log_message "Failed to restart systemd-networkd"
            sleep 5  # Delay after restart
            ;;
        interfaces)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart networking || log_message "Failed to restart networking"
                sleep 5  # Delay after restart
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service networking restart || log_message "Failed to restart networking"
                sleep 5  # Delay after restart
            else
                log_message "Cannot restart networking service"
            fi
            ;;
        network-scripts)
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart network || log_message "Failed to restart network"
                sleep 5  # Delay after restart
            elif command -v service >/dev/null 2>&1; then
                service network restart || log_message "Failed to restart network"
                sleep 5  # Delay after restart
            else
                log_message "Cannot restart network service"
            fi
            ;;
    esac
    log_message "Configuration restored for $manager"
}

# Setup Cron Job
setup_cron() {
    PRO_INT_DIR="/etc/pro-int"
    mkdir -p "$PRO_INT_DIR"
    SCRIPT_NAME="interface-protection.sh"
    cp "$(readlink -f "$0")" "$PRO_INT_DIR/$SCRIPT_NAME"
    chmod +x "$PRO_INT_DIR/$SCRIPT_NAME"
    log_message "Script copied to $PRO_INT_DIR/$SCRIPT_NAME"
    CRON_COMMAND="* * * * * $PRO_INT_DIR/$SCRIPT_NAME conf-check"
    if ! (crontab -l 2>/dev/null; echo "$CRON_COMMAND") | crontab -; then
        log_message "Failed to set crontab"
        exit 1
    fi
    log_message "Cron job created to run $PRO_INT_DIR/$SCRIPT_NAME conf-check every minute"
}

# Display Usage
display_usage() {
    echo "Usage: $0 [backup|check|conf-check|reset|--setup-cron]"
    echo "  backup: Delete existing backups and create new ones for all active managers"
    echo "  check: Manually check for changes in configurations and device states for all active managers"
    echo "  conf-check: Perform a single check-and-restore cycle for all active managers"
    echo "  reset: Delete all existing backups"
    echo "  --setup-cron: Setup cron job to run conf-check every minute"
}

# Main Logic
if [ $# -eq 0 ]; then
    display_usage
    exit 0
fi

ACTION="$1"

if [ "$ACTION" = "backup" ]; then
    for manager in "${managers[@]}"; do
        if is_manager_active "$manager"; then
            backup_config "$manager"
        fi
    done
elif [ "$ACTION" = "check" ]; then
    for manager in "${managers[@]}"; do
        if is_manager_active "$manager"; then
            check_config_changes "$manager"
            if [ "$manager" = "networkmanager" ]; then
                check_device_changes "$manager"
            fi
        fi
    done
elif [ "$ACTION" = "conf-check" ]; then
    for manager in "${managers[@]}"; do
        service_name=$(get_service_name "$manager")
        if [ -n "$service_name" ]; then
            check_and_start_service "$service_name"
        fi
        if is_manager_active "$manager"; then
            config_changed=false
            device_changed=false
            if ! check_config_changes "$manager"; then
                config_changed=true
            fi
            if [ "$manager" = "networkmanager" ]; then
                if ! check_device_changes "$manager"; then
                    device_changed=true
                fi
            fi
            if $config_changed || $device_changed; then
                log_message "Restoring configuration for $manager"
                restore_config "$manager"
            else
                log_message "No changes detected for $manager"
            fi
        else
            log_message "Manager $manager is not active. Skipping checks."
        fi
    done
elif [ "$ACTION" = "reset" ]; then
    rm -rf "$BACKUP_DIR"/*
    log_message "All backups deleted"
elif [ "$ACTION" = "--setup-cron" ]; then
    setup_cron
else
    echo "Invalid argument: $ACTION"
    display_usage
    exit 1
fi
