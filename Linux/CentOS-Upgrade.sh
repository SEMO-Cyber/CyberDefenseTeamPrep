#!/bin/bash
#
#  A script to upgrade CentOS 7 
#  This took a bit of working out. 
#
#  Samuel Brucker 2024 - 2025

#!/bin/bash
# almalinux_upgrade.sh

# Color codes for better visibility
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Function to display error and exit
error_exit() {
    echo -e "${RED}$1${NC}"
    exit 1
}

# Function to check if we're root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "Please run this script as root"
    fi
}

# Function to verify system state
verify_system() {
    echo -e "${GREEN}Verifying system state...${NC}"
    if ! command -v yum &> /dev/null; then
        error_exit "YUM package manager not found"
    fi
    
    # Get current OS version
    CURRENT_OS=$(cat /etc/redhat-release)
    echo "Current OS: $CURRENT_OS"
}

# Function to upgrade CentOS 7 to AlmaLinux 8
upgrade_to_alma8() {
    echo -e "${GREEN}Phase 1: Upgrading to AlmaLinux 8...${NC}"
    
    # Update repositories
    echo "Updating repositories..."
    curl -o /etc/yum.repos.d/CentOS-Base.repo https://el7.repo.almalinux.org/centos/CentOS-Base.repo || error_exit "Failed to update repositories"
    
    # Upgrade system
    echo "Upgrading system..."
    yum upgrade -y || error_exit "System upgrade failed"
    
    # Install ELevate packages
    echo "Installing ELevate packages..."
    yum install -y http://repo.almalinux.org/elevate/elevate-release-latest-el$(rpm --eval %rhel).noarch.rpm || error_exit "Failed to install ELevate release"
    yum install -y leapp-upgrade leapp-data-almalinux || error_exit "Failed to install Leapp packages"
    
    # Run preupgrade check
    echo "Running preupgrade check..."
    leapp preupgrade || error_exit "Preupgrade check failed"
    
    # Fix common issues
    echo "Fixing common issues..."
    rmmod pata_acpi 2>/dev/null
    echo PermitRootLogin yes | tee -a /etc/ssh/sshd_config
    leapp answer --section remove_pam_pkcs11_module_check.confirm=True
    
    # Perform upgrade
    echo "Performing upgrade..."
    leapp upgrade || error_exit "Upgrade failed"
    
    echo "Rebooting system..."
    reboot
}

# Function to prepare system for AlmaLinux 9
prepare_for_alma9() {
    echo -e "${GREEN}Preparing system for AlmaLinux 9 upgrade...${NC}"
    
    # Edit yum.conf
    echo "Editing yum.conf..."
    sed -i '/exclude/d' /etc/yum.conf
    
    # Remove old packages
    echo "Removing old packages..."
    rpm -qa | grep el7 | xargs rpm -e --nodeps
    
    # Clean system
    echo "Cleaning system..."
    dnf clean all
}

# Function to upgrade to AlmaLinux 9
upgrade_to_alma9() {
    echo -e "${GREEN}Phase 2: Upgrading to AlmaLinux 9...${NC}"
    
    # Install ELevate packages
    echo "Installing ELevate packages..."
    yum install -y http://repo.almalinux.org/elevate/elevate-release-latest-el$(rpm --eval %rhel).noarch.rpm || error_exit "Failed to install ELevate release"
    yum install -y leapp-upgrade leapp-data-almalinux || error_exit "Failed to install Leapp packages"
    
    # Run preupgrade check
    echo "Running preupgrade check..."
    leapp preupgrade || error_exit "Preupgrade check failed"
    
    # Fix common issues
    echo "Fixing common issues..."
    sed -i "s/^AllowZoneDrifting=.*/AllowZoneDrifting=no/" /etc/firewalld/firewalld.conf
    leapp answer --section check_vdo.confirm=True
    
    # Perform upgrade
    echo "Performing upgrade..."
    leapp upgrade || error_exit "Upgrade failed"
    
    echo "Rebooting system..."
    reboot
}

# Main function
main() {
    check_root
    verify_system
    
    # Get current OS version
    CURRENT_OS=$(cat /etc/redhat-release)
    
    if [[ $CURRENT_OS =~ "CentOS Linux 7" ]]; then
        upgrade_to_alma8
    elif [[ $CURRENT_OS =~ "AlmaLinux OS 8" ]]; then
        prepare_for_alma9
        upgrade_to_alma9
    else
        error_exit "Unsupported starting operating system"
    fi
}

# Run the main function
main
