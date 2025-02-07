#!/bin/bash
#Hardening script for Splunk. Assumes some version of Oracle Linux 9.2
#CCDC has taught me that a RedHat OS is just a hint at how it makes me want to decorate my walls.
# Samuel Brucker 2024-2025

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

#Start the basic box hardening
echo "Starting the basic hardening."

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
fi

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

# Allow limited incoming ICMP traffic and log packets that dont fit the rules
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -m limit --limit 1/s --limit-burst 5 -j ACCEPT
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -j LOG --log-prefix "Rate-limit exceeded: " --log-level 4
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length ! --length 0:192 -j LOG --log-prefix "Invalid size: " --log-level 4
sudo iptables -A INPUT -p icmp --icmp-type echo-reply -m limit --limit 1/s --limit-burst 5 -j ACCEPT
sudo iptables -A INPUT -p icmp -j DROP

# Allow outgoing ICMP traffic
sudo iptables -A OUTPUT -p icmp -j ACCEPT

# Allow established connections
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS traffic
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --sport 53 -m state --state ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p tcp --sport 53 -m state --state ESTABLISHED -j ACCEPT

# Allow HTTP/HTTPS traffic
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 443 -j ACCEPT

# Allow Splunk-specific traffic
sudo iptables -A INPUT -p tcp --dport 9997 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 9997 -j ACCEPT
#sudo iptables -A INPUT -p tcp --dport 8089 -j ACCEPT  # Commented out as requested
#sudo iptables -A OUTPUT -p tcp --sport 8089 -j ACCEPT  # Commented out as requested
sudo iptables -A INPUT -p tcp --dport 8000 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 8000 -j ACCEPT

# Log dropped packets
sudo iptables -A INPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4
sudo iptables -A OUTPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4

# Set default policies
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Save the rules
iptables-save > /etc/iptables/rules.v4

#
#   Backup Configuration
#
#

# Create backup directory if it doesn't exist
BACKUP_DIR="/etc/BacService/"
mkdir -p "$BACKUP_DIR"

# Backup network interface configurations (critical for security)
echo "Backing up network interface configurations..."
cp -R /etc/sysconfig/network-scripts/* "$BACKUP_DIR"    # Network interface configs
cp /etc/sysconfig/network "$BACKUP_DIR"                 # Network configuration
cp /etc/resolv.conf "$BACKUP_DIR"                       # DNS configuration

#
#   System Hardening
#
#

# Clear crontab
echo "Clearing crontab..."
echo "" > /etc/crontab

# Password Management
echo "Setting new passwords..."

# Set root password
echo "Enter new root password: "
stty -echo
read rootPass
stty echo
echo "root:$rootPass" | chpasswd

# Set sysadmin password
echo "Enter new sysadmin password: "
stty -echo
read sysadminPass
stty echo
echo "sysadmin:$sysadminPass" | chpasswd

# Uninstall SSH
echo "Uninstalling SSH..."
$PKG_MANAGER remove --purge openssh-server -y

# Harden cron
echo "Locking down Cron and AT permissions..."
touch /etc/cron.allow
chmod 600 /etc/cron.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/cron.deny

touch /etc/at.allow
chmod 600 /etc/at.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/at.deny

# Final steps
echo "Final steps for the basic box hardening..."
$PKG_MANAGER autoremove -y


#
#   Splunk Security Hardening
#
#

echo "Hardening the Splunk configuration..."

#echo "Changing Splunk admin password..."
#echo "Enter new password for Splunk admin user: "
#stty -echo
#read splunkPass
#stty echo
#echo "Confirm new password: "
#stty -echo
#read confirmPass
#stty echo


# Disable distributed search
#echo "Disabling distruted search"
#echo "[distributedSearch]" > $SPLUNK_HOME/etc/system/local/distsearch.conf
#echo "disabled = true" >> $SPLUNK_HOME/etc/system/local/distsearch.conf

#if [ "$splunkPass" != "$confirmPass" ]; then
#    echo "Passwords do not match. Please try again."
#    exit 1
#fi

#/opt/splunk/bin/splunk edit user admin -password $splunkPass -auth admin:$splunkPass

#Remove all users except admin user. This is a little wordy in the output.
#USERS=$(/opt/splunk/bin/splunk list user -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}" | grep -v "sysadmin" | awk '{print $2}')

#for USER in $USERS; do
#    /opt/splunk/bin/splunk remove user $USER -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}"
#done


#Lock down who is able to log in

# Edit authentication.conf
cat > $SPLUNK_HOME/etc/system/local/authentication.conf << EOF
[authentication]
authType = Splunk
authSettings = Splunk

[roleMap_Splunk]
admin = admin

[authenticationResponse]
attributemap = Splunk:role -> role
EOF

# Edit authorize.conf
cat > $SPLUNK_HOME/etc/system/local/authorize.conf << EOF
[role_admin]
importRoles = admin
srchJobsQuota = 50
rtSrchJobsQuota = 50
srchDiskQuota = 10000
srchFilter = *
srchIndexesAllowed = *
srchIndexesDefault = main
srchMaxTime = 8640000
rtSrchMaxTime = 30
srchMaxTotalDiskQuota = 500000
importRoles = user
srchJobsQuota = 50
rtSrchJobsQuota = 50
srchDiskQuota = 10000
srchFilter = *
srchIndexesAllowed = *
srchIndexesDefault = main
srchMaxTime = 8640000
rtSrchMaxTime = 30
srchMaxTotalDiskQuota = 500000
EOF


/opt/splunk/bin/splunk restart 


echo "MAKE SURE YOU ENUMERATE!!!"
echo "Check for cronjobs, services on timers, etc. Also do a manual search through Splunk. Once done, run sudo yum update -y and then restart the machine. Have fun!"
