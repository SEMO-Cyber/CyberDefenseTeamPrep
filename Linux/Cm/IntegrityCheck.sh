#!/bin/bash

# Load config
CONFIG_FILE="./fs.config"
LOG_FILE="/var/log/integrity_monitor.log"

# Function to set immutability
set_immutable() {
    while read -r path; do
        if [ -e "$path" ]; then
            if [ -d "$path" ]; then
                # Set the directory to be immutable
                sudo chattr +i -d $path
                
            elif [ -f "$path" ]; then
                # Set the file to be immutable
                sudo chattr +i $path
            fi
        else
            #echo "$(date): Warning - Path $path does not exist."  # Console warning if the path doesn't exist
            #echo "$(date): Path $path does not exist." >> "$LOG_FILE"
        fi
    done < "$CONFIG_FILE"
}

# Run in background every 10 seconds
while true; do
    set_immutable
    sleep 10
done
