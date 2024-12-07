#!/bin/bash
#Scraped together from a multitude of scripts, ideas, and a dash of AI for easy documentation and suggestions
#Hardening script for the workstation Ubuntu. My networkers use this box, plz be gentle read team. 



# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi


# Update and upgrade the system
echo "Updating and upgrading the system..."
apt update && apt upgrade -y


# Install necessary tools and dependencies
echo "Installing necessary tools and dependencies..."
apt install -y curl wget iptables-persistent nmap tripwire snort cron


#Begin firewall rules
echo "Configuring firewall rules..."

#Flush rules
iptables -F
iptables -X

iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

#Allow traffic from exisiting/established connections
iptables -A INPUT -m conntrack --cstate ESTABLISHED,RELATED -j ACCEPT


#Allow Splunk Forwarding
iptables -A OUTPUT -p tcp --dport 9997 -j ACCEPT

#Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT

#Allow web access
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT


# Allow DNS traffic
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -m state --state ESTABLISHED -j ACCEPT

# Allow NTP traffic  
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
iptables -A INPUT -p udp --sport 123 -m state --state ESTABLISHED -j ACCEPT


#Allow access to Splunk webGUI and management
iptables -A OUTPUT -p tcp --dport 8000 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 8089 -j ACCEPT

#Save the rules
iptables-save > /etc/iptables/rules.v4


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
apt remove --purge openssh-server -y


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
apt autoremove -y
echo "MAKE SURE YOU STILL ENUMERATE!!"

