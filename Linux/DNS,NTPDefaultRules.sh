#!/bin/bash
#Flush rules
iptables -F
iptables -X

sudo iptables -P INPUT DROP
sudo iptables -P OUTPUT DROP
sudo iptables -P FORWARD DROP

#Allow traffic from exisiting/established connections
sudo iptables -A INPUT -m conntrack --cstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --cstate ESTABLISHED,RELATED -j ACCEPT

#Allow DNS Traffic
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

#Allow NTP traffic
sudo iptables -A INPUT -p udp --dport 123 -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

#Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT

#Allow to install
sudo iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

sudo iptables-save >/etc/iptables