#!/bin/bash
#Hardening script for Fedora 21. God I hate this operating system.
#CCDC has taught me that a RedHat OS is just a hint at how it makes me want to decorate my walls.


# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

echo "Setting device banner"
cat > /etc/issue << EOF
LEGAL DISCLAIMER: This computer system is the property of Team 10 LLC. By using this system, all users acknowledge notice of, and agree to comply with, the Acceptable User of Information Technology Resources Polity (AUP). 
By using this system, you consent to these terms and conditions. Use is also consent to monitoring, logging, and use of logging to prosecute abuse. 
If you do NOT wish to comply with these terms and conditions, you must LOG OFF IMMEDIATELY.
EOF

# Determine package manager
if command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
else
    echo "Neither dnf nor yum found. Exiting."
    exit 1
fi

# Install necessary tools and dependencies
echo "Installing necessary tools and dependencies..."
$PKG_MANAGER install -y curl wget iptables-services sed cronie auditd 



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
#   Initial Backup
#
#
# Define the main backup directory and subdirectory
MAIN_BACKUP_DIR="/etc/backs"
BACKUP_DIR="$MAIN_BACKUP_DIR/initial"

# Check if /etc/backs exists, if not, create it
if [ ! -d "$MAIN_BACKUP_DIR" ]; then
    echo "Backup directory does not exist. Creating /etc/backs..."
    mkdir -p "$MAIN_BACKUP_DIR"
fi

# Ensure the specific backup subdirectory exists
mkdir -p "$BACKUP_DIR"

echo "Starting Initial Backup..."

# Backup critical system files before any changes
tar -czvf $BACKUP_DIR/initial_backup.tar.gz \
    /root \
    /var/www/html \
    /etc/roundcubemail \
    /etc/httpd \
    /etc/dovecot \
    /etc/postfix \
    /etc/cron* \
    /etc/passwd \
    /etc/group \
    /etc/shadow \
    /etc/sudoers* \
    /etc/hosts \
    /etc/hostname \
    /etc/aliases \
    /etc/systemd \
    /etc/yum* \
    /etc/resolv.conf \
    /usr/share/httpd \
    /srv/vmail \
    /etc/sysconfig \
    /usr/share/roundcubemail \
    /usr/share/dovecot

echo "Initial Backup Completed Successfully and stored in $BACKUP_DIR"
echo "Setting permission only to root"
chmod 700 /etc/backs

#
#   System Hardening
#
#

# 1. Secure File Permissions
echo "Setting secure permissions for critical files..."
chmod 600 /etc/shadow
chmod 600 /etc/gshadow
chmod 600 /etc/ssh/sshd_config
chmod 640 /var/log/messages
chmod 640 /var/log/secure

echo "File permissions set."

# 2. Restrict Access to Root User
echo "Restricting access to root user..."
chmod 700 /root
chown root:root /root
echo "Root access restricted."

#3. Removing shell access to other sus users
echo "Removing shell access to apache, vmail, system users"
sudo usermod -s /sbin/nologin apache
sudo usermod -s /sbin/nologin vmail
sudo usermod -s /sbin/nologin system

#4. Removing SUID Bit in /bin/dash
sudo chmod u-s /bin/dash


# 4. Lock Down Cron Jobs
echo "Securing cron jobs..."
touch /etc/cron.allow
touch /etc/at.allow
echo 'root' > /etc/cron.allow
echo 'root' > /etc/at.allow
chmod 600 /etc/cron.allow /etc/at.allow
chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly

echo "Cron jobs secured."


# Final steps
echo "Final steps..."
$PKG_MANAGER autoremove -y

echo "MAKE SURE YOU ENUMERATE!!!"
echo "Check for cronjobs, services on timers, etc, then update and upgrade the machine. THEN RESTART. It will update the kernel!!"
