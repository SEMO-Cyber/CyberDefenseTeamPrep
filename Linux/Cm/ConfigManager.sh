#!/bin/bash

# Function to edit fs.config
edit_fs_config() {
    nano ./fs.config
}

# Function to edit serviceup.config
edit_serviceup_config() {
    nano ./serviceup.config
}

edit_maliciousdir_config() {
    nano ./maliciousdir.config
}

# Menu loop
while true; do
    clear
    echo "Choose an option:"
    echo "1) Edit fs.config"
    echo "2) Edit serviceup.config"
    echo "3) Edit maliciousdir.config"
    echo "4) Exit"
    read -p "Enter your choice: " choice

    case $choice in
        1)
            edit_fs_config
            ;;
        2)
            edit_serviceup_config
            ;;
        3)
            edit_maliciousdir_config
            ;;
        4)
            exit 0
            ;;
        *)
            echo "Invalid choice!"
            ;;
    esac
    sleep 2
done
