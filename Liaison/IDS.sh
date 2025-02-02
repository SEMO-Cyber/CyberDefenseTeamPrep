#!/bin/bash

# Function to display messages to the user
show_message() {
  echo -e "\e[1;32m$1\e[0m"  # Green and bold text
}

# Function to display error messages
show_error() {
  echo -e "\e[1;31mERROR: $1\e[0m" # Red and bold text
}

# Function to check if the script is run as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    show_error "This script must be run as root."
    exit 1
  fi
}

# Function to get network interface from user
get_network_interface() {
  show_message "Available network interfaces:"
  ip -o -4 addr show | awk '$2 !~ /^lo$/ {print $2}'

  while true; do
    read -p "Enter the network interface you want Snort to monitor (e.g., eth0, ens33): " interface
    if ip link show $interface > /dev/null 2>&1; then
      break
    else
      show_error "Invalid interface name. Please try again."
    fi
  done
}

# Function to get home network from user
get_home_network() {
  while true; do
    read -p "Enter your home network in CIDR notation (e.g., 192.168.1.0/24): " home_net
    # Basic CIDR format check (can be improved for more robust validation)
    if [[ $home_net =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2}$ ]]; then
      break
    else
      show_error "Invalid CIDR format. Please try again."
    fi
  done
}

# Main script execution

check_root

show_message "Starting Snort installation and configuration..."

# Update package lists
show_message "Updating package lists..."
apt-get update -y

# Install required packages
show_message "Installing required packages..."
apt-get install -y snort snort-rules-default

# Get network interface and home network from user
interface=$(get_network_interface)
home_net=$(get_home_network)

# Configure Snort
show_message "Configuring Snort..."

# 1. Edit snort.conf
sed -i "s/ipvar HOME_NET any/ipvar HOME_NET $home_net/g" /etc/snort/snort.conf
sed -i "s/ipvar EXTERNAL_NET \$HOME_NET/ipvar EXTERNAL_NET !\$HOME_NET/g" /etc/snort/snort.conf
sed -i "s/interface eth0/interface $interface/g" /etc/snort/snort.conf # Replace default interface (May not be present in all versions, so the error will be suppressed)

# 2. Enable community rules (you can choose other rule sets)
#    (Ensure that the community rules set is present in the downloaded rules)
sed -i 's/# oinkcode <oinkcode>/oinkcode <your_oinkcode>/' /etc/snort/snort.conf

# 3. (Optional) Disable specific rules (example)
# sed -i 's/include \$RULE_PATH\/example.rules/# include \$RULE_PATH\/example.rules/' /etc/snort/snort.conf

# Configure Snort to run as a service (default in newer versions)
# May require changing from 'disable' to 'enable' if an older version is used
systemctl enable snort

# Start Snort service
show_message "Starting Snort service..."
systemctl start snort

# Check Snort status
show_message "Checking Snort status..."
systemctl status snort

show_message "Snort installation and configuration completed!"
show_message "You can monitor Snort logs with: tail -f /var/log/snort/alert"