#!/bin/bash

# Function to stop running scripts
stop_scripts() {
    pkill -f IntegrityCheck.sh
    pkill -f ServiceManager.sh
}

# Function to start scripts
start_scripts() {
    nohup ./IntegrityCheck.sh &
    nohup ./ServiceManager.sh &
}

# Menu loop
while true; do
    clear
    echo "Choose an option:"
    echo "1) Config Manager"
    echo "2) Key Search"
    echo "3) Backup Handler"
    echo "4) Clear Screen"
    echo "5) Exit"
    read -p "Enter your choice: " choice

    case $choice in
        1)
            ./ConfigManager.sh
            stop_scripts
            start_scripts
            ;;
        2)
            ./KeySearch.sh
            ;;
        3)
            ./BackupHandler.sh
            ;;
        4)
            clear
            ;;
        5)
            stop_scripts
            exit 0
            ;;
        *)
            echo "Invalid choice!"
            ;;
    esac
    sleep 2
done
