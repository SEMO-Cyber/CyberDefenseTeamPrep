#!/bin/bash

# Define backup and log locations
BACKUP_DIR="/etc/BacServices/int-protection"
LOG_FILE="/var/log/int-protection.log"

# Function to detect the interface manager
detect_manager() {
    # Check for netplan (Ubuntu-specific, prioritized if present)
    if [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
        echo "netplan"
    # Check for NetworkManager (nmcli) if it's installed and running
    elif command -v nmcli >/dev/null 2>&1 && (systemctl is-active --quiet NetworkManager || pgrep NetworkManager >/dev/null); then
        echo "NetworkManager"
    # Check for systemd-networkd if config exists and service is active
    elif [ -d /etc/systemd/network ] && (systemctl is-active --quiet systemd-networkd || [ -f /run/systemd/networkd.pid ]); then
        echo "systemd-networkd"
    # Check for ifupdown (or ifupdown-ng on Alpine) via interfaces file
    elif [ -f /etc/network/interfaces ]; then
        echo "ifupdown"
    # Check for netctl (Arch Linux) if config directory exists
    elif [ -d /etc/netctl ]; then
        echo "netctl"
    else
        echo "unknown"
    fi
}

# Detect the interface manager
manager=$(detect_manager)
if [ "$manager" = "unknown" ]; then
    echo "$(date): ERROR: Unknown interface manager detected" >> "$LOG_FILE"
    exit 1
fi

# Set configuration directory and apply command based on the manager
case "$manager" in
    NetworkManager)
        config_dir="/etc/NetworkManager"
        apply_cmd="nmcli connection reload && systemctl restart NetworkManager"
        ;;
    ifupdown)
        config_dir="/etc/network"
        apply_cmd="ifdown -a && ifup -a"
        ;;
    systemd-networkd)
        config_dir="/etc/systemd/network"
        apply_cmd="systemctl restart systemd-networkd"
        ;;
    netctl)
        config_dir="/etc/netctl"
        apply_cmd="for profile in \$(netctl list | grep '^*' | cut -d' ' -f2); do netctl stop \$profile; netctl start \$profile; done"
        ;;
    netplan)
        config_dir="/etc/netplan"
        apply_cmd="netplan apply"
        ;;
esac

# Create backup directory if it doesn’t exist
mkdir -p "$BACKUP_DIR" || {
    echo "$(date): ERROR: Failed to create backup directory $BACKUP_DIR" >> "$LOG_FILE"
    exit 1
}

# Check if backup exists; if not, create it
if [ ! -d "$BACKUP_DIR/config" ]; then
    echo "$(date): Creating initial backup of $config_dir to $BACKUP_DIR/config" >> "$LOG_FILE"
    cp -a "$config_dir" "$BACKUP_DIR/config" || {
        echo "$(date): ERROR: Failed to create backup of $config_dir" >> "$LOG_FILE"
        exit 1
    }
else
    # Compare current config with backup
    diff_output=$(diff -r --brief "$config_dir" "$BACKUP_DIR/config")
    if [ -n "$diff_output" ]; then
        echo "$(date): Changes detected in $config_dir:" >> "$LOG_FILE"
        echo "$diff_output" >> "$LOG_FILE"
        echo "$(date): Reverting to backup" >> "$LOG_FILE"
        
        # Revert by synchronizing backup to config directory
        rsync -a --delete "$BACKUP_DIR/config/" "$config_dir/" || {
            echo "$(date): ERROR: Failed to revert $config_dir to backup" >> "$LOG_FILE"
            exit 1
        }
        
        echo "$(date): Applying configuration" >> "$LOG_FILE"
        eval "$apply_cmd" || {
            echo "$(date): ERROR: Failed to apply configuration with '$apply_cmd'" >> "$LOG_FILE"
            exit 1
        }
        
        echo "$(date): Revert completed" >> "$LOG_FILE"
    fi
fi

exit 0
