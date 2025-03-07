#!/bin/bash

# Exit on errors
set -e

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Backup directory and log file
BAC_SERVICES_DIR="/etc/BacServices"
BACKUP_DIR="$BAC_SERVICES_DIR/interface-protection"
LOG_FILE="/var/log/interface-protection.log"

# Create directories if they don’t exist
mkdir -p "$BAC_SERVICES_DIR"
mkdir -p "$BACKUP_DIR"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Detect network management tool
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

# Function to get list of interfaces
get_interfaces() {
    case "$NETWORK_MANAGER" in
        netplan)
            grep -h "ethernets:" /etc/netplan/*.yaml -A 10 | grep -oP '^\s+\K\w+' | sort -u
            ;;
        networkmanager)
            nmcli -t -f NAME con show | grep -v '^lo$'
            ;;
        systemd-networkd)
            networkctl list --no-legend | awk '{if ($NF == "configured") print $2}'
            ;;
        interfaces)
            grep -oP '^\s*iface\s+\K\w+' /etc/network/interfaces | grep -v 'lo'
            ;;
        network-scripts)
            ls /etc/sysconfig/network-scripts/ifcfg-* | sed 's/.*ifcfg-//'
            ;;
        *)
            echo "Cannot determine interfaces" >&2
            exit 1
            ;;
    esac
}

# Function to backup configuration
backup_config() {
    local interface="$1"
    case "$NETWORK_MANAGER" in
        netplan)
            cp /etc/netplan/*.yaml "$BACKUP_DIR/"
            log_message "Backup created for interface $interface (Netplan)"
            ;;
        networkmanager)
            nmcli con show "$interface" | grep -vE 'connection.timestamp|connection.uuid|GENERAL.STATE|IP4.ADDRESS|IP6.ADDRESS' > "$BACKUP_DIR/$interface.profile.backup"
            log_message "Backup created for interface $interface (NetworkManager)"
            ;;
        systemd-networkd)
            cp /etc/systemd/network/*.network "$BACKUP_DIR/"
            log_message "Backup created for interface $interface (systemd-networkd)"
            ;;
        interfaces)
            cp /etc/network/interfaces "$BACKUP_DIR/interfaces.backup"
            log_message "Backup created for interface $interface (/etc/network/interfaces)"
            ;;
        network-scripts)
            cp /etc/sysconfig/network-scripts/ifcfg-$interface "$BACKUP_DIR/ifcfg-$interface.backup"
            log_message "Backup created for interface $interface (/etc/sysconfig/network-scripts/)"
            ;;
    esac
}

# Function to check for changes and log them
check_changes() {
    local interface="$1"
    case "$NETWORK_MANAGER" in
        netplan)
            for config_file in /etc/netplan/*.yaml; do
                backup_copy="$BACKUP_DIR/$(basename "$config_file")"
                if [ ! -f "$backup_copy" ]; then
                    log_message "No backup found for $config_file. Creating initial backup..."
                    backup_config "$interface"
                    return 0
                fi
                if ! cmp -s "$config_file" "$backup_copy"; then
                    log_message "Changes detected in $config_file. The following lines show the differences:"
                    diff -u "$backup_copy" "$config_file" >> "$LOG_FILE" 2>&1
                    return 1
                fi
            done
            log_message "No changes detected in Netplan configs for $interface"
            return 0
            ;;
        networkmanager)
            local backup_profile="$BACKUP_DIR/$interface.profile.backup"
            local temp_profile="/tmp/$interface.profile.current"
            if [ ! -f "$backup_profile" ]; then
                log_message "No backup found for $interface. Creating initial backup..."
                backup_config "$interface"
                return 0
            fi
            nmcli con show "$interface" | grep -vE 'connection.timestamp|connection.uuid|GENERAL.STATE|IP4.ADDRESS|IP6.ADDRESS' > "$temp_profile"
            if ! cmp -s "$temp_profile" "$backup_profile"; then
                log_message "Changes detected in profile for interface $interface. The following lines show the differences:"
                diff -u "$backup_profile" "$temp_profile" >> "$LOG_FILE" 2>&1
                rm -f "$temp_profile"
                return 1
            fi
            rm -f "$temp_profile"
            log_message "No changes detected in NetworkManager config for $interface"
            return 0
            ;;
        systemd-networkd)
            for config_file in /etc/systemd/network/*.network; do
                backup_copy="$BACKUP_DIR/$(basename "$config_file")"
                if [ ! -f "$backup_copy" ]; then
                    log_message "No backup found for $config_file. Creating initial backup..."
                    backup_config "$interface"
                    return 0
                fi
                if ! cmp -s "$config_file" "$backup_copy"; then
                    log_message "Changes detected in $config_file. The following lines show the differences:"
                    diff -u "$backup_copy" "$config_file" >> "$LOG_FILE" 2>&1
                    return 1
                fi
            done
            log_message "No changes detected in systemd-networkd configs for $interface"
            return 0
            ;;
        interfaces)
            local backup_file="$BACKUP_DIR/interfaces.backup"
            if [ ! -f "$backup_file" ]; then
                log_message "No backup found for /etc/network/interfaces. Creating initial backup..."
                backup_config "$interface"
                return 0
            fi
            if ! cmp -s /etc/network/interfaces "$backup_file"; then
                log_message "Changes detected in /etc/network/interfaces. The following lines show the differences:"
                diff -u "$backup_file" /etc/network/interfaces >> "$LOG_FILE" 2>&1
                return 1
            fi
            log_message "No changes detected in /etc/network/interfaces"
            return 0
            ;;
        network-scripts)
            local config_file="/etc/sysconfig/network-scripts/ifcfg-$interface"
            local backup_file="$BACKUP_DIR/ifcfg-$interface.backup"
            if [ ! -f "$backup_file" ]; then
                log_message "No backup found for $config_file. Creating initial backup..."
                backup_config "$interface"
                return 0
            fi
            if ! cmp -s "$config_file" "$backup_file"; then
                log_message "Changes detected in $config_file. The following lines show the differences:"
                diff -u "$backup_file" "$config_file" >> "$LOG_FILE" 2>&1
                return 1
            fi
            log_message "No changes detected in $config_file"
            return 0
            ;;
    esac
}

# Function to restore configuration
restore_config() {
    local interface="$1"
    case "$NETWORK_MANAGER" in
        netplan)
            cp "$BACKUP_DIR"/*.yaml /etc/netplan/
            netplan apply
            log_message "Configuration restored for interface $interface (Netplan)"
            ;;
        networkmanager)
            nmcli con load "$BACKUP_DIR/$interface.profile.backup"
            nmcli con down "$interface" 2>/dev/null || true
            nmcli con up "$interface"
            log_message "Configuration restored for interface $interface (NetworkManager)"
            ;;
        systemd-networkd)
            cp "$BACKUP_DIR"/*.network /etc/systemd/network/
            systemctl restart systemd-networkd
            log_message "Configuration restored for interface $interface (systemd-networkd)"
            ;;
        interfaces)
            cp "$BACKUP_DIR/interfaces.backup" /etc/network/interfaces
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart networking || log_message "Failed to restart networking service"
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service networking restart || log_message "Failed to restart networking service"
            else
                log_message "Cannot restart networking service"
            fi
            log_message "Configuration restored for interface $interface (/etc/network/interfaces)"
            ;;
        network-scripts)
            cp "$BACKUP_DIR/ifcfg-$interface.backup" /etc/sysconfig/network-scripts/ifcfg-$interface
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart network || log_message "Failed to restart network service"
            elif command -v service >/dev/null 2>&1; then
                service network restart || log_message "Failed to restart network service"
            else
                log_message "Cannot restart network service"
            fi
            log_message "Configuration restored for interface $interface (/etc/sysconfig/network-scripts/)"
            ;;
    esac
}

# Function to setup cronjob
setup_cronjob() {
    # Path to the script
    SCRIPT_PATH=$(realpath "$0")
    # Cronjob command
    CRON_COMMAND="* * * * * $SCRIPT_PATH monitor"
    # Add cronjob to root’s crontab
    (crontab -l 2>/dev/null; echo "$CRON_COMMAND") | crontab -
    log_message "Cronjob setup to run $SCRIPT_PATH monitor every minute"
}

# Main logic
if [ "$1" = "reset" ]; then
    NETWORK_MANAGER=$(detect_network_manager)
    if [ "$NETWORK_MANAGER" = "unknown" ]; then
        log_message "Unsupported network management tool detected"
        exit 1
    fi
    log_message "Resetting backups"
    rm -rf "$BACKUP_DIR"/*
    for interface in $(get_interfaces); do
        backup_config "$interface"
    done
    log_message "Backup reset completed"
    exit 0
elif [ "$1" = "monitor" ]; then
    NETWORK_MANAGER=$(detect_network_manager)
    if [ "$NETWORK_MANAGER" = "unknown" ]; then
        log_message "Unsupported network management tool detected"
        exit 1
    fi
    for i in {1..3}; do
        log_message "Starting monitoring cycle $i"
        for interface in $(get_interfaces); do
            if ! check_changes "$interface"; then
                log_message "Restoring configuration for interface $interface"
                restore_config "$interface"
            fi
        done
        if [ "$i" -lt 3 ]; then
            sleep 20
        fi
    done
    log_message "Monitoring cycles completed"
    exit 0
elif [ "$1" = "--setup-cron" ]; then
    setup_cronjob
    exit 0
else
    echo "Usage: $0 {reset|monitor|--setup-cron}"
    exit 1
fi
