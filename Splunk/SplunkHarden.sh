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

# Perform backup of Splunk and related files
echo "Backing up Splunk configuration..."
cp -R /opt/splunk/etc "$BACKUP_DIR"                    # Main configuration directory
cp -R /opt/splunk/etc/system/local "$BACKUP_DIR"        # Interface directory
cp /etc/systemd/system/splunk.service "$BACKUP_DIR"     # Service file
cp /etc/hosts "$BACKUP_DIR"
cp /etc/passwd "$BACKUP_DIR"
cp /etc/group "$BACKUP_DIR"
cp /etc/shadow "$BACKUP_DIR"

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


echo "Changing Splunk admin password..."
echo "Enter new password for Splunk admin user: "
stty -echo
read splunkPass
stty echo
echo "Confirm new password: "
stty -echo
read confirmPass
stty echo

if [ "$splunkPass" != "$confirmPass" ]; then
    echo "Passwords do not match. Please try again."
    exit 1
fi

/opt/splunk/bin/splunk edit user admin -password $splunkPass -auth admin:changeme


# Remove all users except admin
echo "Removing all users except admin..."
/opt/splunk/bin/splunk user list | grep -v "admin" | while read -r user; do
    /opt/splunk/bin/splunk remove user $user
done

# Remove all receivers and listeners
echo "Removing current receivers and listeners..."
/opt/splunk/bin/splunk disable listen
/opt/splunk/bin/splunk remove listen
/opt/splunk/bin/splunk disable receive
/opt/splunk/bin/splunk remove receive

# Remove all forwarders
echo "Removing forwarders..."
/opt/splunk/bin/splunk disable forwarder
/opt/splunk/bin/splunk remove forward-server

# Remove all authentication tokens
echo "Removing authentication tokens..."
/opt/splunk/bin/splunk tokens all -delete

# Configure strict authentication settings
echo "Configuring authentication settings..."
/opt/splunk/bin/splunk edit cluster-config -auth splunk-system-user -secret splunk-system-user-secret
/opt/splunk/bin/splunk edit authentication general-settings -requireClientCert true
/opt/splunk/bin/splunk edit authentication general-settings -allowSso false
/opt/splunk/bin/splunk edit authentication general-settings -allowBasicAuth false

# Disable unnecessary Splunk features
echo "Disabling unnecessary features..."
/opt/splunk/bin/splunk disable kvstore
/opt/splunk/bin/splunk disable distsearch

# Set strict security settings
echo "Setting strict security settings..."
/opt/splunk/bin/splunk set min-ssl-version tls1.2
/opt/splunk/bin/splunk set cipher-suite-group modern
/opt/splunk/bin/splunk set requireClientCert true
/opt/splunk/bin/splunk set enableSplunkWebSSL true


# Configure local data inputs for Splunk logs
echo "Setting up local data inputs..."
/opt/splunk/bin/splunk add monitor /opt/splunk/var/log/splunk -index _internal
/opt/splunk/bin/splunk add monitor /var/log -index main
/opt/splunk/bin/splunk add monitor /var/log/secure -index main
/opt/splunk/bin/splunk add monitor /var/log/auth -index main

# Configure receiver on port 9997
echo "Setting up receiver..."
/opt/splunk/bin/splunk enable listen 9997 -auth admin:$splunkPass
/opt/splunk/bin/splunk restart

# Create indexes
echo "Creating indexes..."
/opt/splunk/bin/splunk add index web -auth admin:$splunkPass
/opt/splunk/bin/splunk add index windows -auth admin:$splunkPass
/opt/splunk/bin/splunk add index network -auth admin:$splunkPass
/opt/splunk/bin/splunk add index dns -auth admin:$splunkPass

# Install Palo Alto apps
echo "Installing Palo Alto apps..."
/opt/splunk/bin/splunk install app https://splunkbase.splunk.com/app/1622/release/7.0.1/download -auth admin:$splunkPass
/opt/splunk/bin/splunk install app https://splunkbase.splunk.com/app/491/download -auth admin:$splunkPass

# Configure UDP input for Palo Alto logs
echo "Configuring UDP input..."
cat > /opt/splunk/etc/system/local/inputs.conf << EOL
[udp://514]
sourcetype = pan:firewall
no_appending_timestamp = true
index = pan_logs
EOL


# Restart Splunk to apply changes
echo "Restarting Splunk to apply changes..."
/opt/splunk/bin/splunk restart



echo "MAKE SURE YOU ENUMERATE!!!"
echo "Check for cronjobs, services on timers, etc. Once done, run sudo yum update -y and then restart the machine. Have fun!"
