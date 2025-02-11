#!/bin/bash
#
#  A script to upgrade CentOS 7 
#  Quick and dirty, the majority is AI generated with a little bit of tweaking from me.
#
#  Samuel Brucker 2024 - 2025

# Set up logging
LOG_FILE="/var/log/centos_upgrade.log"
echo "Starting CentOS 7 to CentOS Stream 9 upgrade at $(date)" > "$LOG_FILE"

# Function to handle errors gracefully
handle_error() {
    echo "ERROR: $1" | tee -a "$LOG_FILE"
    echo "Check $LOG_FILE for details"
    exit 1
}

# Verify we're running on CentOS
if [ ! -f /etc/os-release ] || [ ! -f /etc/centos-release ]; then
    handle_error "CentOS release files not found"
fi

if ! grep -q "CentOS" /etc/centos-release; then
    handle_error "This script must be run on CentOS"
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
echo "Creating CentOS Stream repository configuration..." | tee -a "$LOG_FILE"
cat << EOF > /etc/yum.repos.d/centos-stream.repo
[centos-stream]
name=CentOS Stream \$releasever - Base
baseurl=http://mirror.centos.org/\$releasever-stream/BaseOS/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
EOF

# Clean yum cache and verify repository configuration
echo "Cleaning yum cache and verifying repository configuration..." | tee -a "$LOG_FILE"
yum clean all >> "$LOG_FILE" 2>&1 || handle_error "Failed to clean yum cache"
yum repolist enabled >> "$LOG_FILE" 2>&1 || handle_error "Failed to verify repository configuration"

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
