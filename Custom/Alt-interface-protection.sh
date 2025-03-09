#!/bin/bash

# Exit on errors
set -e

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Define directories and files
BAC_SERVICES_DIR="/etc/BacServices"
BACKUP_DIR="$BAC_SERVICES_DIR/interface-protection"
LOG_FILE="/var/log/interface-protection.log"
LOCK_FILE="/tmp/interface_protection_lock"
PID_FILE="/var/run/interface-protection.pid"
DEBOUNCE_TIME=5  # seconds to wait after last event
RESTORE_TIMEOUT=10  # seconds to ignore events post-restore

# Create directories if they don’t exist
mkdir -p "$BAC_SERVICES_DIR"
mkdir -p "$BACKUP_DIR"

# Function to log messages to file (no console output)
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check if the script is already running
check_running() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Script is already running with PID $pid"
            exit 1
        else
            rm -f "$PID_FILE"
        fi
    fi
}

# Function to stop the script
stop_script() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid"
            log_message "Script stopped (PID: $pid)"
            echo "Script stopped (PID: $pid)"
            rm -f "$PID_FILE"
            rm -f "$LOCK_FILE"
        else
            echo "No running process found for PID $pid"
            rm -f "$PID_FILE"
        fi
    else
        echo "Script is not running (no PID file found)"
    fi
    exit 0
}

# Function to check the status of the script
status_script() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Script is running with PID $pid"
        else
            echo "Script is not running (stale PID file found)"
            rm -f "$PID_FILE"
        fi
    else
        echo "Script is not running"
    fi
    exit 0
}

# Handle command-line arguments
case "$1" in
    start)
        check_running
        # Start the daemon in the background
        exec setsid "$0" daemon >> "$LOG_FILE" 2>&1 &
        echo "Started monitoring (PID: $!). Check $LOG_FILE for details."
        exit 0
        ;;
    stop)
        stop_script
        ;;
    status)
        status_script
        ;;
    daemon)
        # This is the daemon mode
        echo $$ > "$PID_FILE"
        log_message "Script started with PID $$"
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac

# If not daemon mode, exit after starting
[ "$1" != "daemon" ] && exit 0

# Check if inotifywait is installed, install if necessary
if ! command -v inotifywait > /dev/null; then
    log_message "inotifywait not found, attempting to install inotify-tools..."
    if command -v apt-get > /dev/null; then
        apt-get update
        apt-get install -y inotify-tools
    elif command -v dnf > /dev/null; then
        dnf install -y inotify-tools
    elif command -v yum > /dev/null; then
        yum install -y inotify-tools
    elif command -v pacman > /dev/null; then
        pacman -S --noconfirm inotify-tools
    elif command -v zypper > /dev/null; then
        zypper install -y inotify-tools
    elif command -v apk > /dev/null; then
        apk add --no-cache inotify-tools
    else
        log_message "No supported package manager found. Please install inotify-tools manually."
        exit 1
    fi
    if ! command -v inotifywait > /dev/null; then
        log_message "Failed to install inotify-tools. Please install it manually."
        exit 1
    fi
    log_message "inotify-tools installed successfully."
fi

