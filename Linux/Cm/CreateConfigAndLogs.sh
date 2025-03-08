#!/bin/bash

# Define the config and log files for the project
CONFIG_FILES=(
    "./fs.config"
    "./serviceup.config"
    "./maliciouskeys.config"
    "./maliciousdir.config"
    "./backup.config"
)

LOG_FILES=(
    "/var/log/integrity_monitor.log"
    "/var/log/service_interrupt.log"
    "/var/log/malicious_keys.log"
)

# Function to create an empty file if it doesn't exist
create_file() {
    FILE=$1
    if [ ! -f "$FILE" ]; then
        touch "$FILE"
        echo "$FILE has been created."
    else
        echo "$FILE already exists."
    fi
}

# Create .config files
echo "Creating .config files..."
for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
    create_file "$CONFIG_FILE"
done

# Create .log files
echo "Creating .log files..."
for LOG_FILE in "${LOG_FILES[@]}"; do
    create_file "$LOG_FILE"
done

echo "All necessary .config and .log files have been created."
