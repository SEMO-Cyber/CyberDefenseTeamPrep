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
DEBOUNCE_TIME=${DEBOUNCE_TIME:-5}  # Seconds to wait after last event (configurable)
RESTORE_TIMEOUT=${RESTORE_TIMEOUT:-10}  # Seconds to ignore events post-restore (configurable)
RESTORATION_COOLDOWN_TIME=${RESTORATION_COOLDOWN_TIME:-5}  # Seconds for cooldown after restoration (configurable)
PRO_INT_DIR="/etc/pro-int"
PRO_INT_SCRIPT="$PRO_INT_DIR/interface-protection.sh"

# Create directories if they don’t exist
mkdir -p "$BAC_SERVICES_DIR"
mkdir -p "$BACKUP_DIR"
mkdir -p "$PRO_INT_DIR"

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

# Function to set up the script to run on reboot
setup_cronjob() {
    # Copy the script to /etc/pro-int
    cp -p "$0" "$PRO_INT_SCRIPT" || {
        log_message "Failed to copy script to $PRO_INT_SCRIPT"
        echo "Failed to copy script to $PRO_INT_SCRIPT"
        exit 1
    }
    chmod +x "$PRO_INT_SCRIPT"

    # Check if cron is installed, install if not
    if ! command -v crontab > /dev/null; then
        log_message "cron not found, attempting to install..."
        echo "Installing cron..."
        if command -v apt-get > /dev/null; then
            apt-get update && apt-get install -y cron || {
                log_message "Failed to install cron using apt-get. Please install manually."
                echo "Failed to install cron. Please run: sudo apt-get install cron"
                exit 1
            }
        elif command -v dnf > /dev/null; then
            dnf install -y cronie || {
                log_message "Failed to install cronie using dnf. Please install manually."
                echo "Failed to install cronie. Please run: sudo dnf install cronie"
                exit 1
            }
        elif command -v yum > /dev/null; then
            yum install -y cronie || {
                log_message "Failed to install cronie using yum. Please install manually."
                echo "Failed to install cronie. Please run: sudo yum install cronie"
                exit 1
            }
        elif command -v pacman > /dev/null; then
            pacman -S --noconfirm cronie || {
                log_message "Failed to install cronie using pacman. Please install manually."
                echo "Failed to install cronie. Please run: sudo pacman -S cronie"
                exit 1
            }
        elif command -v apk > /dev/null; then
            apk add --no-cache busybox-initscripts cron || {
                log_message "Failed to install cron using apk. Please install manually."
                echo "Failed to install cron. Please run: apk add busybox-initscripts cron"
                exit 1
            }
        else
            log_message "No supported package manager found for cron installation. Please install cron manually."
            echo "No supported package manager found. Please install cron manually for your system."
            exit 1
        fi
        log_message "cron installed successfully."
        echo "cron installed successfully."
    fi

    # Enable and start cron service
    if command -v systemctl > /dev/null; then
        systemctl enable cron > /dev/null 2>&1 || log_message "Failed to enable cron service with systemctl"
        systemctl start cron > /dev/null 2>&1 || log_message "Failed to start cron service with systemctl"
    elif command -v service > /dev/null; then
        service cron start > /dev/null 2>&1 || log_message "Failed to start cron service with service"
    else
        log_message "No systemctl or service command found, skipping cron service start"
    fi

    # Set up cronjob to run on reboot
    (crontab -l 2>/dev/null | grep -v "$PRO_INT_SCRIPT"; echo "@reboot /bin/bash $PRO_INT_SCRIPT start") | crontab - || {
        log_message "Failed to set up cronjob for $PRO_INT_SCRIPT"
        echo "Failed to set up cronjob for $PRO_INT_SCRIPT"
        exit 1
    }
    log_message "Cronjob set up to run $PRO_INT_SCRIPT on reboot"
    echo "Cronjob set up to run $PRO_INT_SCRIPT on reboot"
}

# Handle command-line arguments
case "$1" in
    start)
        check_running
        # Set up cronjob on first start
        if [ ! -f "$PRO_INT_SCRIPT" ]; then
            setup_cronjob
        fi
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
        # Trap to clean up PID and lock files on exit
        trap 'rm -f "$PID_FILE" "$LOCK_FILE"' EXIT
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac

# If not daemon mode, exit after starting
[ "$1" != "daemon" ] && exit 0

