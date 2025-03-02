#!/bin/bash
#
#  A script that automatically backs up interface configurations, sets them as immutable, 
#  and creates a service to check the integrity every minute.
#  If the integrity is invalid, it pulls from the backup.
#
#  Heavily AI generated with slight tweaks from me. No way I'm doing this one by hand.
#
#  Samuel Brucker 2024-2025
#

# Configuration variables
BACKUP_DIR="/etc/BacService/"
CONFIG_FILE="network-config.json"
SERVICE_FILE="network-config-restore.service"
TIMER_FILE="network-config-restore.timer"
LOCK_FILE="/var/lock/network-config.lock"

# Function to handle logging
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message" >&2
}

# Function to check prerequisites
check_prerequisites() {
    local missing=()
    
    # Check for required commands
    for cmd in jq systemctl chattr; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_message "ERROR" "Missing required commands: ${missing[*]}"
        return 1
    fi
    
    # Check for root privileges
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "This script must be run as root"
        log_message "ERROR" "Please use: sudo $0"
        return 1
    fi
    
    # Check and create backup directory
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR" || {
            log_message "ERROR" "Failed to create backup directory: $BACKUP_DIR"
            return 1
        }
    fi
    
    # Verify backup directory permissions
    if [ ! -w "$BACKUP_DIR" ]; then
        log_message "ERROR" "Backup directory not writable: $BACKUP_DIR"
        return 1
    fi
    
    return 0
}

# Function to install systemd files
install_systemd_files() {
    local systemd_dir="/etc/systemd/system"
    
    # Create service file
    cat > "$systemd_dir/$SERVICE_FILE" << EOF
[Unit]
Description=Network Configuration Restore Service
After=network.target
Before=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "source /etc/profile && %p restore"
User=root
Restart=on-failure
RestartSec=30
StartLimitIntervalSec=300
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF
    
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to create service file: $systemd_dir/$SERVICE_FILE"
        return 1
    fi
    
    # Create timer file
    cat > "$systemd_dir/$TIMER_FILE" << EOF
[Unit]
Description=Run network configuration check periodically

[Timer]
OnUnitActiveSec=1min
AccuracySec=1s
RandomizedDelaySec=5s
Unit=network-config-restore.service

[Install]
WantedBy=timers.target
EOF
    
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to create timer file: $systemd_dir/$TIMER_FILE"
        return 1
    fi
    
    # Reload systemd daemon
    if ! systemctl daemon-reload; then
        log_message "ERROR" "Failed to reload systemd daemon"
        return 1
    fi
    
    # Enable and start the timer
    if ! systemctl enable --now "$TIMER_FILE"; then
        log_message "ERROR" "Failed to enable and start timer"
        return 1
    fi
    
    log_message "INFO" "Successfully installed and enabled systemd service and timer"
    return 0
}

