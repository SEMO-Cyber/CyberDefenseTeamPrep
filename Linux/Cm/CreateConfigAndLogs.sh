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

# Define the sub-scripts that need to be made executable
SCRIPTS=(
    "./IntegrityCheck.sh"
    "./ServiceManager.sh"
    "./KeySearch.sh"
    "./BackupHandler.sh"
    "./ConfigManager.sh"
    "./CustomManager.sh"
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

# Function to set executable permissions for scripts
set_executable_permissions() {
    SCRIPT=$1
    if [ -f "$SCRIPT" ]; then
        chmod +x "$SCRIPT"
        echo "Executable permissions set for $SCRIPT."
    else
        echo "$SCRIPT does not exist."
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

# Set executable permissions for the sub-scripts
echo "Setting executable permissions for sub-scripts..."
for SCRIPT in "${SCRIPTS[@]}"; do
    set_executable_permissions "$SCRIPT"
done

echo "All necessary .config, .log files have been created, and executable permissions have been set for sub-scripts."
