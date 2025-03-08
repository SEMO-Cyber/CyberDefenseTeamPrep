#!/bin/bash

# Load config
CONFIG_FILE="./fs.config"
LOG_FILE="/var/log/integrity_monitor.log"

# Function to remove immutability
remove_immutable() {
    while read -r path; do
        if [ -e "$path" ]; then
            if [ -d "$path" ]; then
                # Remove the immutability from the directory
                sudo chattr -i "$path"
                echo "$(date): Directory $path has been made mutable."  # Console message
                echo "$(date): Directory $path has been made mutable." >> "$LOG_FILE"
            elif [ -f "$path" ]; then
                # Remove the immutability from the file
                sudo chattr -i "$path"
                echo "$(date): File $path has been made mutable."  # Console message
                echo "$(date): File $path has been made mutable." >> "$LOG_FILE"
            fi
        else
            echo "$(date): Warning - Path $path does not exist."  # Console warning if the path doesn't exist
            echo "$(date): Path $path does not exist." >> "$LOG_FILE"
        fi
    done < "$CONFIG_FILE"
}

# Run in background every 10 seconds
while true; do
    remove_immutable
    sleep 10
done
