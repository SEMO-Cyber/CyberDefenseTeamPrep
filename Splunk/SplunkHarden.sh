#!/bin/bash
#Hardening script for Splunk. Assumes some version of Oracle Linux 9.2
#CCDC has taught me that a RedHat OS is just a hint at how it makes me want to decorate my walls.
# UPDATE: It is now two or three months after that "joke" and I am installing a Fedora-based distro on my laptop. It's immutable, so I don't think it really counts, but worth a mention.
# I still, mostly, stand by my words.
#
# This is based off a mixture of my work (and many, many, many hours of testing), online guides, forums, splunk documentation, and ofc, AI to smooth the process over. 
# It's WIP, there are minor bugs here and there and a few sections could use a rewrite, but it should work about 90-95% of the way. Certainly better than nothing!
#
# Samuel Brucker 2024-2025

#For debugging. This is an easy way to see where a fatal error happens in this script. 
#set -euo pipefail
#trap 'echo "Error occurred at line $LINENO"' ERR

# Add at the beginning of the script
LOG_FILE="/var/log/splunk_harden_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

SPLUNK_HOME="/opt/splunk"

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

#Start the basic box hardening
echo "Starting the basic hardening."

echo "Setting device banner"
cat > /etc/issue << EOF
LEGAL DISCLAIMER: This computer system is the property of Team 10 LLC. By using this system, all users acknowledge notice of, and agree to comply with, the Acceptable User of Information Technology Resources Polity (AUP). 
By using this system, you consent to these terms and conditions. Use is also consent to monitoring, logging, and use of logging to prosecute abuse. 
If you do NOT wish to comply with these terms and conditions, you must LOG OFF IMMEDIATELY.
EOF

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
iptables -Z

# Set default policies
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow limited incoming ICMP traffic and log packets that don't fit the rules
#sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -m limit --limit 1/s --limit-burst 5 -j ACCEPT
#sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -j LOG --log-prefix "Rate-limit exceeded: " --log-level 4
#sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length ! --length 0:192 -j LOG --log-prefix "Invalid size: " --log-level 4
#sudo iptables -A INPUT -p icmp --icmp-type echo-reply -m limit --limit 1/s --limit-burst 5 -j ACCEPT
#sudo iptables -A INPUT -p icmp -j DROP

# Allow DNS traffic
iptables -A OUTPUT -p udp --dport 53 -m limit --limit 20/min --limit-burst 50 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -m limit --limit 20/min --limit-burst 50 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -m state --state ESTABLISHED -j ACCEPT

# Allow HTTP/HTTPS traffic
iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m limit --limit 100/min --limit-burst 200 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m limit --limit 100/min --limit-burst 200 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# Allow Splunk-specific traffic
iptables -A INPUT -p tcp --dport 9997 -m conntrack --ctstate NEW -j ACCEPT  #Splunk Forwarders
iptables -A OUTPUT -p tcp --sport 9997 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

iptables -A INPUT -p tcp --dport 514 -m conntrack --ctstate NEW -j ACCEPT   #Logs from Palo
iptables -A OUTPUT -p tcp --sport 514 -m conntrack --ctstate ESTABLISHED -j ACCEPT

#sudo iptables -A INPUT -p tcp --dport 8089 -j ACCEPT   #NOT NEEDED
#sudo iptables -A OUTPUT -p tcp --sport 8089 -j ACCEPT  #NOT NEEDED

iptables -A INPUT -p tcp --dport 8000 -m conntrack --ctstate NEW -j ACCEPT  #Splunk webGUI
iptables -A OUTPUT -p tcp --sport 8000 -m conntrack --ctstate ESTABLISHED -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "DROP-IN:" --log-level 4 --log-ip-options --log-tcp-options --log-tcp-sequence
iptables -A OUTPUT -j LOG --log-prefix "DROP-OUT:" --log-level 4 --log-ip-options --log-tcp-options --log-tcp-sequence

mkdir /etc/iptables

