#!/bin/bash

# Memory file to store backup information
MEMORY_FILE="./backup.config"

# Function to create a backup
backup() {
    # Prompt user for source and destination directories
    read -p "Enter the source directory to back up: " SOURCE_DIR
    read -p "Enter the destination directory to save the backup: " DEST_DIR

    # Check if source directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "Source directory $SOURCE_DIR does not exist."
        exit 1
    fi

    # Check if destination directory exists, if not, create it
    if [ ! -d "$DEST_DIR" ]; then
        echo "Destination directory $DEST_DIR does not exist. Creating it..."
        mkdir -p "$DEST_DIR"
    fi

    # Create a timestamp for the backup file
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

    # Define the backup filename
    BACKUP_FILE="$DEST_DIR/backup_$(basename "$SOURCE_DIR")_$TIMESTAMP.tar.gz"

    # Create the backup
    echo "Creating backup of $SOURCE_DIR at $BACKUP_FILE"
    tar -czf "$BACKUP_FILE" -C "$SOURCE_DIR" .

    # Check if the backup was successful
    if [ $? -eq 0 ]; then
        echo "Backup successfully created at $BACKUP_FILE"
        # Save the backup info to the memory file
        echo "$TIMESTAMP|$SOURCE_DIR|$BACKUP_FILE" >> "$MEMORY_FILE"
    else
        echo "Backup failed."
        exit 1
    fi
}

# Function to list backups from memory file
list_backups() {
    if [ ! -f "$MEMORY_FILE" ]; then
        echo "No backups found."
        exit 1
    fi
    echo "Available backups:"
    cat -n "$MEMORY_FILE" | awk -F'|' '{print $1 ") Timestamp: " $2 ", Source: " $3 ", Backup File: " $4}'
}

# Function to restore a backup
restore() {
    list_backups

    # Prompt user to select a backup
    read -p "Enter the number of the backup to restore: " BACKUP_NUMBER
    BACKUP_INFO=$(sed "${BACKUP_NUMBER}q;d" "$MEMORY_FILE")

    # Check if the backup info was found
    if [ -z "$BACKUP_INFO" ]; then
        echo "Invalid backup selection."
        exit 1
    fi

    # Parse the backup info
    TIMESTAMP=$(echo "$BACKUP_INFO" | cut -d'|' -f1)
    SOURCE_DIR=$(echo "$BACKUP_INFO" | cut -d'|' -f2)
    BACKUP_FILE=$(echo "$BACKUP_INFO" | cut -d'|' -f3)

    # Check if the backup file exists
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Backup file $BACKUP_FILE not found."
        exit 1
    fi

    # Recreate the source directory if it doesn't exist
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "Source directory $SOURCE_DIR does not exist. Creating it..."
        mkdir -p "$SOURCE_DIR"
    fi

    # Restore the backup
    echo "Restoring backup from $BACKUP_FILE to $SOURCE_DIR"
    tar -xzf "$BACKUP_FILE" -C "$SOURCE_DIR"

    if [ $? -eq 0 ]; then
        echo "Backup restored successfully to $SOURCE_DIR"
    else
        echo "Restore failed."
        exit 1
    fi
}


# Main script execution
echo "Select an option:"
echo "1) Create a backup"
echo "2) Restore a backup"
read -p "Enter your choice (1 or 2): " CHOICE

case $CHOICE in
    1) backup ;;
    2) restore ;;
    *) echo "Invalid choice." ;;
esac
