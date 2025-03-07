#!/bin/bash

# Exit on errors
set -e

# Backup directory
BACKUP_DIR="/var/backups/network_configs"
mkdir -p "$BACKUP_DIR"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

# Function to detect network management tool
detect_network_manager() {
    if command -v netplan >/dev/null 2>&1 && [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
        echo "netplan"
    elif command -v nmcli >/dev/null 2>&1 && systemctl is-active NetworkManager >/dev/null 2>&1; then
        echo "networkmanager"
    else
        echo "unknown"
    fi
}

# Function to get list of interfaces
get_interfaces() {
    if [ "$NETWORK_MANAGER" = "networkmanager" ]; then
        nmcli -t -f NAME con show | grep -v '^lo$'
    elif [ "$NETWORK_MANAGER" = "netplan" ]; then
        # Extract interface names from Netplan YAML (simplified)
        grep -h "ethernets:" /etc/netplan/*.yaml -A 10 | grep -oP '^\s+\K\w+' | sort -u
    else
        echo "Cannot determine interfaces for unknown manager" >&2
        exit 1
    fi
}

# Function to backup configuration
backup_config() {
    local interface="$1"
    local backup_file="$BACKUP_DIR/$interface.backup"

    if [ "$NETWORK_MANAGER" = "netplan" ]; then
        # Backup all Netplan files (simplified; assumes files cover all interfaces)
        cp /etc/netplan/*.yaml "$BACKUP_DIR/"
        echo "Backed up Netplan config for $interface to $BACKUP_DIR"
    elif [ "$NETWORK_MANAGER" = "networkmanager" ]; then
        nmcli con show "$interface" > "$backup_file"
        echo "Backed up NetworkManager config for $interface to $backup_file"
    fi
}

# Function to check for changes
check_changes() {
    local interface="$1"
    local backup_file="$BACKUP_DIR/$interface.backup"
    local temp_file="/tmp/$interface.current"

    if [ ! -f "$backup_file" ]; then
        echo "No backup found for $interface. Creating initial backup..."
        backup_config "$interface"
        return 0
    fi

    if [ "$NETWORK_MANAGER" = "netplan" ]; then
        # Compare all Netplan files (simplified)
        for config_file in /etc/netplan/*.yaml; do
            backup_copy="$BACKUP_DIR/$(basename "$config_file")"
            if ! cmp -s "$config_file" "$backup_copy"; then
                echo "Changes detected in $config_file"
                return 1
            fi
        done
        echo "No changes detected in Netplan configs for $interface"
        return 0
    elif [ "$NETWORK_MANAGER" = "networkmanager" ]; then
        nmcli con show "$interface" > "$temp_file"
        if ! cmp -s "$temp_file" "$backup_file"; then
            echo "Changes detected in NetworkManager config for $interface"
            rm -f "$temp_file"
            return 1
        fi
        echo "No changes detected in NetworkManager config for $interface"
        rm -f "$temp_file"
        return 0
    fi
}

# Function to restore configuration
restore_config() {
    local interface="$1"
    local backup_file="$BACKUP_DIR/$interface.backup"

    if [ "$NETWORK_MANAGER" = "netplan" ]; then
        # Restore all Netplan files
        cp "$BACKUP_DIR"/*.yaml /etc/netplan/
        netplan apply
        echo "Restored Netplan config and applied changes for $interface"
    elif [ "$NETWORK_MANAGER" = "networkmanager" ]; then
        # Reload backup into NetworkManager (simplified; assumes backup is compatible)
        nmcli con load "$backup_file" 2>/dev/null || nmcli con up "$interface"
        echo "Restored NetworkManager config for $interface"
    fi
}

# Main logic
NETWORK_MANAGER=$(detect_network_manager)
echo "Detected OS: $OS, Network Manager: $NETWORK_MANAGER"

if [ "$NETWORK_MANAGER" = "unknown" ]; then
    echo "Unsupported network management tool detected"
    exit 1
fi

# Set service based on network manager
case "$NETWORK_MANAGER" in
    netplan)
        SERVICE="systemd-networkd"
        ;;
    networkmanager)
        SERVICE="NetworkManager"
        ;;
esac

# Process each interface
for interface in $(get_interfaces); do
    echo "Checking interface: $interface"
    if ! check_changes "$interface"; then
        echo "Restoring configuration for $interface..."
        restore_config "$interface"
        systemctl restart "$SERVICE.service"
    fi
done

echo "Network monitoring complete."
