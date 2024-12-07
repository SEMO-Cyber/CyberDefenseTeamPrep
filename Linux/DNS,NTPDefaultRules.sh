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
apt install -y curl wget nmap fail2ban iptables-persistent



#
#   IPTables Rules
#
#

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


#
#   Fail2Ban Configuration
#
#

# Enable and start Fail2ban
echo "Enabling and starting Fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Configure Fail2ban
echo "Configuring Fail2ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Edit jail.local file
sed -i 's/bantime  = 10m/bantime  = 1h/' /etc/fail2ban/jail.local
sed -i 's/findtime  = 10m/findtime  = 30m/' /etc/fail2ban/jail.local
sed -i 's/maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local

# Add ignoreip (adjust as needed)
sed -i 's/ignoreip = 127.0.0.1\/8 ::1/ignoreip = 127.0.0.1\/8 ::1 172.20.0.0\/16/' /etc/fail2ban/jail.local

# Enable SSH protection
sed -i 's/\[sshd\]/[sshd]\nenabled = true/' /etc/fail2ban/jail.local

# Restart Fail2ban
echo "Restarting Fail2ban..."
systemctl restart fail2ban




#
#  NTP Configuration
#
#

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


#
#   Uninstall SSH, harden cron, final notes
#
#

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
echo "Check for cronjobs, services on timers, etc, THEN RESTART THE MACHINE. IT WILL UPDATE TO A BETTER KERNEL!!!!!!"
