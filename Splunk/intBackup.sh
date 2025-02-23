#!/bin/bash
#
#  A script that backs up interface configurations, sets them as immutable, and creates a service to check the integrity every minute. 
#  If the integrity is invalid, it pulls from the backup.
#
#  Heavily AI generated with slight tweaks from me. No way I'm doing this one by hand.
#
#  Samuel Brucker 2024-2025


# Configuration variables
BACKUP_DIR="/etc/BacService/"
CONFIG_FILE="network-config.json"
SERVICE_FILE="network-config-restore.service"
TIMER_FILE="network-config-restore.timer"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    echo "Please use: sudo $0"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to backup network configurations
backup_config() {
    local config_data="{}"
    
    # Check for Debian/Ubuntu network configurations
    if [ -d "/etc/network/interfaces" ] || [ -d "/etc/netplan" ]; then
        # Debian/Ubuntu systems
        local debian_config="{}"
        
        # Backup traditional network configuration
        if [ -f "/etc/network/interfaces" ]; then
            debian_config=$(jq ".interfaces = \"$input\"" <<< "$debian_config" <<< "$(cat /etc/network/interfaces)")
        fi
        
        # Backup Netplan configurations (Ubuntu)
        if [ -d "/etc/netplan" ]; then
            local netplan_config="{}"
            for file in /etc/netplan/*.yaml; do
                if [ -f "$file" ]; then
                    local content=$(cat "$file")
                    netplan_config=$(jq ". + {\"$(basename $file)\": \"$content\"}" <<< "$netplan_config")
                fi
            done
            debian_config=$(jq ".netplan = $netplan_config" <<< "$debian_config")
        fi
        
        config_data=$(jq ".debian = $debian_config" <<< "$config_data")
    fi
    
    # Check for RedHat-based configurations
    if [ -d "/etc/sysconfig/network-scripts" ]; then
        # Get all ifcfg-* files
        local ifcfg_files=("/etc/sysconfig/network-scripts/ifcfg-*")
        local rh_config="{}"
        
        for file in "${ifcfg_files[@]}"; do
            if [ -f "$file" ]; then
                local iface=$(basename "$file" | cut -d- -f2-)
                local content=$(cat "$file")
                rh_config=$(jq ". + {\"$iface\": \"$content\"}" <<< "$rh_config")
            fi
        done
        
        config_data=$(jq ". + {redhat: $rh_config}" <<< "$config_data")
    fi
    
    # Check for NetworkManager configurations
    if command -v nmcli &> /dev/null; then
        # Use connection show instead of show for better compatibility
        local nm_config=$(nmcli -g NAME,UUID,DEVICE,TYPE connection show)
        config_data=$(jq ". + {nmcli: \"$nm_config\"}" <<< "$config_data")
    fi
    
    # Check for systemd-networkd configurations
    if [ -d "/etc/systemd/network" ]; then
        local systemd_config="{}"
        for file in /etc/systemd/network/*.network; do
            if [ -f "$file" ]; then
                local content=$(cat "$file")
                systemd_config=$(jq ". + {\"$(basename $file)\": \"$content\"}" <<< "$systemd_config")
            fi
        done
        config_data=$(jq ". + {systemd: $systemd_config}" <<< "$config_data")
    fi
    
    # Save the configuration
    echo "$config_data" > "$BACKUP_DIR/$CONFIG_FILE"
}

# Function to restore network configurations
restore_config() {
    local config_data=$(jq -r '.' "$BACKUP_DIR/$CONFIG_FILE")
    
    # Restore Debian/Ubuntu configurations
    if jq -e '.debian' <<< "$config_data" > /dev/null; then
        # Restore traditional network configuration
        if jq -e '.debian.interfaces' <<< "$config_data" > /dev/null; then
            echo "$(jq -r '.debian.interfaces' <<< "$config_data")" > /etc/network/interfaces
            chattr +i /etc/network/interfaces
            systemctl restart networking
        fi
        
        # Restore Netplan configurations (Ubuntu)
        if jq -e '.debian.netplan' <<< "$config_data" > /dev/null; then
            local netplan_configs=$(jq -r '.debian.netplan' <<< "$config_data")
            for file in $(echo "$netplan_configs" | jq -r 'keys[]'); do
                local content=$(jq -r ".debian.netplan.$file" <<< "$config_data")
                echo "$content" > "/etc/netplan/$file"
                chattr +i "/etc/netplan/$file"
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
        done
        systemctl restart network
    fi
    
    # Restore NetworkManager configurations
    if jq -e '.nmcli' <<< "$config_data" > /dev/null; then
        local connections=$(jq -r '.nmcli' <<< "$config_data")
        for conn in $(echo "$connections" | grep -oP '(?<=NAME=)[^ ]+'); do
            nmcli connection reload "$conn"
        done
    fi
    
    # Restore systemd-networkd configurations
    if jq -e '.systemd' <<< "$config_data" > /dev/null; then
        local configs=$(jq -r '.systemd' <<< "$config_data")
        for file in $(echo "$configs" | jq -r 'keys[]'); do
            local content=$(jq -r ".systemd.$file" <<< "$config_data")
            echo "$content" > "/etc/systemd/network/$file"
            chattr +i "/etc/systemd/network/$file"
        done
        systemctl restart systemd-networkd
    fi
}

# Create systemd service file
cat > "/etc/systemd/system/$SERVICE_FILE" << EOF
[Unit]
Description=Network Configuration Restore Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "source /etc/profile && $0 restore"
User=root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer file
cat > "/etc/systemd/system/$TIMER_FILE" << EOF
[Unit]
Description=Run network configuration check periodically

[Timer]
OnUnitActiveSec=1h
AccuracySec=1min
Unit=network-config-restore.service

[Install]
WantedBy=timers.target
EOF

# Initial backup
backup_config

# Enable and start the service and timer
systemctl daemon-reload
systemctl enable --now "$SERVICE_FILE"
systemctl enable --now "$TIMER_FILE"
