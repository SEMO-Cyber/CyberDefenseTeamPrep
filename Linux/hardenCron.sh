#!/bin/bash
#A script meant to harden some of the perms for cron jobs and copy all cron locations into a central, easy to reference directory. This is a time saver with a tiny bit of hardening, nothing special.

#I took both influences, made some changes, ran it through AI, and then did a little more configuration. 


#!/bin/bash
# Script to harden cron and at permissions and dump cron jobs

# Function to check if the script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit 1
    fi
}

# Function to harden cron and at permissions
harden_cron_permissions() {
    echo "Locking down Cron and AT permissions..."
    touch /etc/cron.allow
    chmod 600 /etc/cron.allow
    awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/cron.deny

    touch /etc/at.allow
    chmod 600 /etc/at.allow
    awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/at.deny
}

# Function to create directories for cron job dumps
create_directories() {
    local base_dir=~/cronJobs
    local sub_dirs=("varSpool" "etc/hourly" "etc/daily" "etc/weekly" "etc/monthly")

    echo "Checking and creating base directory for cron job dumps..."
    mkdir -p "$base_dir"

    echo "Creating subdirectories for cron job dumps..."
    for dir in "${sub_dirs[@]}"; do
        mkdir -p "$base_dir/$dir"
    done
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
        "~/cronJobs/varSpool"
        "~/cronJobs/etc"
        "~/cronJobs/etc/hourly"
        "~/cronJobs/etc/daily"
        "~/cronJobs/etc/weekly"
        "~/cronJobs/etc/monthly"
    )

    echo "Dumping cron jobs into ~/cronJobs..."
    for i in "${!source_dirs[@]}"; do
        if [ -e "${source_dirs[$i]}" ]; then
            cp -r "${source_dirs[$i]}" "${dest_dirs[$i]}"
            printf "Dumped %s to %s\n" "${source_dirs[$i]}" "${dest_dirs[$i]}"
        else
            printf "Warning: %s does not exist.\n" "${source_dirs[$i]}"
        fi
    done
}

# Function to display files
display_files() {
    local input=""
    while true; do
        read -p "Display list of files? (y/n) " input
        case $input in
            [Yy]* ) find ~/cronJobs/ -type f; break;;
            [Nn]* ) break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Main script execution
check_root
harden_cron_permissions
create_directories
copy_cron_jobs
display_files

echo "Cron job dump complete."
