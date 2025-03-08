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

# Create directories if they don't exist
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

### Detect All Network Managers
detect_network_managers() {
    local managers=()
    
    # Check for netplan
    if [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
        managers+=("netplan")
    fi
    
    # Check for NetworkManager
    if systemctl is-active NetworkManager >/dev/null 2>&1; then
        managers+=("networkmanager")
    fi
    
    # Check for systemd-networkd
    if systemctl is-active systemd-networkd >/dev/null 2>&1 && 
       [ -d /etc/systemd/network ] && 
       ls /etc/systemd/network/*.network >/dev/null 2>&1; then
        managers+=("systemd-networkd")
    fi
    
    # Check for traditional interfaces
    if [ -f /etc/network/interfaces ]; then
        managers+=("interfaces")
    fi
    
    # Check for network-scripts
    if [ -d /etc/sysconfig/network-scripts ] && 
       ls /etc/sysconfig/network-scripts/ifcfg-* >/dev/null 2>&1; then
        managers+=("network-scripts")
    fi
    
    echo "${managers[@]}"
}

# Detect all network managers
NETWORK_MANAGERS=($(detect_network_managers))
if [ ${#NETWORK_MANAGERS[@]} -eq 0 ]; then
    log_message "No supported network management tools detected"
    exit 1
fi

log_message "Detected network managers: ${NETWORK_MANAGERS[*]}"

### Configure Paths and Types
declare -A CONFIG_PATHS
declare -A IS_DIRS

for manager in "${NETWORK_MANAGERS[@]}"; do
    case "$manager" in
        networkmanager)
            CONFIG_PATHS[$manager]="/etc/NetworkManager/system-connections"
            IS_DIRS[$manager]=true
            ;;
        netplan)
            CONFIG_PATHS[$manager]="/etc/netplan"
            IS_DIRS[$manager]=true
            ;;
        systemd-networkd)
            CONFIG_PATHS[$manager]="/etc/systemd/network"
            IS_DIRS[$manager]=true
            ;;
        interfaces)
            CONFIG_PATHS[$manager]="/etc/network/interfaces"
            IS_DIRS[$manager]=false
            ;;
        network-scripts)
            CONFIG_PATHS[$manager]="/etc/sysconfig/network-scripts"
            IS_DIRS[$manager]=true
            ;;
    esac
done

### Backup Configuration and Device States
backup_config() {
    for manager in "${NETWORK_MANAGERS[@]}"; do
        MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"
        
        # Remove existing backups and create fresh ones
        rm -rf "$MANAGER_BACKUP_DIR"
        mkdir -p "$MANAGER_BACKUP_DIR"
        
        if [ "${IS_DIRS[$manager]}" = true ]; then
            cp -r "${CONFIG_PATHS[$manager]}"/* "$MANAGER_BACKUP_DIR/" || {
                log_message "Failed to backup ${CONFIG_PATHS[$manager]}"
                exit 1
            }
        else
            cp "${CONFIG_PATHS[$manager]}" "$MANAGER_BACKUP_DIR/$(basename "${CONFIG_PATHS[$manager]}")" || {
                log_message "Failed to backup ${CONFIG_PATHS[$manager]}"
                exit 1
            }
        fi
        
        # For NetworkManager, also backup device states
        if [ "$manager" = "networkmanager" ]; then
            nmcli -t -f GENERAL.DEVICE,IP4.ADDRESS device show > "$MANAGER_BACKUP_DIR/device_states.backup" || {
                log_message "Failed to backup device states for NetworkManager"
                exit 1
            }
        fi
        
        log_message "Backup created for $manager"
    done
}

### Check for Changes in Configuration
check_config_changes() {
    local changes_detected=false
    
    for manager in "${NETWORK_MANAGERS[@]}"; do
        MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"
        
        if [ ! -d "$MANAGER_BACKUP_DIR" ]; then
            log_message "No backup found for $manager"
            continue
        fi
        
        if [ "${IS_DIRS[$manager]}" = true ]; then
            diff -r "${CONFIG_PATHS[$manager]}" "$MANAGER_BACKUP_DIR" > /tmp/diff_output 2>&1
            diff_status=$?
        else
            diff "${CONFIG_PATHS[$manager]}" "$MANAGER_BACKUP_DIR/$(basename "${CONFIG_PATHS[$manager]}")" > /tmp/diff_output 2>&1
            diff_status=$?
        fi
        
        if [ $diff_status -eq 0 ]; then
            log_message "No changes detected in $manager configurations"
        elif [ $diff_status -eq 1 ]; then
            log_message "Changes detected in $manager configurations:"
            cat /tmp/diff_output >> "$LOG_FILE"
            changes_detected=true
        else
            log_message "Error running diff for $manager: $diff_status"
        fi
        
        rm /tmp/diff_output
    done
    
    if $changes_detected; then
        return 1
    fi
    return 0
}

### Check for Changes in Device States (for NetworkManager)
check_device_changes() {
    local changes_detected=false
    
    for manager in "${NETWORK_MANAGERS[@]}"; do
        if [ "$manager" != "networkmanager" ]; then
            continue
        fi
        
        MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"
        
        if [ ! -f "$MANAGER_BACKUP_DIR/device_states.backup" ]; then
            log_message "No device state backup found for NetworkManager"
            continue
        fi
        
        nmcli -t -f GENERAL.DEVICE,IP4.ADDRESS device show > /tmp/current_device_states
        diff /tmp/current_device_states "$MANAGER_BACKUP_DIR/device_states.backup" > /tmp/device_diff_output 2>&1
        diff_status=$?
        
        if [ $diff_status -eq 0 ]; then
            log_message "No changes detected in device states for NetworkManager"
        elif [ $diff_status -eq 1 ]; then
            log_message "Changes detected in device states for NetworkManager:"
            cat /tmp/device_diff_output >> "$LOG_FILE"
            changes_detected=true
        else
            log_message "Error running diff for device states: $diff_status"
        fi
        
        rm /tmp/current_device_states /tmp/device_diff_output
    done
    
    if $changes_detected; then
        return 1
    fi
    return 0
}

### Restore Configuration
restore_config() {
    for manager in "${NETWORK_MANAGERS[@]}"; do
        MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"
        
        if [ "${IS_DIRS[$manager]}" = true ]; then
            rm -rf "${CONFIG_PATHS[$manager]}"/*
            cp -r "$MANAGER_BACKUP_DIR"/* "${CONFIG_PATHS[$manager]}/" || {
                log_message "Failed to restore ${CONFIG_PATHS[$manager]}"
                exit 1
            }
        else
            cp "$MANAGER_BACKUP_DIR/$(basename "${CONFIG_PATHS[$manager]}")" "${CONFIG_PATHS[$manager]}" || {
                log_message "Failed to restore ${CONFIG_PATHS[$manager]}"
                exit 1
            }
        fi
        
        # Apply changes based on network manager
        case "$manager" in
            networkmanager)
                nmcli connection reload || log_message "Failed to reload NetworkManager"
                for conn in $(nmcli -t -f NAME con show); do
                    nmcli con up "$conn" || log_message "Failed to bring up $conn"
                done
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
    done
}

### Check and Restore (conf-check)
conf_check() {
    local config_changed=false
    local device_changed=false
    
    for manager in "${NETWORK_MANAGERS[@]}"; do
        MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"
        
        if [ ! -d "$MANAGER_BACKUP_DIR" ]; then
            log_message "No backup found for $manager. Please run 'backup' first."
            continue
        fi
        
        if ! check_config_changes; then
            config_changed=true
        fi
        
        if [ "$manager" = "networkmanager" ]; then
            if ! check_device_changes; then
                device_changed=true
            fi
        fi
    done
    
    if $config_changed || $device_changed; then
        log_message "Restoring configurations for all network managers"
        restore_config
    else
        log_message "No changes detected in configurations or device states"
    fi
}

### Reset Backups
reset_backups() {
    for manager in "${NETWORK_MANAGERS[@]}"; do
        MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"
        rm -rf "$MANAGER_BACKUP_DIR"
        log_message "Backups deleted for $manager"
    done
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
    echo "  check: Manually check for changes in configurations and device states"
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
        check_config_changes
        for manager in "${NETWORK_MANAGERS[@]}"; do
            if [ "$manager" = "networkmanager" ]; then
                check_device_changes
            fi
        done
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