# Function to detect all active network managers
detect_managers() {
    local managers=()
    [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1 && managers+=("netplan")
    systemctl is-active NetworkManager >/dev/null 2>&1 && managers+=("networkmanager")
    systemctl is-active systemd-networkd >/dev/null 2>&1 && [ -d /etc/systemd/network ] && ls /etc/systemd/network/*.network >/dev/null 2>&1 && managers+=("systemd-networkd")
    [ -f /etc/network/interfaces ] && managers+=("interfaces")
    [ -d /etc/sysconfig/network-scripts ] && ls /etc/sysconfig/network-scripts/ifcfg-* >/dev/null 2>&1 && managers+=("network-scripts")
    if [ ${#managers[@]} -eq 0 ]; then
        echo "unknown"
    else
        echo "${managers[@]}"
    fi
}

# Function to get the configuration path for a manager
get_config_path() {
    case "$1" in
        netplan) echo "/etc/netplan" ;;
        networkmanager) echo "/etc/NetworkManager/system-connections" ;;
        systemd-networkd) echo "/etc/systemd/network" ;;
        interfaces) echo "/etc/network/interfaces" ;;
        network-scripts) echo "/etc/sysconfig/network-scripts" ;;
        *) echo "" ;;
    esac
}

# Function to check if the configuration is a directory
get_is_dir() {
    case "$1" in
        netplan|networkmanager|systemd-networkd|network-scripts) echo true ;;
        interfaces) echo false ;;
        *) echo false ;;
    esac
}

# Function to restart a service in a distribution-agnostic way
restart_service() {
    local service="$1"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-units --type=service | grep -q "$service.service"; then
            systemctl restart "$service" || log_message "Failed to restart $service with systemctl"
        else
            log_message "Service $service not found with systemctl, skipping restart"
        fi
    elif command -v service >/dev/null 2>&1; then
        if [ -f "/etc/init.d/$service" ]; then
            service "$service" restart || log_message "Failed to restart $service with service"
        else
            log_message "Service $service not found in /etc/init.d, skipping restart"
        fi
    else
        log_message "No systemctl or service command found, skipping restart"
    fi
}

# Function to apply configurations based on the manager
apply_config() {
    local manager="$1"
    case "$manager" in
        netplan)
            netplan apply || log_message "Failed to apply netplan"
            ;;
        networkmanager)
            restart_service "NetworkManager"
            if command -v nmcli >/dev/null 2>&1; then
                for device in $(nmcli -t -f GENERAL.DEVICE device show | cut -d':' -f2 | grep -v lo); do
                    nmcli dev reapply "$device" || log_message "Warning: Failed to reapply configuration for $device"
                done
            fi
            ;;
        systemd-networkd)
            restart_service "systemd-networkd"
            ;;
        interfaces)
            restart_service "networking"
            ;;
        network-scripts)
            restart_service "network"
            ;;
    esac
}

# Backup Configuration
backup_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    if [ ! -e "$CONFIG_PATH" ]; then
        log_message "Configuration path $CONFIG_PATH does not exist for $manager, skipping"
        return
    fi

    rm -rf "$MANAGER_BACKUP_DIR"
    mkdir -p "$MANAGER_BACKUP_DIR"
    if [ "$IS_DIR" = "true" ]; then
        if [ ! -d "$CONFIG_PATH" ]; then
            log_message "Configuration path $CONFIG_PATH is not a directory for $manager, skipping"
            return
        fi
        if [ "$(ls -A "$CONFIG_PATH")" ]; then
            cp -r "$CONFIG_PATH"/* "$MANAGER_BACKUP_DIR/" || {
                log_message "Failed to backup $CONFIG_PATH for $manager"
                exit 1
            }
        else
            log_message "Configuration directory $CONFIG_PATH is empty for $manager, no files to backup"
        fi
    else
        if [ ! -f "$CONFIG_PATH" ]; then
            log_message "Configuration file $CONFIG_PATH does not exist for $manager, skipping"
            return
        fi
        cp "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" || {
            log_message "Failed to backup $CONFIG_PATH for $manager"
            exit 1
        }
    fi
    log_message "Backup created for $manager"
}

# Restore a specific file or directory with Lock
restore_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    if [ ! -e "$CONFIG_PATH" ]; then
        log_message "Configuration path $CONFIG_PATH does not exist for $manager, cannot restore"
        return
    fi
    }

    touch "$LOCK_FILE"
    echo "$(date +%s)" > "$LOCK_FILE"

    if [ "$IS_DIR" = "true" ]; then
        if [ ! -d "$CONFIG_PATH" ]; then
            log_message "Configuration path $CONFIG_PATH is not a directory for $manager, cannot restore"
            rm -f "$LOCK_FILE"
            return
        fi
        # For directories, we'll handle file-specific restoration in monitor_config
        log_message "Directory restoration triggered for $manager (specific files handled in monitoring)"
    else
        cp "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" "$CONFIG_PATH" || {
            log_message "Failed to restore $CONFIG_PATH for $manager"
            rm -f "$LOCK_FILE"
            return
        }
    fi
    log_message "Configuration restored for $manager"
    apply_config "$manager"
    rm -f "$LOCK_FILE"
}

# Monitor Configuration Changes with inotifywait
monitor_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")

    if [ ! -e "$CONFIG_PATH" ]; then
        log_message "Configuration path $CONFIG_PATH does not exist for $manager, cannot monitor"
        return
    }

    if [ "$IS_DIR" = "true" ]; then
        if [ ! -d "$CONFIG_PATH" ]; then
            log_message "Configuration path $CONFIG_PATH is not a directory for $manager, cannot monitor"
            return
        fi
        inotifywait -m -r -e modify,create,delete "$CONFIG_PATH" | while read -r directory event file; do
            full_path="$directory$file"
            if [ -f "$LOCK_FILE" ]; then
                restore_time=$(cat "$LOCK_FILE")
                current_time=$(date +%s)
                if [ $((current_time - restore_time)) -lt "$RESTORE_TIMEOUT" ]; then
                    log_message "Ignoring event due to recent restore: $event $file"
                    continue
                fi
            fi
            log_message "Change detected in $manager: $event $file"
            # Debounce
            last_event_time=$(date +%s)
            while [ $(date +%s) -lt $(($last_event_time + $DEBOUNCE_TIME)) ]; do
                inotifywait -q -t 1 "$CONFIG_PATH" || break
            done
            # Restore only the affected file
            if [ -n "$file" ] && [ -e "$full_path" ]; then
                relative_path="${full_path#$CONFIG_PATH/}"
                backup_file="$BACKUP_DIR/$manager/$relative_path"
                if [ -f "$backup_file" ]; then
                    touch "$LOCK_FILE"
                    cp "$backup_file" "$full_path" || log_message "Failed to restore $full_path"
                    rm -f "$LOCK_FILE"
                    log_message "Restored $full_path for $manager"
                    apply_config "$manager"
                else
                    log_message "No backup found for $full_path"
                fi
            else
                log_message "Skipping invalid event or file: $event $file"
            fi
        done
    else
        inotifywait -m -e modify "$CONFIG_PATH" | while read -r line; do
            log_message "Change detected in $manager: $line"
            if [ -f "$LOCK_FILE" ]; then
                restore_time=$(cat "$LOCK_FILE")
                current_time=$(date +%s)
                if [ $((current_time - restore_time)) -lt "$RESTORE_TIMEOUT" ]; then
                    log_message "Ignoring event due to recent restore"
                    continue
                fi
            fi
            restore_config "$manager"
        done
    fi
}

# Main Logic
managers=($(detect_managers))

if [ "${managers[0]}" = "unknown" ]; then
    log_message "No active network managers detected, cannot proceed"
    exit 1
fi

# Backup and monitor all detected managers
for manager in "${managers[@]}"; do
    log_message "Detected active manager: $manager"
    backup_config "$manager"
    monitor_config "$manager" &
done

log_message "Started monitoring for all detected managers: ${managers[*]}"

# Keep script running
wait
