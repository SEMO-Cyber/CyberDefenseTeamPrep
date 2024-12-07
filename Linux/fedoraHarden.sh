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
$PKG_MANAGER install -y nmap tripwire fail2ban iptables-services cronie

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

# Allow Splunk forwarder traffic
iptables -A OUTPUT -p tcp --dport 9997 -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4

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

# LDAP directories and files
/etc/openldap             -> $(SEC_BIN) ;
/var/lib/ldap             -> $(SEC_BIN) ;

# Dovecot directories and files
/etc/dovecot              -> $(SEC_BIN) ;
/var/lib/dovecot          -> $(SEC_BIN) ;

# Roundcube directories and files
/var/www/roundcubemail     -> $(SEC_BIN) ;
/etc/roundcubemail         -> $(SEC_BIN) ;

# Tripwire directories and files
/usr/sbin/tripwire         -> $(SEC_BIN) ;
/etc/tripwire              -> $(SEC_BIN) ;
/var/lib/tripwire          -> $(SEC_BIN) ;
EOF

# Regenerate the Tripwire policy file
twadmin --create-polfile /etc/tripwire/twpol.txt

# Update the Tripwire database
tripwire --update --twrfile /var/lib/tripwire/report/$(hostname)-$(date +%Y%m%d)-$(date +%H%M%S).twr

# Initialize Tripwire
tripwire --init

# Set up a cron job to run Tripwire checks regularly
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/sbin/tripwire --check") | crontab -

# Configure LDAP
echo "Configuring LDAP..."
# Add LDAP configuration here

# Configure Dovecot
echo "Configuring Dovecot..."
# Add Dovecot configuration here

# Configure Roundcube
echo "Configuring Roundcube..."
# Add Roundcube configuration here

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
