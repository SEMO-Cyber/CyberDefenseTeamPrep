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
apt install -y curl wget iptables-persistent nmap cron


#
#   IPTables Rules
#
#

#Begin firewall rules
echo "Configuring firewall rules..."

# Flush existing rules
iptables -F
iptables -X

# Allow limited incomming ICMP traffic and log packets that dont fit the rules
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -m limit --limit 1/s --limit-burst 5 -j ACCEPT
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -j LOG --log-prefix "Rate-limit exceeded: " --log-level 4
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length ! --length 0:192 -j LOG --log-prefix "Invalid size: " --log-level 4
sudo iptables -A INPUT -p icmp --icmp-type echo-reply -m limit --limit 1/s --limit-burst 5 -j ACCEPT
sudo iptables -A INPUT -p icmp -j DROP

# Allow outgoing ICMP traffic
sudo iptables -A OUTPUT -p icmp -j ACCEPT

# Allow traffic from existing/established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow traffic on Splunk ports
iptables -A INPUT -p tcp --dport 9997 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 9997 -j ACCEPT

# Allow web access
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# Allow outgoing DNS traffic
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow outgoing NTP traffic  
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

# Allow outgoing SSH traffic
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Set default policies for ipv4 and ipv6
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Save the rules
iptables-save > /etc/iptables/rules.v4

#
#   Uninstall SSH, harden cron, final notes
#
#

# Uninstall SSH
#echo "Uninstalling SSH..."
#apt remove --purge openssh-server -y


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
