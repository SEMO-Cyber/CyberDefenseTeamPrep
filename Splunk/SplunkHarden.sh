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
iptables -A INPUT -p tcp --dport 9997 -m conntrack --ctstate NEW -m limit --limit 20/min --limit-burst 40 -j ACCEPT  #Splunk Forwarders
iptables -A OUTPUT -p tcp --sport 9997 -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 514 -m conntrack --ctstate NEW -m limit --limit 20/min --limit-burst 40 -j ACCEPT   #Logs from Palo
iptables -A OUTPUT -p tcp --sport 514 -m conntrack --ctstate ESTABLISHED -j ACCEPT
#sudo iptables -A INPUT -p tcp --dport 8089 -j ACCEPT   #NOT NEEDED
#sudo iptables -A OUTPUT -p tcp --sport 8089 -j ACCEPT  #NOT NEEDED
iptables -A INPUT -p tcp --dport 8000 -m conntrack --ctstate NEW -m limit --limit 20/min --limit-burst 40 -j ACCEPT  #Splunk webGUI
iptables -A OUTPUT -p tcp --sport 8000 -m conntrack --ctstate ESTABLISHED -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "DROP-IN:" --log-level 4 --log-ip-options --log-tcp-options --log-tcp-sequence
iptables -A OUTPUT -j LOG --log-prefix "DROP-OUT:" --log-level 4 --log-ip-options --log-tcp-options --log-tcp-sequence

# Save the rules
iptables-save > /etc/iptables/rules.v4


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
#Set the base directory for Splunk

echo "Hardening the Splunk configuration..."

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
SPLUNK_USERNAME="sysadmin"
SPLUNK_PASSWORD="$splunkPass"
SPLUNK_HOME="/opt/splunk"
CONF_FILE="/opt/splunk/etc/system/local/server.conf"



#Remove old conf file
#rm -f $CONF_FILE

#cat > $CONF_FILE << EOF
#[general]
#serverName = Splunk

#[sslConfig]
#cliVerifyServerName = false
#EOF



# Change admin password with proper error handling
if ! $SPLUNK_HOME/bin/splunk edit user sysadmin -password "$SPLUNK_PASSWORD" -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"; then
    echo "Error: Failed to change admin password"
    exit 1
fi

$SPLUNK_HOME/bin/splunk edit user admin -password $splunkPass -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"

#Remove all users except admin user. This is a little wordy in the output.
USERS=$($SPLUNK_HOME/bin/splunk list user -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}" | grep -v "sysadmin" | awk '{print $2}')

for USER in $USERS; do
    $SPLUNK_HOME/bin/splunk remove user $USER -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}"
done

#Lock down who is able to log in
#make sure files exist
touch "$SPLUNK_HOME/etc/system/local/authentication.conf"
touch "$SPLUNK_HOME/etc/system/local/authorize.conf"

# Edit authentication.conf
cat > $SPLUNK_HOME/etc/system/local/authentication.conf << EOF
[authentication]
authType = Splunk
authSettings = Splunk

[roleMap_Splunk]
sysadmin = admin

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

cat > "$SPLUNK_HOME/etc/system/local/inputs.conf" << EOF
# System logs (main index)
[monitor:///var/log/messages]
index = main
sourcetype = linux_messages
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue

[monitor:///var/log/secure]
index = _audit
sourcetype = linux_secure
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue

[monitor:///var/log/audit/audit.log]
index = _audit
sourcetype = linux_audit
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue

# System performance monitoring (main index)
[monitor:///var/log/sysstat/sa*]
index = main
sourcetype = linux_sysstat
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue

# Critical system logs (main index)
[monitor:///var/log/cron]
index = main
sourcetype = linux_cron
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue

[monitor:///var/log/maillog]
index = main
sourcetype = linux_maillog
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue

# Internal Splunk monitoring (_internal index)
[monitor:///opt/splunk/var/log/splunk/splunkd.log]
index = _internal
sourcetype = splunkd
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue

[monitor:///opt/splunk/var/log/splunk/splunkd_stderr.log]
index = _internal
sourcetype = splunkd_stderr
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue

[monitor:///opt/splunk/var/log/splunk/metrics.log]
index = _internal
sourcetype = splunkd_metrics
disabled = false
crcSalt = <SOURCE>
ignoreOlderThan = 7d
followTail = 0
queue = parsingQueue
EOF


# Configure receivers
cat > "$SPLUNK_HOME/etc/system/local/inputs.conf" << EOF
# TCP input for Splunk forwarders (port 9997)
[tcp://9997]
index = main
sourcetype = tcp:9997
connection_host = dns
disabled = false

# UDP input for syslog (port 514) - This is configured for Palo Alto. Use with the Palo Alto Add-on and App (installed onto Splunk)
[udp://514]
sourcetype = pan:firewall
no_appending_timestamp = true
index = pan_logs
EOF

#  ------------   NOT WORKING  ------------
#
# Install Palo Alto apps
#echo "Installing Palo Alto apps..."
#$SPLUNK_HOME/bin/splunk install app https://splunkbase.splunk.com/app/7523 -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"
#$SPLUNK_HOME/bin/splunk install app https://splunkbase.splunk.com/app/7505 -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"

# Configure UDP input for Palo Alto logs
echo "Configuring UDP input..."
cat > $SPLUNK_HOME/etc/system/local/inputs.conf << EOL
[udp://514]
sourcetype = pan:firewall
no_appending_timestamp = true
index = pan_logs
EOL

# Disable distributed search
echo "Disabling distributed search"
echo "[distributedSearch]" > $SPLUNK_HOME/etc/system/local/distsearch.conf
echo "disabled = true" >> $SPLUNK_HOME/etc/system/local/distsearch.conf

# Restart Splunk to apply changes
echo "Restarting Splunk to apply changes..."
$SPLUNK_HOME/bin/splunk restart

echo "MAKE SURE YOU ENUMERATE!!!"
echo "Check for cronjobs, services on timers, etc. Also do a manual search through Splunk. Once done, run sudo yum update -y and then restart the machine. Have fun!"