# Check and install inotify-tools if not present (fully automated)
if ! command -v inotifywait > /dev/null; then
    log_message "inotifywait not found, attempting to install inotify-tools..."
    echo "Installing inotify-tools..."

    if command -v apt-get > /dev/null; then
        apt-get install -y inotify-tools || {
            log_message "Failed to install inotify-tools using apt-get. Please install manually."
            echo "Failed to install inotify-tools. Please run: sudo apt-get install inotify-tools"
            exit 1
        }
    elif command -v dnf > /dev/null; then
        # Oracle Linux, Fedora, etc.
        if ! dnf repolist | grep -q epel; then
            dnf install -y epel-release || {
                log_message "Failed to install epel-release. Please install manually."
                echo "Failed to install epel-release. Please run: sudo dnf install epel-release"
                exit 1
            }
        fi
        dnf install -y inotify-tools || {
            log_message "Failed to install inotify-tools using dnf. Please install manually."
            echo "Failed to install inotify-tools. Please run: sudo dnf install inotify-tools"
            exit 1
        }
    elif command -v yum > /dev/null; then
        yum install -y inotify-tools || {
            log_message "Failed to install inotify-tools using yum. Please install manually."
            echo "Failed to install inotify-tools. Please run: sudo yum install inotify-tools"
            exit 1
        }
    elif command -v pacman > /dev/null; then
        pacman -S --noconfirm inotify-tools || {
            log_message "Failed to install inotify-tools using pacman. Please install manually."
            echo "Failed to install inotify-tools. Please run: sudo pacman -S inotify-tools"
            exit 1
        }
    elif command -v apk > /dev/null; then
        apk add --no-cache inotify-tools || {
            log_message "Failed to install inotify-tools using apk. Please install manually."
            echo "Failed to install inotify-tools. Please run: apk add inotify-tools"
            exit 1
        }
    else
        log_message "No supported package manager found. Please install inotify-tools manually."
        echo "No supported package manager found. Please install inotify-tools manually."
        exit 1
    fi
    log_message "inotify-tools installed successfully."
    echo "inotify-tools installed successfully."
fi

# Function to determine the NetworkManager plugin
get_nm_plugin() {
    if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
        plugin=$(grep -E "^\s*plugins=" /etc/NetworkManager/NetworkManager.conf | sed 's/.*=//')
        if echo "$plugin" | grep -q "ifcfg-rh"; then
            echo "ifcfg-rh"
        elif echo "$plugin" | grep -q "keyfile"; then
            echo "keyfile"
        else
            echo "keyfile"  # Default to keyfile if not specified
        fi
    else
        echo "keyfile"  # Assume keyfile if config file doesn't exist
    fi
}

