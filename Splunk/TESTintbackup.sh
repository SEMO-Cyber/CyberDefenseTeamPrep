#!/bin/bash

# Exit on errors
set -e

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Backup directory
BACKUP_DIR="/etc/BacService/"
mkdir -p "$BACKUP_DIR"

# Log file
LOG_FILE="/var/log/interface-protection.log"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Log script start
log_message "Script started"

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
        # List all active NetworkManager connections, excluding loopback
        nmcli -t -f NAME con show | grep -v '^lo$'
    elif [ "$NETWORK_MANAGER" = "netplan" ]; then
        # Extract interface names from Netplan YAML files (simplified)
        grep -h "ethernets:" /etc/netplan/*.yaml -A 10 | grep -oP '^\s+\K\w+' | sort -u
    else
        echo "Cannot determine interfaces for unknown manager" >&2
        exit 1
    fi
}

# Function to backup configuration
backup_config() {
    local interface="$1"
    local backup_profile="$BACKUP_DIR/$interface.profile.backup"
    local backup_state="$BACKUP_DIR/$interface.state.backup"

    if [ "$NETWORK_MANAGER" = "netplan" ]; then
        # Backup all Netplan configuration files
        cp /etc/netplan/*.yaml "$BACKUP_DIR/"
        echo "Backed up Netplan config for $interface to $BACKUP_DIR"
        log_message "Backup created for interface $interface (Netplan)"
    elif [ "$NETWORK_MANAGER" = "networkmanager" ]; then
        # Backup persistent connection profile
        nmcli con show "$interface" > "$backup_profile"
        # Backup current runtime state of the device
        nmcli device show "$interface" > "$backup_state"
        echo "Backed up NetworkManager profile and state for $interface to $BACKUP_DIR"
        log_message "Backup created for interface $interface (NetworkManager)"
    fi
}

# Function to check for changes
check_changes() {
    local interface="$1"
    local backup_profile="$BACKUP_DIR/$interface.profile.backup"
    local backup_state="$BACKUP_DIR/$interface.state.backup"
    local temp_profile="/tmp/$interface.profile.current"
    local temp_state="/tmp/$interface.state.current"

    # If no backup exists, create one and assume no changes yet
    if [ ! -f "$backup_profile" ] || [ ! -f "$backup_state" ]; then
        echo "No backup found for $interface. Creating initial backup..."
        log_message "No backup found for $interface. Creating initial backup..."
        backup_config "$interface"
        return 0
    fi

    if [ "$NETWORK_MANAGER" = "netplan" ]; then
        # Compare all Netplan configuration files
        for config_file in /etc/netplan/*.yaml; do
            backup_copy="$BACKUP_DIR/$(basename "$config_file")"
            if ! cmp -s "$config_file" "$backup_copy"; then
                echo "Changes detected in $config_file"
                log_message "Changes detected for interface $interface (Netplan)"
                return 1  # Changes found
            fi
        done
        echo "No changes detected in Netplan configs for $interface"
        log_message "No changes detected for interface $interface (Netplan)"
        return 0  # No changes
    elif [ "$NETWORK_MANAGER" = "networkmanager" ]; then
        # Capture current profile and runtime state
        nmcli con show "$interface" > "$temp_profile"
        nmcli device show "$interface" > "$temp_state"

        # Compare both persistent profile and runtime state
        if ! cmp -s "$temp_profile" "$backup_profile" || ! cmp -s "$temp_state" "$backup_state"; then
            echo "Changes detected in profile or state for $interface"
            log_message "Changes detected for interface $interface (NetworkManager)"
            rm -f "$temp_profile" "$temp_state"
            return 1  # Changes found
        fi
        echo "No changes detected in NetworkManager config for $interface"
        log_message "No changes detected for interface $interface (NetworkManager)"
        rm -f "$temp_profile" "$temp_state"
        return 0  # No changes
    fi
}

# Function to restore configuration
restore_config() {
    local interface="$1"
    local backup_profile="$BACKUP_DIR/$interface.profile.backup"

    if [ "$NETWORK_MANAGER" = "netplan" ]; then
        # Restore all Netplan configuration files and apply them
        cp "$BACKUP_DIR"/*.yaml /etc/netplan/
        netplan apply
        echo "Restored Netplan config and applied changes for $interface"
        log_message "Configuration restored for interface $interface (Netplan)"
    elif [ "$NETWORK_MANAGER" = "networkmanager" ]; then
        # Reload the original connection profile
        nmcli con load "$backup_profile" 2>/dev/null || true
        # Force reapplication by bringing connection down and up
        nmcli con down "$interface" 2>/dev/null || true
        nmcli con up "$interface"
        echo "Restored NetworkManager config and reapplied connection for $interface"
        log_message "Configuration restored for interface $interface (NetworkManager)"
    fi
}

# Main logic
NETWORK_MANAGER=$(detect_network_manager)
echo "Detected OS: $OS, Network Manager: $NETWORK_MANAGER"
log_message "Detected OS: $OS, Network Manager: $NETWORK_MANAGER"

# Exit if network manager is unsupported
if [ "$NETWORK_MANAGER" = "unknown" ]; then
    echo "Unsupported network management tool detected"
    log_message "Unsupported network management tool detected"
    exit 1
fi

# Set service to restart based on network manager
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
    log_message "Checking interface: $interface"
    if ! check_changes "$interface"; then
        echo "Restoring configuration for $interface..."
        log_message "Restoring configuration for interface $interface"
        restore_config "$interface"
        systemctl restart "$SERVICE.service"
    fi
done

echo "Network monitoring complete."
log_message "Script finished"
