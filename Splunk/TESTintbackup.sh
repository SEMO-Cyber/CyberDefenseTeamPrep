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

# List of possible network managers
managers=("netplan" "networkmanager" "systemd-networkd" "interfaces" "network-scripts")

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
        diff -r "$CONFIG_PATH" "$MANAGER_BACKUP_DIR" > /tmp/diff_output 2>&1
        diff_status=$?
    else
        diff "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" > /tmp/diff_output 2>&1
        diff_status=$?
    fi
    if [ $diff_status -eq 0 ]; then
        log_message "No changes detected in $manager configurations"
        rm /tmp/diff_output
        return 0
    elif [ $diff_status -eq 1 ]; then
        log_message "Changes detected in $manager configurations:"
        cat /tmp/diff_output >> "$LOG_FILE"
        rm /tmp/diff_output
        return 1
    else
        log_message "Error running diff for $manager: $diff_status"
        rm /tmp/diff_output
        exit 1
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

# Restore Configuration
restore_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    if [ "$IS_DIR" = "true" ]; then
        rm -rf "$CONFIG_PATH"/*
        if [ "$(ls -A "$MANAGER_BACKUP_DIR")" ]; then
            cp -rf"$MANAGER_BACKUP_DIR"/* "$CONFIG_PATH/" || {
                log_message "Failed to restore $CONFIG_PATH for $manager"
                echo "Failed to restore $CONFIG_PATH for $manager"
                exit 1
            }
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
            # Reload NetworkManager to recognize restored files
            nmcli connection reload || echo "Failed to reload NetworkManager"

            # Restore device state from backup
            if [ -f "$MANAGER_BACKUP_DIR/device_states.backup" ]; then
                while IFS=':' read -r key value; do
                    if [[ "$key" =~ ^GENERAL\.DEVICE ]]; then
                        device="$value"
                    elif [[ "$key" =~ ^IP4\.ADDRESS\[1\] ]]; then
                        ip_addr="$value"
                    elif [[ "$key" =~ ^IP4\.GATEWAY ]]; then
                        gateway="$value"
                    fi
                done < "$MANAGER_BACKUP_DIR/device_states.backup"

                if [ -n "$device" ] && [ -n "$ip_addr" ] && [ -n "$gateway" ]; then
                    # Delete the existing connection to clear misconfigurations
                    nmcli connection delete "$device" || echo "Failed to delete connection for $device"
                    # Create a new connection with backed-up settings
                    nmcli connection add type ethernet ifname "$device" con-name "$device" \
                        ipv4.method manual ipv4.addresses "$ip_addr" ipv4.gateway "$gateway"
                    nmcli connection up "$device" || echo "Failed to bring up $device"
                else
                    echo "Missing device, IP, or gateway in backup"
                fi
            else
                echo "No device state backup found"
            fi
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
    log_message "Configuration restored for $manager"
}

# Setup Cron Job
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