# Save the rules
iptables-save > /etc/iptables/rules.v4

# disable and remove unneeded firewalld. It's not needed.
systemctl stop firewalld

systemctl disable firewalld

$PKG_MANAGER remove firewalld -y


#
#   Backup Configurations
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
cp /etc/iptables/rules.v4 "$BACKUP_DIR"                 # A redundant backup for the iptable rules

echo "Backing up original Splunk configurations..."
mkdir -p "$BACKUP_DIR/splunkORIGINAL"
cp -R "$SPLUNK_HOME" "$BACKUP_DIR/splunkORIGINAL"

#
#   System Hardening
#
#

echo "restricting user creation to root only"
chmod 700 /usr/sbin/useradd
chmod 700 /usr/sbin/groupadd

# Clear crontab
echo "Clearing crontab..."
echo "" > /etc/crontab

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

# Uninstall SSH
echo "Uninstalling SSH..."
$PKG_MANAGER remove openssh-server -y

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

# Set the banner for Splunk
cat > "$SPLUNK_HOME/etc/system/local/global-banner.conf" << EOF
[BANNER_MESSAGE_SINGLETON]
global_banner.visible = true
global_banner.message = WARNING: NO UNAUTHORIZED ACCESS. This is property of Team 10 LLC. Unauthorized users will be prosecuted and tried to the furthest extent of the law!
global_banner.background_color = red
EOF


# Set better permissions for important Splunk configurations
echo "Setting secure local file permissions..."
chmod -R 700 "$SPLUNK_HOME/etc/system/local"
chmod -R 700 "$SPLUNK_HOME/etc/system/default"
chown -R splunk:splunk "$SPLUNK_HOME/etc"


#echo "Changing Splunk admin password..."
while true; do
    echo "Enter new password for Splunk admin user: "
    stty -echo
    read splunkPass
    stty echo

    echo "Confirm new password: "
    stty -echo
    read confirmPass
    stty echo

    if [ "$splunkPass" = "$confirmPass" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

# Set consistent authentication variables
SPLUNK_USERNAME="admin"
SPLUNK_PASSWORD="$splunkPass"
OG_SPLUNK_PASSWORD="changeme"

# Change admin password with proper error handling
if ! $SPLUNK_HOME/bin/splunk edit user $SPLUNK_USERNAME -password "$SPLUNK_PASSWORD" -auth "$SPLUNK_USERNAME:$OG_SPLUNK_PASSWORD"; then
    echo "Error: Failed to change admin password"
    exit 1
fi

$SPLUNK_HOME/bin/splunk edit user SPLUNK_USERNAME -password $splunkPass -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"

#Remove all users except admin user. This is a little wordy in the output.
USERS=$($SPLUNK_HOME/bin/splunk list user -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}" | grep -v "$SPLUNK_USERNAME" | awk '{print $2}')

for USER in $USERS; do
    $SPLUNK_HOME/bin/splunk remove user $USER -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}"
done

# Configure receivers
cat > "$SPLUNK_HOME/etc/system/local/inputs.conf" << EOF
#TCP input for Splunk forwarders (port 9997)
#Commented out as I prefer being able to see this listener in the webgui, so I use Splunk CLI to add this automatically
#[tcp://9997]
#index = main
#sourcetype = tcp:9997
#connection_host = dns
#disabled = false

