#!/bin/bash

# --- Script to Configure Firewall Rules (iptables) ---

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

# Function to check if iptables is installed
check_iptables() {
    if ! command -v iptables &> /dev/null; then
        error "iptables is not installed. Please install it and try again."
    fi
}

# Function to flush existing iptables rules (optional)
flush_rules() {
    read -p "Do you want to flush existing iptables rules? (y/n): " flush_choice
    if [[ "$flush_choice" == "y" ]]; then
        info "Flushing existing iptables rules..."
        iptables -F
        iptables -X
        iptables -t nat -F
        iptables -t nat -X
        iptables -t mangle -F
        iptables -t mangle -X
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        info "Existing iptables rules flushed."
    else
        info "Keeping existing iptables rules."
    fi
}

# Function to configure inbound rules
configure_inbound() {
    info "Configuring inbound rules..."
    while true; do
        read -p "Enter an inbound port number (or 'done' to finish): " port
        if [[ "$port" == "done" ]]; then
            break
        fi

        # Basic input validation
        if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
            echo "Invalid port number. Please enter a number between 1 and 65535."
            continue
        fi

        read -p "Enter protocol (tcp/udp/all): " protocol
        if [[ ! "$protocol" =~ ^(tcp|udp|all)$ ]]; then
            echo "Invalid protocol. Please enter 'tcp', 'udp', or 'all'."
            continue
        fi
        
        if [[ "$protocol" == "all" ]]; then
            iptables -A INPUT -p tcp --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT
            iptables -A INPUT -p udp --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT
            info "Added rule to allow inbound TCP and UDP traffic on port $port"
        else
            iptables -A INPUT -p "$protocol" --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT
            info "Added rule to allow inbound $protocol traffic on port $port"
        fi
    done
}

# Function to configure outbound rules
configure_outbound() {
    info "Configuring outbound rules..."
    while true; do
        read -p "Enter an outbound port number (or 'done' to finish): " port
        if [[ "$port" == "done" ]]; then
            break
        fi

        # Basic input validation
        if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
            echo "Invalid port number. Please enter a number between 1 and 65535."
            continue
        fi

        read -p "Enter protocol (tcp/udp/all): " protocol
        if [[ ! "$protocol" =~ ^(tcp|udp|all)$ ]]; then
            echo "Invalid protocol. Please enter 'tcp', 'udp', or 'all'."
            continue
        fi

        if [[ "$protocol" == "all" ]]; then
            iptables -A OUTPUT -p tcp --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT
            iptables -A OUTPUT -p udp --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT
            info "Added rule to allow outbound TCP and UDP traffic on port $port"
        else
            iptables -A OUTPUT -p "$protocol" --dport "$port" -m state --state NEW,ESTABLISHED -j ACCEPT
            info "Added rule to allow outbound $protocol traffic on port $port"
        fi
    done
}

# Function to save iptables rules (distro-specific)
save_rules() {
    info "Saving iptables rules..."
    if [[ -f /etc/debian_version ]]; then # Debian/Ubuntu
        iptables-save > /etc/iptables/rules.v4
        if [[ ! -f /etc/network/if-pre-up.d/iptablesload ]]; then
          echo '#!/bin/sh
          /sbin/iptables-restore < /etc/iptables/rules.v4
          exit 0' > /etc/network/if-pre-up.d/iptablesload
          chmod +x /etc/network/if-pre-up.d/iptablesload
        fi
    elif [[ -f /etc/redhat-release ]]; then # RHEL/CentOS
        service iptables save
    else
        error "Could not determine the distribution. Please save iptables rules manually."
    fi
    info "iptables rules saved."
}

# --- Main Script ---

check_root
check_iptables
flush_rules # Optional: Flush existing rules
configure_inbound
configure_outbound

# Default policy: Drop everything else
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

save_rules

info "Firewall configuration complete!"