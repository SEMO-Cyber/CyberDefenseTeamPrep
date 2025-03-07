#!/bin/bash

LOG_FILE="/var/log/integrity_monitor.log"

log_event() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [ALERT] $message" >> "$LOG_FILE"
}

monitor_immutable() {
    while true; do
        for dir in $(awk '{print $3}' configuration.txt); do
           if [[ $(lsattr -d "$dir") != @(i|ii|iS|iA|iSa|iAS)* ]];  then
                log_event "Immutable flag removed from $dir. Restoring..."
                chattr +i "$dir"
                log_event "Restored immutable flag for $dir"
            fi
        done
        sleep 5
    done
}

monitor_immutable
