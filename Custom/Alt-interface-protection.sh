#!/bin/bash

# Define directories and log file
BAC_SERVICES_DIR="/etc/BacServices"
BACKUP_DIR="$BAC_SERVICES_DIR/interface-protection"
LOG_FILE="/var/log/interface-protection.log"
DEBOUNCE_TIME=5  # seconds to wait after last event before restoring
LOCK_FILE="/tmp/interface-protection.lock"
PID_FILE="/var/run/interface-protection.pid"

# Function to log messages with timestamp to file
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
            # PID file exists but process is not running, clean up
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
        # Continue with script execution
        ;;
    stop)
        stop_script
        ;;
    status)
        status_script
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Create directories if they don’t exist
mkdir -p "$BAC_SERVICES_DIR"
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

# Check if the script is already running
check_running

# Daemonize the script
if [ "$1" = "start" ]; then
    # Redirect all output to the log file and detach
    exec setsid "$0" daemon >> "$LOG_FILE" 2>&1 &
    exit 0
fi

# The script continues here in daemon mode
if [ "$1" != "daemon" ]; then
    echo "This script should only be run via start/stop/status commands"
    exit 1
fi

# Save the PID of the daemonized process
echo $$ > "$PID_FILE"
log_message "Script started with PID $$"

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
            log_message "Service $service not found with systemctl"
        fi
    elif command -v service >/dev/null 2>&1; then
        if [ -f "/etc/init.d/$service" ]; then
            service "$service" restart || log_message "Failed to restart $service with service"
        else
            log_message "Service $service not found in /etc/init.d"
        fi
    else
        log_message "Cannot restart service: no systemctl or service command found"
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
            for device in $(nmcli -t -f GENERAL.DEVICE device show | cut -d':' -f2 | grep -v lo); do
                nmcli device reapply "$device" || log_message "Warning: Failed to reapply configuration for $device"
            done
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

    if [ -z "$CONFIG_PATH" ] || [ ! -e "$CONFIG_PATH" ]; then
        log_message "Configuration path for $manager does not exist: $CONFIG_PATH"
        return 1
    fi

    mkdir -p "$MANAGER_BACKUP_DIR"
    if [ "$IS_DIR" = "true" ]; then
        rsync -a --delete "$CONFIG_PATH/" "$MANAGER_BACKUP_DIR/" || {
            log_message "Failed to backup $CONFIG_PATH for $manager"
            exit 1
        }
    else
        cp "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" || {
            log_message "Failed to backup $CONFIG_PATH for $manager"
            exit 1
        }
    fi
    log_message "Backup created for $manager"
}

# Restore Configuration
restore_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    if [ -z "$CONFIG_PATH" ] || [ ! -e "$CONFIG_PATH" ]; then
        log_message "Configuration path for $manager does not exist: $CONFIG_PATH"
        return 1
    fi

    touch "$LOCK_FILE"
    if [ "$IS_DIR" = "true" ]; then
        rsync -a --delete "$MANAGER_BACKUP_DIR/" "$CONFIG_PATH/" || {
            log_message "Failed to restore $CONFIG_PATH for $manager"
            rm -f "$LOCK_FILE"
            return 1
        }
    else
        cp "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" "$CONFIG_PATH" || {
            log_message "Failed to restore $CONFIG_PATH for $manager"
            rm -f "$LOCK_FILE"
            return 1
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

    if [ "$IS_DIR" = "true" ]; then
        while true; do
            inotifywait -r -e modify,create,delete --timeout "$DEBOUNCE_TIME" "$CONFIG_PATH" > /dev/null 2>&1
            if [ $? -eq 2 ] && [ ! -f "$LOCK_FILE" ]; then  # Timeout occurred, no lock
                log_message "Change detected in $manager after debounce"
                restore_config "$manager"
            fi
        done
    else
        inotifywait -m -e modify,delete "$CONFIG_PATH" | while read -r line; do
            if [ ! -f "$LOCK_FILE" ]; then
                log_message "Change detected in $manager: $line"
                restore_config "$manager"
            fi
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

# Keep the script running
wait
