#!/bin/bash

# Flush existing iptables rules
iptables -F

#Allow for already established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow incoming ICMP traffic
iptables -A INPUT -p icmp -m state --state NEW,ESTABLISHED -j ACCEPT

#Allow ntpstat
iptables -A INPUT -p udp -m udp -j ACCEPT

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


# Drop all other incoming traffic
iptables -A INPUT -j DROP

# Save iptables rules
iptables-save > /etc/iptables.rules

echo "# Require the root pw when booting into single user mode" >> /etc/inittab
echo "~~:S:wait:/sbin/sulogin" >> /etc/inittab
echo "Don't allow any nut to kill the server"
perl -npe 's/ca::ctrlaltdel:\/sbin\/shutdown/#ca::ctrlaltdel:\/sbin\/shutdown/' -i /etc/inittab

echo "Disabling USB Mass Storage"
echo "blacklist usb-storage" > /etc/modprobe.d/blacklist-usbstorage