# **Backup configuration**
backup_config() {
    local interface="$1"
    case "$NETWORK_MANAGER" in
        networkmanager)
            # Backup the full .nmconnection files for restoration
            cp /etc/NetworkManager/system-connections/*.nmconnection "$BACKUP_DIR/" 2>> "$LOG_FILE" || {
                log_message "Failed to backup NetworkManager connection files"
                return 1
            }
            
            # Backup specific stable fields for change detection
            for conn in $(nmcli -t -f NAME con show); do
                local backup_file="$BACKUP_DIR/$conn.fields.backup"
                nmcli -f connection.id,connection.type,connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns con show "$conn" > "$backup_file" 2>> "$LOG_FILE" || {
                    log_message "Failed to backup fields for $conn"
                    continue
                }
                # Ensure proper permissions
                chmod 600 "$backup_file" 2>> "$LOG_FILE" || log_message "Failed to set permissions on $backup_file"
            done
            log_message "Backup created for NetworkManager connections"
            ;;
    esac
}

# **Check for changes and log them**
check_changes() {
    local interface="$1"
    case "$NETWORK_MANAGER" in
        networkmanager)
            local changes_detected=0
            local active_connections=$(nmcli -t -f NAME con show)
            
            # Check for deleted connections
            for backup_file in "$BACKUP_DIR"/*.fields.backup; do
                local conn=$(basename "$backup_file" .fields.backup)
                if ! echo "$active_connections" | grep -q "^$conn$"; then
                    log_message "Connection $conn has been deleted"
                    changes_detected=1
                fi
            done
            
            # Check for modified connections
            for conn in $active_connections; do
                local backup_fields="$BACKUP_DIR/$conn.fields.backup"
                local temp_fields="/tmp/$conn.fields.current"
                
                if [ ! -f "$backup_fields" ]; then
                    log_message "No backup found for connection $conn"
                    changes_detected=1
                    continue
                fi
                
                nmcli -f connection.id,connection.type,connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns con show "$conn" > "$temp_fields" 2>> "$LOG_FILE"
                if [ $? -ne 0 ]; then
                    log_message "Failed to get current fields for $conn (connection may not exist)"
                    rm -f "$temp_fields"
                    changes_detected=1
                    continue
                fi
                
                if ! cmp -s "$temp_fields" "$backup_fields"; then
                    log_message "Changes detected in connection $conn. Differences:"
                    diff -u "$backup_fields" "$temp_fields" >> "$LOG_FILE" 2>&1
                    changes_detected=1
                fi
                
                rm -f "$temp_fields"
            done
            
            # Check for new connections
            for current_file in /etc/NetworkManager/system-connections/*.nmconnection; do
                [ -f "$current_file" ] || continue
                local connection_name=$(basename "$current_file" .nmconnection)
                if [ ! -f "$BACKUP_DIR/$connection_name.nmconnection" ]; then
                    log_message "New connection detected: $connection_name"
                    changes_detected=1
                fi
            done
            
            if [ $changes_detected -eq 0 ]; then
                log_message "No changes detected in NetworkManager connections"
                return 0
            else
                return 1
            fi
            ;;
    esac
}

# **Restore configuration**
restore_config() {
    local interface="$1"
    case "$NETWORK_MANAGER" in
        networkmanager)
            # Remove all existing .nmconnection files to ensure a clean state
            rm -f /etc/NetworkManager/system-connections/*.nmconnection 2>> "$LOG_FILE" || {
                log_message "Failed to clear existing NetworkManager connections"
                return 1
            }
            
            # Copy backup .nmconnection files to the system directory
            cp "$BACKUP_DIR"/*.nmconnection /etc/NetworkManager/system-connections/ 2>> "$LOG_FILE" || {
                log_message "Failed to restore NetworkManager connection files"
                return 1
            }
            
            # Ensure proper permissions
            chmod 600 /etc/NetworkManager/system-connections/*.nmconnection 2>> "$LOG_FILE" || {
                log_message "Failed to set permissions on restored connections"
                return 1
            }
            
            # Reload NetworkManager to recognize the new configuration files
            nmcli connection reload 2>> "$LOG_FILE" || {
                log_message "Failed to reload NetworkManager connections"
                return 1
            }
            
            # Bring up all connections to ensure they are active
            for connection in $(nmcli -t -f NAME con show); do
                nmcli con up "$connection" 2>> "$LOG_FILE" || {
                    log_message "Failed to bring up $connection"
                    continue
                }
            done
            
            log_message "Configuration restored for NetworkManager"
            return 0
            ;;
    esac
}
