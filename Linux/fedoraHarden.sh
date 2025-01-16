#!/bin/bash
#Hardening script for Fedora 21. God I hate this operating system.
#CCDC has taught me that a RedHat OS is just a hint at how it makes me want to decorate my walls.


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

# Update and upgrade the system
echo "Updating and upgrading the system..."
$PKG_MANAGER update -y

# Install necessary tools and dependencies
echo "Installing necessary tools and dependencies..."
$PKG_MANAGER install -y curl wget nmap iptables-services cronie auditd



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

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT

# Allow incoming LDAP traffic
iptables -A INPUT -p tcp --dport 389 -j ACCEPT
iptables -A INPUT -p tcp --dport 636 -j ACCEPT

# Allow incoming IMAP traffic
iptables -A INPUT -p tcp --dport 143 -j ACCEPT
iptables -A INPUT -p tcp --dport 993 -j ACCEPT

# Allow incoming SMTP traffic
iptables -A INPUT -p tcp --dport 25 -j ACCEPT
iptables -A INPUT -p tcp --dport 465 -j ACCEPT
iptables -A INPUT -p tcp --dport 587 -j ACCEPT

# Allow incoming HTTP/HTTPS traffic for Roundcube
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow incoming NTP traffic
iptables -A INPUT -p udp --dport 123 -j ACCEPT

# Allow icmp
iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT

# Allow Splunk forwarder traffic
iptables -A OUTPUT -p tcp --sport 9997 -j ACCEPT

# Allow outgoing DNS traffic
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4


# Drop all other incoming traffic
# Set default policies
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Save iptables rules
iptables-save > /etc/iptables.rules


#
#   Uninstall SSH, harden cron, final notes
#
#

# Uninstall SSH
echo "Uninstalling SSH..."
dnf remove --purge openssh-server -y

# Harden cron
echo "Locking down Cron and AT permissions..."
touch /etc/cron.allow
chmod 600 /etc/cron.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/cron.deny

touch /etc/at.allow
chmod 600 /etc/at.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/at.deny

# Final steps
echo "Final steps..."
dnf autoremove -y

echo "MAKE SURE YOU ENUMERATE!!!"
echo "Check for cronjobs, services on timers, etc, THEN RESTART THE MACHINE. IT WILL UPDATE TO A BETTER KERNEL!!!!!!"
