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

# Set environment variables for D-Bus (needed for nmcli in cron)
if [ -z "$DBUS_SYSTEM_BUS_ADDRESS" ]; then
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/var/run/dbus/system_bus_socket
fi

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
            nmcli -t -f DEVICE con show | grep -v '^lo$'
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
            cp /etc/netplan/*.yaml "$BACKUP_DIR/" 2>> "$LOG_FILE" || log_message "Failed to backup Netplan configs"
            log_message "Backup created for Netplan configurations"
            ;;
        networkmanager)
            cp /etc/NetworkManager/system-connections/*.nmconnection "$BACKUP_DIR/" 2>> "$LOG_FILE" || log_message "Failed to backup NetworkManager connection files"
            log_message "Backup created for NetworkManager connections"
            ;;
        systemd-networkd)
            cp /etc/systemd/network/*.network "$BACKUP_DIR/" 2>> "$LOG_FILE" || log_message "Failed to backup systemd-networkd configs"
            log_message "Backup created for systemd-networkd configurations"
            ;;
        interfaces)
            cp /etc/network/interfaces "$BACKUP_DIR/interfaces.backup" 2>> "$LOG_FILE" || log_message "Failed to backup /etc/network/interfaces"
            log_message "Backup created for /etc/network/interfaces"
            ;;
        network-scripts)
            cp /etc/sysconfig/network-scripts/ifcfg-$interface "$BACKUP_DIR/ifcfg-$interface.backup" 2>> "$LOG_FILE" || log_message "Failed to backup ifcfg-$interface"
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
                    log_message "No backup found for $config_file"
                    return 1
                fi
                if ! cmp -s "$config_file" "$backup_copy"; then
                    log_message "Changes detected in $config_file. Differences:"
                    diff -u "$backup_copy" "$config_file" >> "$LOG_FILE" 2>&1
                    return 1
                fi
            done
            log_message "No changes detected in Netplan configs"
            return 0
            ;;
        networkmanager)
            for backup_file in "$BACKUP_DIR"/*.nmconnection; do
                local connection_name=$(basename "$backup_file" .nmconnection)
                local current_file="/etc/NetworkManager/system-connections/$connection_name.nmconnection"
                if [ ! -f "$current_file" ]; then
                    log_message "Connection file $current_file not found"
                    return 1
                fi
                if ! cmp -s "$current_file" "$backup_file"; then
                    log_message "Changes detected in connection $connection_name. Differences:"
                    diff -u "$backup_file" "$current_file" >> "$LOG_FILE" 2>&1
                    return 1
                fi
            done
            for current_file in /etc/NetworkManager/system-connections/*.nmconnection; do
                local connection_name=$(basename "$current_file" .nmconnection)
                if [ ! -f "$BACKUP_DIR/$connection_name.nmconnection" ]; then
                    log_message "New connection detected: $connection_name"
                    return 1
                fi
            done
            log_message "No changes detected in NetworkManager connections"
            return 0
            ;;
        systemd-networkd)
            for config_file in /etc/systemd/network/*.network; do
                backup_copy="$BACKUP_DIR/$(basename "$config_file")"
                if [ ! -f "$backup_copy" ]; then
                    log_message "No backup found for $config_file"
                    return 1
                fi
                if ! cmp -s "$config_file" "$backup_copy"; then
                    log_message "Changes detected in $config_file. Differences:"
                    diff -u "$backup_copy" "$config_file" >> "$LOG_FILE" 2>&1
                    return 1
                fi
            done
            log_message "No changes detected in systemd-networkd configs"
            return 0
            ;;
        interfaces)
            local backup_file="$BACKUP_DIR/interfaces.backup"
            if [ ! -f "$backup_file" ]; then
                log_message "No backup found for /etc/network/interfaces"
                return 1
            fi
            if ! cmp -s /etc/network/interfaces "$backup_file"; then
                log_message "Changes detected in /etc/network/interfaces. Differences:"
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
                log_message "No backup found for $config_file"
                return 1
            fi
            if ! cmp -s "$config_file" "$backup_file"; then
                log_message "Changes detected in $config_file. Differences:"
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
            cp "$BACKUP_DIR"/*.yaml /etc/netplan/ 2>> "$LOG_FILE" || log_message "Failed to restore Netplan configs"
            netplan apply 2>> "$LOG_FILE" || log_message "Failed to apply Netplan configs"
            log_message "Configuration restored for Netplan"
            ;;
        networkmanager)
            rm -f /etc/NetworkManager/system-connections/*.nmconnection 2>> "$LOG_FILE"
            cp "$BACKUP_DIR"/*.nmconnection /etc/NetworkManager/system-connections/ 2>> "$LOG_FILE" || log_message "Failed to restore NetworkManager connection files"
            nmcli con reload 2>> "$LOG_FILE" || log_message "Failed to reload NetworkManager connections"
            for connection in $(nmcli -t -f NAME con show); do
                nmcli con up "$connection" 2>> "$LOG_FILE" || log_message "Failed to bring up $connection"
            done
            log_message "Configuration restored for NetworkManager"
            ;;
        systemd-networkd)
            cp "$BACKUP_DIR"/*.network /etc/systemd/network/ 2>> "$LOG_FILE" || log_message "Failed to restore systemd-networkd configs"
            systemctl restart systemd-networkd 2>> "$LOG_FILE" || log_message "Failed to restart systemd-networkd"
            log_message "Configuration restored for systemd-networkd"
            ;;
        interfaces)
            cp "$BACKUP_DIR/interfaces.backup" /etc/network/interfaces 2>> "$LOG_FILE" || log_message "Failed to restore /etc/network/interfaces"
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart networking 2>> "$LOG_FILE" || log_message "Failed to restart networking service"
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service networking restart 2>> "$LOG_FILE" || log_message "Failed to restart networking service"
            else
                log_message "Cannot restart networking service"
            fi
            log_message "Configuration restored for /etc/network/interfaces"
            ;;
        network-scripts)
            cp "$BACKUP_DIR/ifcfg-$interface.backup" /etc/sysconfig/network-scripts/ifcfg-$interface 2>> "$LOG_FILE" || log_message "Failed to restore ifcfg-$interface"
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart network 2>> "$LOG_FILE" || log_message "Failed to restart network service"
            elif command -v service >/dev/null 2>&1; then
                service network restart 2>> "$LOG_FILE" || log_message "Failed to restart network service"
            else
                log_message "Cannot restart network service"
            fi
            log_message "Configuration restored for interface $interface (/etc/sysconfig/network-scripts/)"
            ;;
    esac
}

# Function to ensure backups exist
ensure_backups() {
    local interfaces=($(get_interfaces))
    case "$NETWORK_MANAGER" in
        netplan)
            if ! ls "$BACKUP_DIR"/*.yaml >/dev/null 2>&1; then
                log_message "No Netplan backups found. Creating backups..."
                backup_config ""
            fi
            ;;
        networkmanager)
            if ! ls "$BACKUP_DIR"/*.nmconnection >/dev/null 2>&1; then
                log_message "No NetworkManager backups found. Creating backups..."
                backup_config ""
            fi
            ;;
        systemd-networkd)
            if ! ls "$BACKUP_DIR"/*.network >/dev/null 2>&1; then
                log_message "No systemd-networkd backups found. Creating backups..."
                backup_config ""
            fi
            ;;
        interfaces)
            if [ ! -f "$BACKUP_DIR/interfaces.backup" ]; then
                log_message "No /etc/network/interfaces backup found. Creating backup..."
                backup_config ""
            fi
            ;;
        network-scripts)
            for interface in "${interfaces[@]}"; do
                if [ ! -f "$BACKUP_DIR/ifcfg-$interface.backup" ]; then
                    log_message "No backup found for $interface. Creating backup..."
                    backup_config "$interface"
                fi
            done
            ;;
    esac
}

# Function to backup all interfaces
backup_all() {
    case "$NETWORK_MANAGER" in
        netplan|networkmanager|systemd-networkd|interfaces)
            backup_config ""
            ;;
        network-scripts)
            local interfaces=($(get_interfaces))
            for interface in "${interfaces[@]}"; do
                backup_config "$interface"
            done
            ;;
    esac
}

# Main logic
if [ $# -eq 0 ]; then
    ACTION="monitor"
else
    ACTION="$1"
fi

NETWORK_MANAGER=$(detect_network_manager)
if [ "$NETWORK_MANAGER" = "unknown" ]; then
    log_message "Unsupported network management tool detected"
    exit 1
fi

case "$ACTION" in
    reset)
        log_message "Resetting backups"
        rm -rf "$BACKUP_DIR"/*
        backup_all
        log_message "Backup reset completed"
        ;;
    backup)
        backup_all
        log_message "Backups created"
        ;;
    check)
        ensure_backups
        changes_detected=0
        case "$NETWORK_MANAGER" in
            netplan|networkmanager|systemd-networkd|interfaces)
                if ! check_changes ""; then
                    changes_detected=1
                fi
                ;;
            network-scripts)
                for interface in $(get_interfaces); do
                    if ! check_changes "$interface"; then
                        changes_detected=1
                    fi
                done
                ;;
        esac
        if [ $changes_detected -eq 1 ]; then
            log_message "Changes detected in configurations"
        else
            log_message "No changes detected in configurations"
        fi
        ;;
    monitor)
        log_message "Starting monitoring cycle"
        ensure_backups
        case "$NETWORK_MANAGER" in
            netplan|networkmanager|systemd-networkd|interfaces)
                if ! check_changes ""; then
                    log_message "Restoring configuration"
                    restore_config ""
                fi
                ;;
            network-scripts)
                for interface in $(get_interfaces); do
                    if ! check_changes "$interface"; then
                        log_message "Restoring configuration for interface $interface"
                        restore_config "$interface"
                    fi
                done
                ;;
        esac
        log_message "Monitoring cycle completed"
        ;;
    --setup-cron)
        PRO_INT_DIR="/etc/pro-int"
        mkdir -p "$PRO_INT_DIR"
        SCRIPT_NAME=$(basename "$0")
        cp "$0" "$PRO_INT_DIR/$SCRIPT_NAME"
        chmod +x "$PRO_INT_DIR/$SCRIPT_NAME"
        log_message "Script copied to $PRO_INT_DIR/$SCRIPT_NAME"
        CRON_COMMAND="* * * * * $PRO_INT_DIR/$SCRIPT_NAME monitor"
        (crontab -l 2>/dev/null; echo "$CRON_COMMAND") | crontab -
        log_message "Cronjob created to run $PRO_INT_DIR/$SCRIPT_NAME monitor every minute"
        ;;
    *)
        echo "Usage: $0 [backup|check|monitor|reset|--setup-cron]"
        exit 1
        ;;
esac
