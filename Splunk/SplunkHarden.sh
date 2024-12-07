#!/bin/bash
#Hardening script for Splunk. Assumes some version of Oracle Linux.

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Determine package manager
if command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
else
    echo "Neither dnf nor yum found. Exiting."
    exit 1
fi

# Check if nmap is already installed
if command -v nmap &> /dev/null; then
    echo "nmap is already installed"
    exit 0
fi

# Update and upgrade the system
echo "Updating and upgrading the system..."
$PKG_MANAGER update -y

# Install necessary tools and dependencies
echo "Installing necessary tools and dependencies..."
$PKG_MANAGER install -y curl wget nmap fail2ban iptables-services cronie

# Verify iptables-save is installed
if ! command -v iptables-save &> /dev/null; then
    echo "iptables-save not found. Installing..."
    $PKG_MANAGER install -y iptables
fi


#
#   IPTables Rules
#
#

# Configure firewall rules using iptables
echo "Configuring firewall rules..."

# Flush existing rules
iptables -F
iptables -X

# Set default policies
iptables -P INPUT DROP
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP

# Allow traffic from existing/established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT

# Allow incoming ICMP traffic (ping)
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Allow DNS traffic
iptables -A INPUT -p tcp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# Allow NTP
iptables -A INPUT -p udp --dport 123 -j ACCEPT

# Allow incoming traffic on port 8000 (Splunk web interface)
iptables -A INPUT -p tcp --dport 8000 -j ACCEPT

# Allow incoming traffic on port 8089 (Splunk data input)
iptables -A INPUT -p tcp --dport 8089 -j ACCEPT

# Allow incoming traffic on port 8191 (Splunk data input)
iptables -A INPUT -p tcp --dport 8191 -j ACCEPT

# Allow incoming traffic on port 8065 (Splunk data input)
iptables -A INPUT -p tcp --dport 8065 -j ACCEPT

# Allow incoming traffic on port 9997 (Splunk data input)
iptables -A INPUT -p tcp --dport 9997 -j ACCEPT

# Allow incoming traffic from specific IP addresses or subnets
# Internal, e1/2 subnet
iptables -A INPUT -s 172.20.240.0/24 -j ACCEPT
# User, e1/4 subnet 
iptables -A INPUT -s 172.20.242.0/24 -j ACCEPT
# Public, e1/1 subnet 
iptables -A INPUT -s 172.20.241.0/24 -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4

# Drop all other incoming traffic
iptables -A INPUT -j DROP

# Save iptables rules
iptables-save > /etc/iptables.rules

#
#   Uninstall SSH, harden cron, final notes
#
#

# Uninstall SSH
echo "Uninstalling SSH..."
$PKG_MANAGER remove --purge openssh-server -y


#harden cron
echo "Locking down Cron and AT permissions..."
touch /etc/cron.allow
chmod 600 /etc/cron.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/cron.deny

touch /etc/at.allow
chmod 600 /etc/at.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/at.deny


# Final steps
echo "Final steps..."
$PKG_MANAGER autoremove -y

echo "MAKE SURE YOU ENUMERATE!!!"
echo "Check for cronjobs, services on timers, etc, THEN RESTART THE MACHINE. IT WILL UPDATE TO A BETTER KERNEL!!!!!!"