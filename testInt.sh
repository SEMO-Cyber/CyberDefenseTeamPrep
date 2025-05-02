#!/bin/bash

# Script to protect network configurations by monitoring and restoring changes
# Runs as a daemon or via command-line options

# Configuration
LOG_FILE="/var/log/interface-protection.log"
BACKUP_DIR="/etc/pro-int/backups"
PRO_INT_SCRIPT="/etc/pro-int/interface-protection.sh"
PID_FILE="/var/run/interface-protection.pid"

# Ensure necessary directories exist
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR" "$(dirname "$PRO_INT_SCRIPT")"

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Detect network configuration managers
detect_managers() {
    local managers=()
    [ -d "/etc/netplan" ] && managers+=("netplan")
    [ -d "/etc/network" ] && managers+=("network")
    [ -f "/etc/sysconfig/network-scripts" ] && managers+=("network-scripts")
    echo "${managers[@]}"
}

# Backup configuration files or directories
backup_config() {
    local manager="$1"
    local src_dir backup_dir
    case "$manager" in
        netplan)
            src_dir="/etc/netplan"
            ;;
        network)
            src_dir="/etc/network"
            ;;
        network-scripts)
            src_dir="/etc/sysconfig/network-scripts"
            ;;
        *)
            log_message "Unknown manager: $manager"
            return 1
            ;;
    esac
    backup_dir="$BACKUP_DIR/$manager"
    mkdir -p "$backup_dir"
    cp -r -p "$src_dir"/* "$backup_dir/" 2>/dev/null || {
        log_message "Failed to backup $manager configurations"
        return 1
    }
    log_message "Backed up $manager configurations to $backup_dir"
}

# Restore configuration from backup
restore_config() {
    local full_path="$1"
    local is_dir="$2"
    local manager="$3"
    local backup_file="$BACKUP_DIR/$manager/$(basename "$full_path")"
    if [ "$is_dir" = "true" ]; then
        # Directories are handled by file events in monitor_config
        log_message "Directory event triggered for $full_path"
    elif [ -f "$backup_file" ]; then
        mkdir -p "$(dirname "$full_path")"
        cp -p "$backup_file" "$full_path" || log_message "Failed to restore $full_path"
        log_message "Restored $full_path from backup"
    else
        log_message "No backup found for $full_path"
    fi
}

# Monitor configuration directory for changes
monitor_config() {
    local manager="$1"
    local watch_dir
    case "$manager" in
        netplan)
            watch_dir="/etc/netplan"
            ;;
        network)
            watch_dir="/etc/network"
            ;;
        network-scripts)
            watch_dir="/etc/sysconfig/network-scripts"
            ;;
        *)
            log_message "Cannot monitor unknown manager: $manager"
            return 1
            ;;
    esac
    log_message "Starting monitoring for $manager at $watch_dir"
    inotifywait -m -r -e CREATE -e MODIFY -e DELETE "$watch_dir" 2>/dev/null | while read -r dir event file; do
        local full_path="$dir$file"
        local backup_file="$BACKUP_DIR/$manager/$file"
        case "$event" in
            CREATE*)
                log_message "CREATE event on $full_path"
                if [ -f "$backup_file" ]; then
                    mkdir -p "$(dirname "$full_path")"
                    cp -p "$backup_file" "$full_path" || log_message "Failed to restore $full_path"
                    log_message "Restored $full_path over created file"
                else
                    rm -f "$full_path"
                    log_message "Removed $full_path (no backup exists)"
                fi
                ;;
            MODIFY*)
                log_message "MODIFY event on $full_path"
                if [ -f "$backup_file" ] && [ -f "$full_path" ]; then
                    local backup_hash=$(sha256sum "$backup_file" | cut -d' ' -f1)
                    local current_hash=$(sha256sum "$full_path" | cut -d' ' -f1)
                    if [ "$backup_hash" != "$current_hash" ]; then
                        mkdir -p "$(dirname "$full_path")"
                        cp -p "$backup_file" "$full_path" || log_message "Failed to restore $full_path"
                        log_message "Restored $full_path after modification"
                    fi
                fi
                ;;
            DELETE*)
                log_message "DELETE event on $full_path"
                if [ -f "$backup_file" ]; then
                    mkdir -p "$(dirname "$full_path")"
                    cp -p "$backup_file" "$full_path" || log_message "Failed to restore $full_path"
                    log_message "Restored $full_path after deletion"
                fi
                ;;
        esac
    done
}

# Set up correct sources.list for Debian or Ubuntu
set_sources_list() {
    if ! command -v lsb_release > /dev/null; then
        log_message "lsb_release not found, attempting to install..."
        apt-get update && apt-get install -y lsb-release || {
            log_message "Failed to install lsb-release"
            return 1
        }
    fi
    local distributor=$(lsb_release -is)
    local codename=$(lsb_release -cs)
    if [ "$distributor" = "Ubuntu" ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null
        log_message "Backed up sources.list to /etc/apt/sources.list.bak"
        cat <<EOF > /etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ $codename main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $codename-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ $codename-security main restricted universe multiverse
EOF
        log_message "Set Ubuntu sources for $codename"
    elif [ "$distributor" = "Debian" ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null
        log_message "Backed up sources.list to /etc/apt/sources.list.bak"
        cat <<EOF > /etc/apt/sources.list
deb http://deb.debian.org/debian/ $codename main
deb http://deb.debian.org/debian/ $codename-updates main
deb http://security.debian.org/debian-security $codename-security main
EOF
        log_message "Set Debian sources for $codename"
    else
        log_message "Unsupported distribution: $distributor"
        return 1
    fi
    apt-get update || {
        log_message "Failed to update package lists"
        return 1
    }
}

# Install dependencies
install_dependencies() {
    if command -v apt-get > /dev/null; then
        set_sources_list || log_message "Proceeding without setting sources.list"
        apt-get install -y inotify-tools || {
            log_message "Failed to install inotify-tools with apt-get"
            exit 1
        }
    elif command -v dnf > /dev/null; then
        dnf install -y inotify-tools || {
            log_message "Failed to install inotify-tools with dnf"
            exit 1
        }
    elif command -v yum > /dev/null; then
        yum install -y inotify-tools || {
            log_message "Failed to install inotify-tools with yum"
            exit 1
        }
    else
        log_message "No supported package manager found"
        exit 1
    fi
}

# Set up log rotation
setup_logrotate() {
    if [ ! -f /etc/logrotate.d/interface-protection ]; then
        cat <<EOF > /etc/logrotate.d/interface-protection
$LOG_FILE {
    rotate 5
    size 10M
    compress
    delaycompress
    missingok
    notifempty
}
EOF
        log_message "Logrotate configuration set up for $LOG_FILE"
    fi
}

# Set up persistence (systemd or cron)
setup_persistence() {
    cp -p "$0" "$PRO_INT_SCRIPT" || {
        log_message "Failed to copy script to $PRO_INT_SCRIPT"
        exit 1
    }
    chmod +x "$PRO_INT_SCRIPT"
    if command -v systemctl > /dev/null; then
        cat <<EOF > /etc/systemd/system/interface-protection.service
[Unit]
Description=Interface Protection Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $PRO_INT_SCRIPT daemon
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable interface-protection.service || log_message "Failed to enable service"
        log_message "Systemd service set up for interface-protection"
    else
        (crontab -l 2>/dev/null | grep -v "$PRO_INT_SCRIPT"; echo "@reboot /bin/bash $PRO_INT_SCRIPT start") | crontab - || {
            log_message "Failed to set up cronjob"
            exit 1
        }
        log_message "Cronjob set up to run $PRO_INT_SCRIPT on reboot"
    fi
    setup_logrotate
}

# Check if script is running
check_running() {
    if [ -f "$PID_FILE" ] && ps -p "$(cat "$PID_FILE")" > /dev/null 2>&1; then
        echo "Script is already running with PID $(cat "$PID_FILE")"
        exit 1
    fi
}

# Stop the script
stop_script() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid" && rm -f "$PID_FILE"
            log_message "Script stopped (PID: $pid)"
            echo "Script stopped"
        else
            rm -f "$PID_FILE"
            log_message "PID file exists but process not running, cleaned up"
            echo "No running process found"
        fi
    else
        echo "Script is not running"
    fi
}

# Status of the script
status_script() {
    if [ -f "$PID_FILE" ] && ps -p "$(cat "$PID_FILE")" > /dev/null 2>&1; then
        echo "Script is running with PID $(cat "$PID_FILE")"
    else
        echo "Script is not running"
    fi
}

# Daemon mode
run_daemon() {
    trap 'stop_script; exit 0' SIGTERM SIGINT
    echo $$ > "$PID_FILE"
    local managers=($(detect_managers))
    if [ ${#managers[@]} -eq 0 ]; then
        log_message "No network configuration managers detected"
        exit 1
    fi
    for manager in "${managers[@]}"; do
        backup_config "$manager"
    done
    for manager in "${managers[@]}"; do
        monitor_config "$manager" &
    done
    wait
}

# Main logic
case "$1" in
    start)
        check_running
        if [ ! -f "$PRO_INT_SCRIPT" ]; then
            install_dependencies
            setup_persistence
        fi
        if command -v systemctl > /dev/null; then
            systemctl start interface-protection
            echo "Started via systemd"
        else
            exec setsid "$0" daemon >> "$LOG_FILE" 2>&1 &
            echo "Started monitoring (PID: $!). Check $LOG_FILE for details"
        fi
        ;;
    stop)
        if command -v systemctl > /dev/null; then
            systemctl stop interface-protection
            echo "Stopped via systemd"
        else
            stop_script
        fi
        ;;
    status)
        if command -v systemctl > /dev/null; then
            systemctl status interface-protection
        else
            status_script
        fi
        ;;
    update-backup)
        managers=($(detect_managers))
        if [ ${#managers[@]} -eq 0 ]; then
            echo "No network configuration managers detected"
            exit 1
        fi
        for manager in "${managers[@]}"; do
            backup_config "$manager"
        done
        log_message "Backups updated for all managers"
        echo "Backups updated for all managers"
        ;;
    daemon)
        run_daemon
        ;;
    *)
        echo "Usage: $0 {start|stop|status|update-backup}"
        exit 1
        ;;
esac

exit 0
