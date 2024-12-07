#!/bin/bash
#Hardening script for Splunk. Assumes some version of Oracle Linux.

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Determine package manager
if command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
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
$PKG_MANAGER install -y curl wget nmap iptables-services cronie

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

# Allow traffic from existing/established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow incoming Splunk traffic
iptables -A INPUT -p tcp --dport 9997 -j ACCEPT  # Splunk forwarder port
iptables -A INPUT -m udp --dport 9997 -j ACCEPT  #udp forwarder
iptables -A INPUT -p tcp --dport 8089 -j ACCEPT  # Splunk management port
iptables -A INPUT -p tcp --dport 8000 -j ACCEPT   # Splunk web interface (HTTPS)

# Allow outgoing Splunk traffic
iptables -A OUTPUT -p tcp --sport 9997 -j ACCEPT
iptables -A OUTPUT -p udp --sport 9997 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 8089 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 8000 -j ACCEPT

sudo iptables -A OUTPUT -p tcp --sport 80 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 443 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow DNS traffic
iptables -A OUTPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p udp --dport 53 -m state --state ESTABLISHED -j ACCEPT

# Allow NTP traffic
iptables -A OUTPUT -p udp --sport 123 -j ACCEPT
iptables -A INPUT -p udp --dport 123 -m state --state ESTABLISHED -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4

# Set default policies
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP


# Save the rules
iptables-save > /etc/iptables/rules.v4

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
