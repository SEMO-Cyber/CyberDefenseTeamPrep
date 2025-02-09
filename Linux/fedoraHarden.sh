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

# Allow limited incomming ICMP traffic and log packets that dont fit the rules
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -m limit --limit 1/s --limit-burst 5 -j ACCEPT
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -j LOG --log-prefix "ICMP - Rate-limit exceeded: " --log-level 4
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length ! --length 0:192 -j LOG --log-prefix "ICMP - Invalid size: " --log-level 4
sudo iptables -A INPUT -p icmp --icmp-type echo-reply -m limit --limit 1/s --limit-burst 5 -j ACCEPT
sudo iptables -A INPUT -p icmp -j DROP

# Allow outgoing ICMP traffic
sudo iptables -A OUTPUT -p icmp -j ACCEPT
# Allow traffic from existing/established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT

# Allow incoming LDAP traffic
iptables -A INPUT -p tcp --dport 389 -j ACCEPT
iptables -A INPUT -p tcp --dport 636 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 389 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 636 -j ACCEPT

# Allow IMAP traffic
iptables -A INPUT -p tcp --dport 143 -j ACCEPT
iptables -A INPUT -p tcp --dport 993 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 143 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 993 -j ACCEPT

# Allow SMTP traffic
iptables -A INPUT -p tcp --dport 25 -j ACCEPT
iptables -A INPUT -p tcp --dport 465 -j ACCEPT
iptables -A INPUT -p tcp --dport 587 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 25 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 465 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 587 -j ACCEPT

# Allow POP3 traffic
iptables -A INPUT -p tcp --dport 110 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 110 -j ACCEPT

# Allow incoming and outgoing HTTP/HTTPS traffic
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# Allow outgoing NTP traffic
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

# Allow Splunk forwarder traffic
iptables -A OUTPUT -p tcp --dport 9997 -j ACCEPT
iptables -A INPUT -p tcp --dport 9997 -j ACCEPT

# Allow outgoing DNS traffic
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4

# Drop all other incoming traffic
# Set default policies
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Save iptables rules
iptables-save > /etc/iptables.rules


#
#   System Hardening
#
#

echo "restricting user creation to root only"
chmod 700 /usr/sbin/useradd
chmod 700 /usr/sbin/groupadd

# Password Management
echo "Setting new passwords..."

# Set root password
while true; do
    echo "Enter new root password: "
    stty -echo
    read rootPass
    stty echo
    echo "Confirm root password: "
    stty -echo
    read confirmRootPass
    stty echo

    if [ "$rootPass" = "$confirmRootPass" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

echo "root:$rootPass" | chpasswd

# Set sysadmin password
while true; do
    echo "Enter new sysadmin password: "
    stty -echo
    read sysadminPass
    stty echo
    echo "Confirm sysadmin password: "
    stty -echo
    read confirmSysadminPass
    stty echo

    if [ "$sysadminPass" = "$confirmSysadminPass" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

echo "sysadmin:$sysadminPass" | chpasswd


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
