#!/bin/bash

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# Ensure the results directory exists
mkdir -p results

# File paths for the reports
USER_DETAILS_REPORT="results/user_details_report.txt"
ACCESS_INFO_REPORT="results/access_info_report.txt"

# Display the path of the current script
echo "The current script file in use is: $(readlink -f /proc/$$/exe)"
echo "Current script path using BASH_SOURCE: ${BASH_SOURCE[0]}"

# Function to display user details, roles, and recent login
display_user_details() {
    echo -e "\nUser Details, Roles, and Recent Login" > "$USER_DETAILS_REPORT"
    echo "--------------------------------------" >> "$USER_DETAILS_REPORT"
    printf "%-15s %-30s %-20s\n" "User" "Groups (Roles)" "Recent Login" >> "$USER_DETAILS_REPORT"

    log_file=""
    if [[ -f /var/log/auth.log ]]; then
        log_file="/var/log/auth.log"
    elif [[ -f /var/log/secure ]]; then
        log_file="/var/log/secure"
    fi

    for user in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
        user_groups=$(groups $user)
        
        # Get recent login info
        if [[ -n "$log_file" ]]; then
            recent_login=$(grep "session opened for user $user" "$log_file" | tail -n 1 | awk '{print $1, $2, $3}')
            if [[ -z "$recent_login" ]]; then
                recent_login="No recent login"
            fi
        else
            recent_login="Log file not found"
        fi

        printf "%-15s %-30s %-20s\n" "$user" "$user_groups" "$recent_login" >> "$USER_DETAILS_REPORT"
    done

    echo "User details report generated in $USER_DETAILS_REPORT."
}

# Function to display detailed file access information and services used by each user
display_detailed_access_info() {
    echo -e "\nDetailed Access Information for Each User" > "$ACCESS_INFO_REPORT"
    echo "-----------------------------------------" >> "$ACCESS_INFO_REPORT"
    printf "%-15s %-20s %-30s %-40s\n" "User" "Timestamp" "Action" "File/Service Path" >> "$ACCESS_INFO_REPORT"

    for user in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
        echo -e "\nActivity for user: $user" >> "$ACCESS_INFO_REPORT"
        
        # Display open files accessed by the user
        echo -e "\nOpen Files:" >> "$ACCESS_INFO_REPORT"
        printf "%-15s %-20s %-30s %-40s\n" "User" "Timestamp" "File Name" "File Path" >> "$ACCESS_INFO_REPORT"
        lsof -u "$user" 2>/dev/null | awk '
            NR>1 {
                timestamp=$5
                filetype=$4
                filename=$9
                print "'$user'", timestamp, filetype, filename
            }' | while read user timestamp filetype filename; do
                printf "%-15s %-20s %-30s %-40s\n" "$user" "$timestamp" "$filetype" "$filename" >> "$ACCESS_INFO_REPORT"
            done

        # Display deleted files (if any)
        echo -e "\nRecently Deleted Files (if any):" >> "$ACCESS_INFO_REPORT"
        printf "%-15s %-20s %-30s %-40s\n" "User" "Timestamp" "Action" "File Path" >> "$ACCESS_INFO_REPORT"
        if [[ -f /var/log/audit/audit.log ]]; then
            ausearch -k delete -ui $(id -u "$user") 2>/dev/null | grep -E "syscall=unlink|syscall=unlinkat" | \
            awk '{print "'$user'", $1, "deleted", $NF}' | while read user timestamp action filepath; do
                printf "%-15s %-20s %-30s %-40s\n" "$user" "$timestamp" "$action" "$filepath" >> "$ACCESS_INFO_REPORT"
            done
        else
            echo "No audit log found. Skipping deleted file info." >> "$ACCESS_INFO_REPORT"
        fi

        # Display running services/processes by the user
        echo -e "\nRunning Services and Processes:" >> "$ACCESS_INFO_REPORT"
        printf "%-15s %-20s %-30s %-40s\n" "User" "PID" "Process Name" "Command" >> "$ACCESS_INFO_REPORT"
        ps -u "$user" -o pid,comm,cmd --no-headers | while read pid pname cmd; do
            printf "%-15s %-20s %-30s %-40s\n" "$user" "$pid" "$pname" "$cmd" >> "$ACCESS_INFO_REPORT"
        done
    done

    echo "Detailed access report generated in $ACCESS_INFO_REPORT."
}

# Function to prompt for and change a user's password with confirmation
change_user_password() {
    local user="$1"
    while true; do
        read -sp "Enter new password for user $user: " password
        echo
        read -sp "Confirm new password for user $user: " confirm_password
        echo
        
        if [[ "$password" == "$confirm_password" ]]; then
            echo "$user:$password" | chpasswd
            echo "Password changed successfully for user $user."
            break
        else
            echo "Passwords do not match. Please try again."
        fi
    done
}

# Function to change password for all users except root
change_all_user_passwords() {
    echo "Changing password for all users except root..."
    for user in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd | grep -v '^root$'); do
        change_user_password "$user"
    done
}

# Function to change root password
change_root_password() {
    echo "Changing root password..."
    change_user_password "root"
}

# Main Menu
while true; do
    echo -e "\nMain Menu"
    echo "1. Generate user details, roles, and recent login report"
    echo "2. Generate detailed access information report for each user"
    echo "3. Change password for a single user"
    echo "4. Change password for all users except root"
    echo "5. Change root password"
    echo "6. Exit"
    read -p "Select an option [1-6]: " option

    case $option in
        1)
            display_user_details
            ;;
        2)
            display_detailed_access_info
            ;;
        3)
            read -p "Enter username: " user
            if id "$user" &>/dev/null; then
                change_user_password "$user"
            else
                echo "User $user does not exist."
            fi
            ;;
        4)
            change_all_user_passwords
            ;;
        5)
            change_root_password
            ;;
        6)
            echo "Exiting."
            break
            ;;
        *)
            echo "Invalid option. Please select a valid option from the menu."
            ;;
    esac
done