# Function to detect all active network managers
detect_managers() {
    local managers=()
    [ -d /etc/netplan ] && ls /etc/netplan/*.yaml >/dev/null 2>&1 && managers+=("netplan")
    if systemctl is-active NetworkManager >/dev/null 2>&1; then
        managers+=("networkmanager")
    fi
    systemctl is-active systemd-networkd >/dev/null 2>&1 && [ -d /etc/systemd/network ] && ls /etc/systemd/network/*.network >/dev/null 2>&1 && managers+=("systemd-networkd")
    [ -f /etc/network/interfaces ] && managers+=("interfaces")
    if [ -d /etc/sysconfig/network-scripts ] && ls /etc/sysconfig/network-scripts/ifcfg-* >/dev/null 2>&1; then
        if ! systemctl is-active NetworkManager >/dev/null 2>&1 || [ "$(get_nm_plugin)" != "ifcfg-rh" ]; then
            managers+=("network-scripts")
        fi
    fi
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
        networkmanager)
            plugin=$(get_nm_plugin)
            if [ "$plugin" = "ifcfg-rh"; then
                echo "/etc/sysconfig/network-scripts"
            else
                echo "/etc/NetworkManager/system-connections"
            fi
            ;;
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
    elif command -v service >/dev/null; then
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

# Backup Configuration with permissions preserved
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
            cp -r -p "$CONFIG_PATH"/* "$MANAGER_BACKUP_DIR/" || {
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
        cp -p "$CONFIG_PATH" "$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")" || {
            log_message "Failed to backup $CONFIG_PATH for $manager"
            exit 1
        }
    fi
    log_message "Backup created for $manager"
}

# Restore a specific file or directory with Lock, permissions preserved, and cooldown
restore_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")
    local MANAGER_BACKUP_DIR="$BACKUP_DIR/$manager"

    if [ ! -e "$CONFIG_PATH" ]; then
        log_message "Configuration path $CONFIG_PATH does not exist for $manager, cannot restore"
        return
    fi

    touch "$LOCK_FILE"
    echo "$(date +%s)" > "$LOCK_FILE"

    if [ "$IS_DIR" = "true" ]; then
        if [ ! -d "$CONFIG_PATH" ]; then
            log_message "Configuration path $CONFIG_PATH is not a directory for $manager, cannot restore"
            rm -f "$LOCK_FILE"
            return
        fi
        # For directories, specific file restoration is handled in monitor_config
        log_message "Directory restoration triggered for $manager (specific files handled in monitoring)"
    else
        local backup_file="$MANAGER_BACKUP_DIR/$(basename "$CONFIG_PATH")"
        if [ -f "$backup_file" ]; then
            cp -p "$backup_file" "$CONFIG_PATH" || {
                log_message "Failed to restore $CONFIG_PATH for $manager"
                rm -f "$LOCK_FILE"
                return
            }
            log_message "Restored $CONFIG_PATH for $manager"
            apply_config "$manager"
            # Wait for cooldown period before removing lock file
            sleep "$RESTORATION_COOLDOWN_TIME"
        else
            log_message "No backup found for $CONFIG_PATH, cannot restore"
        fi
    fi
    rm -f "$LOCK_FILE"
}

# Monitor Configuration Changes with inotifywait and detailed diff logging
monitor_config() {
    local manager="$1"
    local CONFIG_PATH=$(get_config_path "$manager")
    local IS_DIR=$(get_is_dir "$manager")

    if [ ! -e "$CONFIG_PATH" ]; then
        log_message "Configuration path $CONFIG_PATH does not exist for $manager, cannot monitor"
        return
    fi

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
                    continue
                fi
            fi
            log_message "Change detected in $manager: $event $file"
            # Debounce
            last_event_time=$(date +%s)
            while [ $(date +%s) -lt $(($last_event_time + $DEBOUNCE_TIME)) ]; do
                inotifywait -q -t 1 "$CONFIG_PATH" || break
            done
            # Handle events
            case "$event" in
                CREATE)
                    relative_path="${full_path#$CONFIG_PATH/}"
                    backup_file="$BACKUP_DIR/$manager/$relative_path"
                    if [ -f "$backup_file" ]; then
                        touch "$LOCK_FILE"
                        echo "$(date +%s)" > "$LOCK_FILE"
                        cp -p "$backup_file" "$full_path" || log_message "Failed to restore $full_path"
                        sleep "$RESTORATION_COOLDOWN_TIME"
                        rm -f "$LOCK_FILE"
                        log_message "Restored $full_path for $manager"
                    else
                        log_message "New file $full_path detected without backup, deleting"
                        rm -f "$full_path"
                    fi
                    ;;
                MODIFY)
                    relative_path="${full_path#$CONFIG_PATH/}"
                    backup_file="$BACKUP_DIR/$manager/$relative_path"
                    if [ -f "$backup_file" ] && [ -f "$full_path" ]; then
                        # Check if the file matches the backup to avoid self-triggered loops
                        if cmp -s "$full_path" "$backup_file"; then
                            log_message "No actual content change in $full_path, skipping restoration"
                            continue
                        fi
                        diff_output=$(diff "$full_path" "$backup_file" 2>/dev/null || true)
                        if [ -n "$diff_output" ]; then
                            log_message "Differences detected in $full_path before restoration:"
                            while IFS= read -r line; do
                                log_message "  $line"
                            done <<< "$diff_output"
                        fi
                        touch "$LOCK_FILE"
                        echo "$(date +%s)" > "$LOCK_FILE"
                        cp -p "$backup_file" "$full_path" || log_message "Failed to restore $full_path"
                        sleep "$RESTORATION_COOLDOWN_TIME"
                        rm -f "$LOCK_FILE"
                        log_message "Restored $full_path for $manager"
                    else
                        log_message "No backup or file missing for $full_path, cannot restore"
                    fi
                    ;;
                DELETE)
                    relative_path="${full_path#$CONFIG_PATH/}"
                    backup_file="$BACKUP_DIR/$manager/$relative_path"
                    if [ -f "$backup_file" ]; then
                        touch "$LOCK_FILE"
                        echo "$(date +%s)" > "$LOCK_FILE"
                        cp -p "$backup_file" "$full_path" || log_message "Failed to restore $full_path"
                        sleep "$RESTORATION_COOLDOWN_TIME"
                        rm -f "$LOCK_FILE"
                        log_message "Restored $full_path for $manager"
                    else
                        log_message "No backup found for deleted file $full_path, cannot restore"
                    fi
                    ;;
            esac
            apply_config "$manager"
        done
    else
        inotifywait -m -e modify,delete "$CONFIG_PATH" | while read -r line; do
            log_message "Change detected in $manager: $line"
            if [ -f "$LOCK_FILE" ]; then
                restore_time=$(cat "$LOCK_FILE")
                current_time=$(date +%s)
                if [ $((current_time - restore_time)) -lt "$RESTORE_TIMEOUT" ]; then
                    continue
                fi
            fi
            local backup_file="$BACKUP_DIR/$manager/$(basename "$CONFIG_PATH")"
            if [ -f "$backup_file" ] && [ -f "$CONFIG_PATH" ]; then
                if cmp -s "$CONFIG_PATH" "$backup_file"; then
                    log_message "No actual content change in $CONFIG_PATH, skipping restoration"
                    continue
                fi
                diff_output=$(diff "$CONFIG_PATH" "$backup_file" 2>/dev/null || true)
                if [ -n "$diff_output" ]; then
                    log_message "Differences detected in $CONFIG_PATH before restoration:"
                    while IFS= read -r line; do
                        log_message "  $line"
                    done <<< "$diff_output"
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
