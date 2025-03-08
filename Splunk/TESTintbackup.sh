#!/bin/bash

# Constants
BACKUP_DIR="/etc/BacServices/int-protection"
LOG_FILE="/var/log/int-protection.log"

# Create backup directories
mkdir -p "/etc/BacServices"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Initialize logging
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Function to detect interface manager
detect_interface_manager() {
    if command -v nmcli &> /dev/null; then
        echo "NetworkManager"
    elif [ -d /etc/netplan ]; then
        echo "netplan"
    elif [ -d /etc/systemd/network ]; then
        echo "systemd-networkd"
    else
        echo "unknown"
    fi
}

# Function to create backups
create_backup() {
    local manager="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    case $manager in
        NetworkManager)
            cp -r /etc/NetworkManager/system-connections "$BACKUP_DIR/$timestamp_nm_backup"
            ;;
        netplan)
            cp -r /etc/netplan "$BACKUP_DIR/$timestamp_netplan_backup"
            ;;
        systemd-networkd)
            cp -r /etc/systemd/network "$BACKUP_DIR/$timestamp_systemd_backup"
            ;;
    esac
    
    echo "$(date) - Created backup for $manager" >> "$LOG_FILE"
}

# Function to detect changes
detect_changes() {
    local manager="$1"
    local current_hash=""
    local backup_hash=""
    
    case $manager in
        NetworkManager)
            current_hash=$(find /etc/NetworkManager/system-connections -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
            backup_hash=$(find "$BACKUP_DIR" -name "*_nm_backup" -type d | sort | tail -n1 | xargs -I{} find {} -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
            ;;
        netplan)
            current_hash=$(find /etc/netplan -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
            backup_hash=$(find "$BACKUP_DIR" -name "*_netplan_backup" -type d | sort | tail -n1 | xargs -I{} find {} -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
            ;;
        systemd-networkd)
            current_hash=$(find /etc/systemd/network -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
            backup_hash=$(find "$BACKUP_DIR" -name "*_systemd_backup" -type d | sort | tail -n1 | xargs -I{} find {} -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
            ;;
    esac
    
    if [ "$current_hash" != "$backup_hash" ]; then
        echo "$(date) - Detected changes in $manager configuration" >> "$LOG_FILE"
        return 0
    fi
    return 1
}

# Function to revert changes
revert_changes() {
    local manager="$1"
    local latest_backup=$(find "$BACKUP_DIR" -name "*_${manager,,}_backup" -type d | sort | tail -n1)
    
    case $manager in
        NetworkManager)
            rm -rf /etc/NetworkManager/system-connections
            cp -r "$latest_backup" /etc/NetworkManager/system-connections
            systemctl restart NetworkManager
            ;;
        netplan)
            rm -rf /etc/netplan
            cp -r "$latest_backup" /etc/netplan
            netplan apply
            ;;
        systemd-networkd)
            rm -rf /etc/systemd/network
            cp -r "$latest_backup" /etc/systemd/network
            systemctl restart systemd-networkd
            ;;
    esac
    
    echo "$(date) - Reverted $manager configuration to backup" >> "$LOG_FILE"
}

# Main function
main() {
    local manager=$(detect_interface_manager)
    create_backup "$manager"
    
    while true; do
        if detect_changes "$manager"; then
            echo "$(date) - Attempting to revert unauthorized changes..." >> "$LOG_FILE"
            revert_changes "$manager"
            
            # Log specific changes
            diff -ru "$latest_backup" /etc/NetworkManager/system-connections >> "$LOG_FILE" 2>&1
            
            echo "$(date) - Changes reverted successfully" >> "$LOG_FILE"
        fi
        
        sleep 60 # Check every minute
    done
}

main
