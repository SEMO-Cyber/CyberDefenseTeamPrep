#!/bin/bash

# Configuration & log file locations
CONFIG_FILE="configuration.txt"
IMMUTABLE_FILE="immutablebackups.txt"
LOG_FILE="/var/log/custom_manager.log"
MALICIOUS_LOG="/var/log/malicious_scan.log"
INTEGRITY_LOG="/var/log/integrity_monitor.log"
ICHECK_THREAD_SCRIPT="icheckthread.sh"

# Function for logging critical events in syslog format
log_event() {
    local severity="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$severity] $message" >> "$LOG_FILE"
}

# Function to load configuration
load_configuration() {
    declare -A SERVICE_PATHS
    while IFS=' ' read -r service type path; do
        SERVICE_PATHS[$service]=$path
    done < "$CONFIG_FILE"
    
    declare -A IMMUTABLE_BACKUPS
    while IFS=' ' read -r dir backup; do
        IMMUTABLE_BACKUPS[$dir]=$backup
    done < "$IMMUTABLE_FILE"
}

# Function to scan for malicious keywords
scan_malicious_code() {
    log_event "INFO" "Starting malicious code scan..."
    > "$MALICIOUS_LOG"  # Clear old logs

    for dir in $(awk '{print $3}' "$CONFIG_FILE"); do
        for file in $(find "$dir" -type f 2>/dev/null); do
            while read -r keyword; do
                if grep -nH "$keyword" "$file" 2>/dev/null; then
                    log_event "ALERT" "Malicious code detected in $file"
                    echo "$file - Malicious keyword: $keyword" >> "$MALICIOUS_LOG"
                fi
            done <<< "$(echo "${MALICIOUS_KEYWORDS[@]}")"
        done
    done
}

# Function to start integrity monitor
run_integrity_monitor() {
    log_event "INFO" "Starting integrity monitor..."
    nohup bash "$ICHECK_THREAD_SCRIPT" &>> "$INTEGRITY_LOG" &
    echo "Integrity check running in background."
}

# Function to edit configuration
edit_configuration() {
    echo "1. Add new entry"
    echo "2. Edit existing entry"
    read -p "Select an option: " choice
    if [[ $choice -eq 1 ]]; then
        read -p "Enter service name: " service
        read -p "Enter type (static/dynamic): " type
        read -p "Enter directory path: " path
        echo "$service $type $path" >> "$CONFIG_FILE"
        log_event "INFO" "Added new configuration: $service"
    elif [[ $choice -eq 2 ]]; then
        nano "$CONFIG_FILE"
        log_event "INFO" "Configuration edited"
    fi
}

# Function to monitor services
monitor_services() {
    while true; do
        clear
        echo -e "Service Name\tStatus\tLogs Count\tVersion"
        for service in $(awk '{print $1}' "$CONFIG_FILE"); do
            status=$(systemctl is-active "$service" 2>/dev/null || echo "UNKNOWN")
            logs=$(journalctl -u "$service" --since "1 hour ago" | wc -l)
            version=$(systemctl show "$service" --property=ExecMainPID | awk -F= '{print $2}')
            echo -e "$service\t$status\t$logs\t$version"
        done
        sleep 1
    done
}

# Function to manage backups
backup_manager() {
    echo "Available immutable directories:"
    cat "$IMMUTABLE_FILE" | awk '{print $1}'
    read -p "Enter directory to back up: " dir
    backup_path=$(grep "$dir" "$IMMUTABLE_FILE" | awk '{print $2}')
    
    if [[ -z "$backup_path" ]]; then
        log_event "ERROR" "Invalid backup directory: $dir"
    else
        cp -r "$dir" "$backup_path"
        log_event "INFO" "Backup created for $dir"
        echo "Backup successful."
    fi
}

# Function to check integrity thread status
check_integrity_thread() {
    pid=$(pgrep -f "$ICHECK_THREAD_SCRIPT")
    if [[ -n "$pid" ]]; then
        echo "Integrity monitor is running (PID: $pid)"
        read -p "Do you want to stop it? (y/n): " choice
        [[ "$choice" == "y" ]] && kill "$pid" && log_event "INFO" "Integrity monitor stopped"
    else
        echo "Integrity monitor is not running."
    fi
}

# Main menu
while true; do
    echo "CustomManager - Blue Team Cyber Defense"
    echo "1. Malicious Search with Configuration"
    echo "2. Integrity Run with Configuration"
    echo "3. Edit Configuration"
    echo "4. Monitor Services"
    echo "5. Backup Manager"
    echo "6. View Configuration"
    echo "7. Check Integrity Thread Status"
    echo "8. Quit"
    read -p "Select an option: " choice

    case $choice in
        1) scan_malicious_code ;;
        2) run_integrity_monitor ;;
        3) edit_configuration ;;
        4) monitor_services ;;
        5) backup_manager ;;
        6) cat "$CONFIG_FILE" ;;
        7) check_integrity_thread ;;
        8) exit 0 ;;
        *) echo "Invalid option!" ;;
    esac
done
