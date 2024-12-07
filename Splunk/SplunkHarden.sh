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
$PKG_MANAGER install -y curl wget nmap tripwire fail2ban iptables-services cronie

# Verify iptables-save is installed
if ! command -v iptables-save &> /dev/null; then
    echo "iptables-save not found. Installing..."
    $PKG_MANAGER install -y iptables
fi

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

# Configure Fail2ban
echo "Configuring Fail2ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i 's/bantime  = 10m/bantime  = 1h/' /etc/fail2ban/jail.local
systemctl restart fail2ban

# Configure Tripwire
echo "Configuring Tripwire..."
tripwire-setup-keyfiles

# Edit the Tripwire policy file
cat >> /etc/tripwire/twpol.txt << EOF

# Splunk directories and files
/opt/splunk                -> $(SEC_BIN) ;
/opt/splunk/etc            -> $(SEC_BIN) ;
/opt/splunk/etc/system     -> $(SEC_BIN) ;
/opt/splunk/etc/apps       -> $(SEC_BIN) ;
/opt/splunk/etc/users      -> $(SEC_BIN) ;
/opt/splunk/var            -> $(SEC_BIN) ;
/opt/splunk/var/log        -> $(SEC_BIN) ;
/opt/splunk/var/run        -> $(SEC_BIN) ;
/opt/splunk/bin            -> $(SEC_BIN) ;
/opt/splunk/lib            -> $(SEC_BIN) ;

# Critical system directories and files
/etc/passwd                -> $(SEC_BIN) ;
/etc/shadow                -> $(SEC_BIN) ;
/etc/group                 -> $(SEC_BIN) ;
/etc/gshadow               -> $(SEC_BIN) ;
/etc/sudoers               -> $(SEC_BIN) ;
/etc/hosts                 -> $(SEC_BIN) ;
/etc/hosts.allow           -> $(SEC_BIN) ;
/etc/hosts.deny            -> $(SEC_BIN) ;
/etc/ssh                   -> $(SEC_BIN) ;
/etc/ssh/sshd_config       -> $(SEC_BIN) ;
/etc/iptables              -> $(SEC_BIN) ;
/etc/iptables/rules.v4     -> $(SEC_BIN) ;
/etc/iptables/rules.v6     -> $(SEC_BIN) ;
EOF

# Regenerate the Tripwire policy file
twadmin --create-polfile /etc/tripwire/twpol.txt

# Update the Tripwire database
tripwire --update --twrfile /var/lib/tripwire/report/$(hostname)-$(date +%Y%m%d)-$(date +%H%M%S).twr

# Initialize Tripwire
tripwire --init

# Set up a cron job to run Tripwire checks regularly
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/sbin/tripwire --check") | crontab -

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

echo "MAKE SURE YOU STILL ENUMERATE!!"