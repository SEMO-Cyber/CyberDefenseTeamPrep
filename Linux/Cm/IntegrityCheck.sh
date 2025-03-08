#!/bin/bash

# Load config
CONFIG_FILE="./fs.config"
LOG_FILE="/var/log/integrity_monitor.log"

# Function to check immutability
check_immutable() {
    while read -r path; do
        if [ -e "$path" ]; then
            if [ -d "$path" ]; then
                # Check if the directory is immutable
                if ! lsattr -d "$path" | grep -q 'i'; then
                    chattr +i "$path"
                    echo "$(date): Warning - Directory $path is not immutable, setting it to immutable."  # Console warning
                    echo "$(date): Directory $path is not immutable, setting it to immutable." >> "$LOG_FILE"
                fi
            elif [ -f "$path" ]; then
                # Check if the file is immutable
                if ! lsattr "$path" | grep -q 'i'; then
                    chattr +i "$path"
                    echo "$(date): Warning - File $path is not immutable, setting it to immutable."  # Console warning
                    echo "$(date): File $path is not immutable, setting it to immutable." >> "$LOG_FILE"
                fi
            fi
        else
        fi
    done < "$CONFIG_FILE"
}

# Run in background every 10 seconds
while true; do
    check_immutable
    sleep 10
done
