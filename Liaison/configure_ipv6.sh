#!/bin/bash

# --- Script to Configure IPv6 Networking (Dual-Stack) ---

# Function to display messages in color
info() {
    echo -e "\e[32m[INFO] $1\e[0m" # Green
}

error() {
    echo -e "\e[31m[ERROR] $1\e[0m" # Red
    exit 1
}

# Function to check if the script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root."
    fi
}

# Function to generate a unique local IPv6 address (ULA)
generate_ula() {
    local prefix="fd$(openssl rand -hex 1):$(openssl rand -hex 2):$(openssl rand -hex 2)::"
    local interface_id=$(ip link show "$interface" | awk '/link\/ether/ {print $2}' | sed 's/://g' | cut -c 7-14)
    echo "$prefix$interface_id/64"
}

# --- Main Script ---

check_root

# --- Network Interface Configuration ---

# Prompt for the network interface
info "Available network interfaces:"
ip -o link show | awk '$2 != "lo:" {print $2}'

read -p "Enter the network interface to configure (e.g., eth0): " interface

# Validate interface
if ! ip link show "$interface" &> /dev/null; then
    error "Interface '$interface' not found."
fi

# --- IPv6 Address Configuration ---

# Determine if static or ULA address is desired
read -p "Do you want to use a static IPv6 address (s) or generate a Unique Local Address (ULA) (u)? [s/u]: " address_type

if [[ "$address_type" == "s" ]]; then
    # Static IPv6 address
    read -p "Enter the static IPv6 address (e.g., 2001:db8::1/64): " ipv6_address
    # Basic validation for static address format
    if [[ ! "$ipv6_address" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\/[0-9]{1,3}$ ]]; then
        error "Invalid IPv6 address format."
    fi
elif [[ "$address_type" == "u" ]]; then
    # Generate ULA
    ipv6_address=$(generate_ula)
    info "Generated ULA: $ipv6_address"
else
    error "Invalid choice. Please enter 's' for static or 'u' for ULA."
fi

# --- Apply Network Configuration ---

# Enable IPv6 forwarding (if not already enabled)
if ! sysctl -n net.ipv6.conf.all.forwarding | grep -q "1"; then
    sysctl -w net.ipv6.conf.all.forwarding=1
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    info "IPv6 forwarding enabled."
fi

# Add IPv6 address to the interface
ip -6 address add "$ipv6_address" dev "$interface"

# --- Verification ---

info "IPv6 configuration applied:"
ip -6 addr show dev "$interface"

info "You can now test connectivity using 'ping6' to the other machine's IPv6 address."

# --- Persistence (Distro-Specific) ---

# Debian/Ubuntu: Add to /etc/network/interfaces
if [[ -f /etc/debian_version ]]; then
    echo -e "\niface $interface inet6 static\n    address $ipv6_address" >> /etc/network/interfaces
    info "IPv6 configuration added to /etc/network/interfaces for persistence."
fi

# RHEL/CentOS: Add to ifcfg- file
if [[ -f /etc/redhat-release ]]; then
    if [[ ! -f /etc/sysconfig/network-scripts/ifcfg-"$interface" ]]; then
        error "Could not find ifcfg file for interface $interface."
    fi
    echo -e "\nIPV6INIT=yes\nIPV6ADDR=$ipv6_address" >> /etc/sysconfig/network-scripts/ifcfg-"$interface"
    info "IPv6 configuration added to ifcfg-$interface for persistence."
    
    # Restart NetworkManager
    info "Restarting NetworkManager..."
    systemctl restart NetworkManager
fi