[tcp://514]
sourcetype = pan:firewall
no_appending_timestamp = true
index = pan_logs
EOF

#Add the 9997 listener using splunk CLI
$SPLUNK_HOME/bin/splunk enable listen 9997 -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"

#Add the index for Palo logs
$SPLUNK_HOME/bin/splunk add index pan_logs

# Install Palo Alto Networks apps
echo "Installing Palo Alto Networks apps..."

# Clone the Palo Alto splunk app
git clone https://github.com/PaloAltoNetworks/SplunkforPaloAltoNetworks.git SplunkforPaloAltoNetworks
mv SplunkforPaloAltoNetworks "$SPLUNK_HOME/etc/apps/"

# Clone the Palo Alto splunk add-on
git clone https://github.com/PaloAltoNetworks/Splunk_TA_paloalto.git Splunk_TA_paloalto
mv Splunk_TA_paloalto "$SPLUNK_HOME/etc/apps/"

# Disable distributed search
echo "Disabling distributed search"
echo "[distributedSearch]" > $SPLUNK_HOME/etc/system/local/distsearch.conf
echo "disabled = true" >> $SPLUNK_HOME/etc/system/local/distsearch.conf

# Restart Splunk to apply changes
echo "Restarting Splunk to apply changes..."
$SPLUNK_HOME/bin/splunk restart

#Backup Splunk again now that changes have been made
echo "Backing up latest Splunk configurations..."
mkdir -p "$BACKUP_DIR/splunk"
cp -R "$SPLUNK_HOME" "$BACKUP_DIR/splunk"
echo "Verifying backup integrity..."
find "$BACKUP_DIR/splunk" -type f -size +0 -print0 | xargs -0 md5sum > "$BACKUP_DIR/splunk/md5sums.txt"
find "$BACKUP_DIR/splunk" -type f -size 0 -delete


############################
# WIP, not functioning yet #
############################

#Lock down who is able to log in
#make sure files exist
#touch "$SPLUNK_HOME/etc/system/local/authentication.conf"
#touch "$SPLUNK_HOME/etc/system/local/authorize.conf"

# Edit authentication.conf
#cat > $SPLUNK_HOME/etc/system/local/authentication.conf << EOF
#[authentication]
#authType = Splunk
#authSettings = Splunk

#[roleMap_Splunk]
#sysadmin = admin

#[authenticationResponse]
#attributemap = Splunk:role -> role
#EOF

# Edit authorize.conf
#cat > $SPLUNK_HOME/etc/system/local/authorize.conf << EOF
#[role_admin]
#importRoles = admin
#srchJobsQuota = 50
#rtSrchJobsQuota = 50
#srchDiskQuota = 10000
#srchFilter = *
#srchIndexesAllowed = *
#srchIndexesDefault = main
#srchMaxTime = 8640000
#rtSrchMaxTime = 30
#srchMaxTotalDiskQuota = 500000
#importRoles = user
#srchJobsQuota = 50
#rtSrchJobsQuota = 50
#srchDiskQuota = 10000
#srchFilter = *
#srchIndexesAllowed = *
#srchIndexesDefault = main
#srchMaxTime = 8640000
#rtSrchMaxTime = 30
#srchMaxTotalDiskQuota = 500000
#EOF

#  ------------   NOT WORKING  ------------
#
# Install Palo Alto apps
#echo "Installing Palo Alto apps..."
#$SPLUNK_HOME/bin/splunk install app https://splunkbase.splunk.com/app/7523 -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"
#$SPLUNK_HOME/bin/splunk install app https://splunkbase.splunk.com/app/7505 -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"

echo "\n\nMAKE SURE YOU ENUMERATE!!!"
echo "Check for cronjobs, services on timers, etc. Also do a manual search through Splunk. Once done, run sudo yum update -y and then restart the machine. Have fun!\n\n"


# Add a final output to help quickly search for rogue system accounts. This isn't exactly a sophisticated sweep, just something to help find some minor plants quicker.
echo "Looking for system accounts with permissions under 500. Double check these, but still make sure you check the /etc/shadow file for more accounts." 
echo "Permissions under or above 500 don't instantly mean an account is legit/malicious."
awk -F: '$3 >= 500 && $1 != "sysadmin" && $1 != "splunk" {print $1}' /etc/passwd | while read user; do
    echo "Found system account: $user"
    echo "To lock this account manually, run:"
    echo "  sudo usermod -L $user    # Lock the account"
    echo "  sudo usermod -s /sbin/nologin $user    # Prevent shell login"
    echo "---"
done
