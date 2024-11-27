#!/bin/bash
#Taken almost character-for-character from  Drury's 2023-2024 Github

#Harden cron permissions
echo "Locking down Cron"
touch /etc/cron.allow
chmod 600 /etc/cron.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/cron.deny
echo "Locking down AT"
touch /etc/at.allow
chmod 600 /etc/at.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/at.deny


#Check cron locations, bring into single directory
#Made original script based off of: https://github.com/dacx910/CCDC-Scripts/blob/main/Linux%20Scripts/dumpCronJobs.sh
#Did some edits, ran it through AI, and then edited again

# Function to check if the script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit 1
    fi
}

# Function to create directories
create_directories() {
    echo "Creating directories for cron job dumps..."
    mkdir -p /cronJobs/varSpool
    mkdir -p /cronJobs/etc/hourly
    mkdir -p /cronJobs/etc/daily
    mkdir -p /cronJobs/etc/weekly
    mkdir -p /cronJobs/etc/monthly
}

# Function to copy cron jobs
copy_cron_jobs() {
    local source_dirs=(
        "/var/spool/cron/crontabs"
        "/etc/crontab"
        "/etc/cron.hourly"
        "/etc/cron.daily"
        "/etc/cron.weekly"
        "/etc/cron.monthly"
    )
    local dest_dirs=(
        "/cronJobs/varSpool"
        "/cronJobs/etc"
        "/cronJobs/etc/hourly"
        "/cronJobs/etc/daily"
        "/cronJobs/etc/weekly"
        "/cronJobs/etc/monthly"
    )

    echo "Dumping cron jobs into /cronJobs..."
    for i in "${!source_dirs[@]}"; do
        if [ -e "${source_dirs[$i]}" ]; then
            cp -r "${source_dirs[$i]}" "${dest_dirs[$i]}"
            echo "Dumped ${source_dirs[$i]} to ${dest_dirs[$i]}"
        else
            echo "Warning: ${source_dirs[$i]} does not exist."
        fi
    done
}

# Function to display files
display_files() {
    local input=""
    while true; do
        read -p "Display list of files? (y/n) " input
        case $input in
            [Yy]* ) find /cronJobs/ -type f; break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Main script execution
check_root
create_directories
copy_cron_jobs
display_files

echo "Cron job dump complete."
