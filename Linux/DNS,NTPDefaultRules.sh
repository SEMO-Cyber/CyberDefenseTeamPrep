#!/bin/bash


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
apt install -y curl wget nmap tripwire fail2ban iptables-persistent

# Configure firewall rules using iptables
echo "Configuring firewall rules..."


#Flush rules
iptables -F
iptables -X

sudo iptables -P INPUT DROP
sudo iptables -P OUTPUT DROP
sudo iptables -P FORWARD DROP

#Allow traffic from exisiting/established connections
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

#Allow DNS Traffic
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

#Allow NTP traffic
sudo iptables -A INPUT -p udp --dport 123 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

#Allow Splunk Forwarding
sudo iptables -A OUTPUT -p tcp --dport 9997 -j ACCEPT

#Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A FORWARD -i lo -j ACCEPT
sudo iptables -A FORWARD -o lo -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "IPTABLES-DROP:" --log-level 4

#Allow to install
sudo iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT


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

# DNS (Bind9) directories and files
/etc/bind                  -> $(SEC_BIN) ;
/var/named                 -> $(SEC_BIN) ;
/var/named/chroot          -> $(SEC_BIN) ;

# NTP directories and files
/etc/ntp.conf              -> $(SEC_BIN) ;
/var/lib/ntp               -> $(SEC_BIN) ;
/var/log/ntp               -> $(SEC_BIN) ;

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

# Configure NTP
echo "Configuring NTP..."
cat > /etc/ntp.conf << EOF
driftfile /var/lib/ntp/ntp.drift

restrict default nomodify notrap noquery
restrict 127.0.0.1
restrict ::1

pool 0.debian.pool.ntp.org iburst
pool 1.debian.pool.ntp.org iburst
pool 2.debian.pool.ntp.org iburst
pool 3.debian.pool.ntp.org iburst

disable monitor
EOF

systemctl restart ntp

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

echo "MAKE SURE YOU ENUMERATE!!!"