# Function to backup network configurations
backup_config() {
    local config_data="{}"
    local temp_file
    
    # Create temporary file for atomic write
    temp_file="$(mktemp --tmpdir="$BACKUP_DIR")"
    trap 'rm -f "$temp_file"' EXIT
    
    # Check for Debian/Ubuntu network configurations
    if [ -d "/etc/network/interfaces" ] || [ -d "/etc/netplan" ]; then
        local debian_config="{}"
        
        # Backup traditional network configuration
        if [ -f "/etc/network/interfaces" ]; then
            debian_config=$(jq --arg intf "$(cat /etc/network/interfaces)" '.interfaces = $intf' <<< "$debian_config")
        fi
        
        # Backup Netplan configurations (Ubuntu)
        if [ -d "/etc/netplan" ]; then
            local netplan_config="{}"
            for file in /etc/netplan/*.yaml; do
                if [ -f "$file" ]; then
                    local content=$(cat "$file")
                    netplan_config=$(jq --arg key "$(basename "$file")" --arg val "$content" '. + {($key): $val}' <<< "$netplan_config")
                fi
            done
            debian_config=$(jq ".netplan = $netplan_config" <<< "$debian_config")
        fi
        
        config_data=$(jq ".debian = $debian_config" <<< "$config_data")
    fi
    
    # Check for RedHat-based configurations
    if [ -d "/etc/sysconfig/network-scripts" ]; then
        local ifcfg_files=("/etc/sysconfig/network-scripts/ifcfg-*")
        local rh_config="{}"
        
        for file in "${ifcfg_files[@]}"; do
            if [ -f "$file" ]; then
                local iface=$(basename "$file" | cut -d- -f2-)
                local content=$(cat "$file")
                rh_config=$(jq --arg key "$iface" --arg val "$content" '. + {($key): $val}' <<< "$rh_config")
            fi
        done
        
        config_data=$(jq ". + {redhat: $rh_config}" <<< "$config_data")
    fi
    
    # Check for NetworkManager configurations
    if command -v nmcli &> /dev/null; then
        local nm_config=$(nmcli -g NAME,UUID,DEVICE,TYPE connection show)
        config_data=$(jq --arg nm "$nm_config" '. + {nmcli: $nm}' <<< "$config_data")
    fi
    
    # Check for systemd-networkd configurations
    if [ -d "/etc/systemd/network" ]; then
        local systemd_config="{}"
        for file in /etc/systemd/network/*.network; do
            if [ -f "$file" ]; then
                local content=$(cat "$file")
                systemd_config=$(jq --arg key "$(basename "$file")" --arg val "$content" '. + {($key): $val}' <<< "$systemd_config")
            fi
        done
        config_data=$(jq ". + {systemd: $systemd_config}" <<< "$config_data")
    fi
    
    # Write to temporary file first
    echo "$config_data" > "$temp_file"
    
    # Atomic move to final location
    mv "$temp_file" "$BACKUP_DIR/$CONFIG_FILE"
    
    log_message "INFO" "Successfully created backup in $BACKUP_DIR/$CONFIG_FILE"
}

# Function to restore network configurations
restore_config() {
    # Acquire lock to prevent concurrent restorations
    if ! flock -n 200; then
        log_message "ERROR" "Another restoration is in progress"
        return 1
    fi
    
    local config_data=$(jq -r '.' "$BACKUP_DIR/$CONFIG_FILE")
    
    # Restore Debian/Ubuntu configurations
    if jq -e '.debian' <<< "$config_data" > /dev/null; then
        # Restore traditional network configuration
        if jq -e '.debian.interfaces' <<< "$config_data" > /dev/null; then
            echo "$(jq -r '.debian.interfaces' <<< "$config_data")" > /etc/network/interfaces
            chattr +i /etc/network/interfaces
            systemctl restart networking
            log_message "INFO" "Restored /etc/network/interfaces"
        fi
        
        # Restore Netplan configurations (Ubuntu)
        if jq -e '.debian.netplan' <<< "$config_data" > /dev/null; then
            local netplan_configs=$(jq -r '.debian.netplan' <<< "$config_data")
            for file in $(echo "$netplan_configs" | jq -r 'keys[]'); do
                local content=$(jq -r ".debian.netplan.$file" <<< "$config_data")
                echo "$content" > "/etc/netplan/$file"
                chattr +i "/etc/netplan/$file"
                log_message "INFO" "Restored /etc/netplan/$file"
            done
            netplan apply
        fi
    fi
    
    # Restore RedHat configurations
    if jq -e '.redhat' <<< "$config_data" > /dev/null; then
        for iface in $(jq -r 'keys[]' <<< "$(jq -r '.redhat' <<< "$config_data")"); do
            local content=$(jq -r ".redhat.$iface" <<< "$config_data")
            echo "$content" > "/etc/sysconfig/network-scripts/ifcfg-$iface"
            chattr +i "/etc/sysconfig/network-scripts/ifcfg-$iface"
            log_message "INFO" "Restored /etc/sysconfig/network-scripts/ifcfg-$iface"
        done
        systemctl restart network
    fi
    
    # Restore NetworkManager configurations
    if jq -e '.nmcli' <<< "$config_data" > /dev/null; then
        local connections=$(jq -r '.nmcli' <<< "$config_data")
        while IFS= read -r line; do
            if [[ $line =~ NAME=([^ ]+) ]]; then
                local conn_name="${BASH_REMATCH[1]}"
                nmcli connection reload "$conn_name"
                log_message "INFO" "Reloaded NetworkManager connection: $conn_name"
            fi
        done <<< "$connections"
    fi
    
    # Restore systemd-networkd configurations
    if jq -e '.systemd' <<< "$config_data" > /dev/null; then
        local configs=$(jq -r '.systemd' <<< "$config_data")
        for file in $(echo "$configs" | jq -r 'keys[]'); do
            local content=$(jq -r ".systemd.$file" <<< "$config_data")
            echo "$content" > "/etc/systemd/network/$file"
            chattr +i "/etc/systemd/network/$file"
            log_message "INFO" "Restored /etc/systemd/network/$file"
        done
        systemctl restart systemd-networkd
    fi
    
    # Release lock
    flock -u 200
}

# Function to check configuration integrity
check_integrity() {
    local current_config
    local backup_config
    
    # Create temporary files for comparison
    local temp_current=$(mktemp)
    local temp_backup=$(mktemp)
    trap 'rm -f "$temp_current" "$temp_backup"' EXIT
    
    # Get current configuration
    backup_config > "$temp_current"
    cat "$BACKUP_DIR/$CONFIG_FILE" > "$temp_backup"
    
    # Compare configurations
    if ! diff -q "$temp_current" "$temp_backup" > /dev/null; then
        log_message "WARNING" "Configuration mismatch detected"
        log_message "INFO" "Restoring configurations from backup"
        restore_config
    fi
}

# Main execution
if ! check_prerequisites; then
    exit 1
fi

# Set up lock file descriptor
exec 200>$LOCK_FILE

# Perform all operations automatically
log_message "INFO" "Starting automatic configuration management..."
log_message "INFO" "Installing systemd files..."
install_systemd_files

log_message "INFO" "Creating initial backup..."
backup_config

log_message "INFO" "Checking configuration integrity..."
check_integrity

log_message "INFO" "All operations completed successfully. System is now monitoring configurations automatically."

exit 0
