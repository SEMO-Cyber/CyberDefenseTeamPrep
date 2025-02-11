#!/bin/bash
#
#  A script to upgrade CentOS 7 
#  Quick and dirty, the majority is AI generated
#
#  Samuel Brucker 2024 - 2025
#!/bin/bash



# Set up logging
LOG_FILE="/var/log/centos_upgrade.log"
echo "Starting CentOS 7 to CentOS Stream 9 upgrade at $(date)" > "$LOG_FILE"

# Function to handle errors gracefully
handle_error() {
    echo "ERROR: $1" | tee -a "$LOG_FILE"
    echo "Check $LOG_FILE for details"
    exit 1
}

# Verify we're running on CentOS 7
if ! grep -q "CentOS Linux 7" /etc/centos-release; then
    handle_error "This script must be run on CentOS 7"
fi

# Check for root privileges
if [ "$(id -u)" != "0" ]; then
    handle_error "This script must be run as root"
fi

echo "Starting upgrade process..." | tee -a "$LOG_FILE"

# Step 1: Update current system
echo "Updating current system..." | tee -a "$LOG_FILE"
yum clean all >> "$LOG_FILE" 2>&1 || handle_error "Failed to clean yum cache"
yum update -y >> "$LOG_FILE" 2>&1 || handle_error "System update failed"

# Step 2: Install EPEL repository
echo "Installing EPEL repository..." | tee -a "$LOG_FILE"
yum install -y epel-release >> "$LOG_FILE" 2>&1 || handle_error "EPEL installation failed"

# Step 3: Configure CentOS Stream repository
echo "Configuring CentOS Stream repository..." | tee -a "$LOG_FILE"
curl -o /etc/yum.repos.d/centos-stream.repo \
http://mirror.centos.org/centos/8-stream/BaseOS/x86_64/os/Packages/centos-stream-release-8.1-1.el8.noarch.rpm \
>> "$LOG_FILE" 2>&1 || handle_error "Failed to configure Stream repository"

# Step 4: Install CentOS Stream release package
echo "Installing CentOS Stream release package..." | tee -a "$LOG_FILE"
yum install -y centos-release-stream >> "$LOG_FILE" 2>&1 || handle_error "Failed to install Stream release package"

# Step 5: Swap repositories
echo "Swapping repositories..." | tee -a "$LOG_FILE"
yum swap -y centos-{linux,stream}-repos >> "$LOG_FILE" 2>&1 || handle_error "Repository swap failed"

# Step 6: Perform distribution synchronization
echo "Performing distribution synchronization..." | tee -a "$LOG_FILE"
yum distro-sync -y >> "$LOG_FILE" 2>&1 || handle_error "Distribution sync failed"

# Step 7: Schedule reboot
echo "Upgrade completed. System will reboot in 5 seconds..." | tee -a "$LOG_FILE"
echo "Please review $LOG_FILE after reboot for any issues."
sleep 5
shutdown -r now

exit 0
