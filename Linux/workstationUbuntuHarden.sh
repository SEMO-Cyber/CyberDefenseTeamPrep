#!/bin/bash
#Scraped together from a multitude of scripts, ideas, and a dash of AI for easy documentation and suggestions



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
apt install -y curl wget gnupg2 ca-certificates lsb-release iptables-persistent nmap tripwire snort


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
tripwire-init


# Uninstall SSH
echo "Uninstalling SSH..."
apt remove --purge openssh-server -y


# Final steps
echo "Final steps..."
apt autoremove -y
echo "Rebooting the system to make sure all updates and changes have taken place."
echo "7 seconds..."
echo "enumerate a little after this!"


sleep 6
reboot