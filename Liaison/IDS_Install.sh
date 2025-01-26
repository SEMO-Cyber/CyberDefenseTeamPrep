#!/bin/bash

# --- Script to Install and Configure Snort IDS ---

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

# Function to install prerequisites
install_prerequisites() {
    info "Updating package list..."
    apt-get update || error "Failed to update package list."

    info "Installing prerequisites..."
    apt-get install -y build-essential libpcap-dev libpcre3-dev libdumbnet-dev bison flex zlib1g-dev liblzma-dev openssl libssl-dev libnghttp2-dev || error "Failed to install prerequisites."
}

# Function to download and install Snort
install_snort() {
    SNORT_VERSION="2.9.20"  # You can make this a user input if needed
    SNORT_TARBALL="snort-$SNORT_VERSION.tar.gz"
    DOWNLOAD_URL="https://www.snort.org/downloads/archive/snort/$SNORT_TARBALL"

    info "Downloading Snort $SNORT_VERSION..."
    wget "$DOWNLOAD_URL" || error "Failed to download Snort."

    info "Extracting Snort..."
    tar -xvzf "$SNORT_TARBALL" || error "Failed to extract Snort."

    cd "snort-$SNORT_VERSION" || error "Failed to change directory to Snort source."

    info "Configuring Snort..."
    ./configure --enable-sourcefire || error "Failed to configure Snort."

    info "Compiling Snort..."
    make || error "Failed to compile Snort."

    info "Installing Snort..."
    make install || error "Failed to install Snort."

    cd ..
    rm -rf "snort-$SNORT_VERSION" "$SNORT_TARBALL"

    # Install DAQ (Data Acquisition library)
    info "Installing DAQ..."
    cd daq-*
    ./configure
    make
    sudo make install
    cd ..

    #Update Shared Libraries
    sudo ldconfig

    info "Snort installed successfully."
}

# Function to configure network interface
configure_network() {
    # List available interfaces
    info "Available network interfaces:"
    ip -o -4 addr show | awk '$2 != "lo" {print $2, $4}'

    read -p "Enter the interface Snort should monitor (e.g., eth0): " interface

    # Validate interface (basic check)
    if ! ip link show "$interface" &> /dev/null; then
        error "Interface '$interface' not found."
    fi

    # Get IP address and subnet mask
    ip_address=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d '/' -f 1)
    subnet_mask=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d '/' -f 2)
    
    #convert subnet mask to CIDR notation if needed:
    if [[ "$subnet_mask" =~ ^[0-9]+$ ]]; then
        cidr_mask=$subnet_mask
    else
        cidr_mask=$(mask2cidr "$subnet_mask")
    fi


    # Ask for the network address
    while true; do
        read -p "Enter your network address in CIDR notation (e.g., 192.168.1.0/24, or press Enter to use default calculated from the interface IP): " network_address

        # Use default if user presses Enter
        if [[ -z "$network_address" ]]; then
            network_address="${ip_address}/${cidr_mask}"
            info "Using default network address: ${network_address}"
            break
        fi

        # Basic validation for CIDR format
        if [[ "$network_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2}$ ]]; then
            break
        else
            echo "Invalid network address format. Please use CIDR notation (e.g., 192.168.1.0/24)."
        fi
    done
    
    # Function to convert subnet mask to CIDR notation
    mask2cidr() {
        # Convert each octet to binary, concatenate, count leading 1s
        local bin_mask=$(echo "$1" | awk -F. '{ printf "%08b%08b%08b%08b", $1, $2, $3, $4 }')
        local cidr=0
        for (( i=0; i<${#bin_mask}; i++ )); do
            if [[ "${bin_mask:$i:1}" == "1" ]]; then
                cidr=$((cidr+1))
            else
                break
            fi
        done
        echo "$cidr"
    }

    # Configure snort.conf
    sed -i "s/ipvar HOME_NET any/ipvar HOME_NET $network_address/" /usr/local/etc/snort/snort.conf
    sed -i "s/var INTERFACE eth0/var INTERFACE $interface/" /usr/local/etc/snort/snort.conf

    info "Network interface configured in snort.conf."
}

# Function to download and configure rules
configure_rules() {
    info "Configuring Snort rules..."

    # 1. Download Community Rules (Free)
    read -p "Do you want to download the Snort Community Ruleset (free)? (y/n): " download_community_rules
    if [[ "$download_community_rules" == "y" ]]; then
        COMMUNITY_RULES_TARBALL="community-rules.tar.gz"
        COMMUNITY_DOWNLOAD_URL="https://www.snort.org/downloads/community/$COMMUNITY_RULES_TARBALL"

        info "Downloading Community Rules..."
        wget "$COMMUNITY_DOWNLOAD_URL" -O /usr/local/etc/snort/rules/$COMMUNITY_RULES_TARBALL || error "Failed to download Community Rules."

        info "Extracting Community Rules..."
        tar -xvzf /usr/local/etc/snort/rules/$COMMUNITY_RULES_TARBALL -C /usr/local/etc/snort/rules/ || error "Failed to extract Community Rules."

        rm /usr/local/etc/snort/rules/$COMMUNITY_RULES_TARBALL
    fi

    # 2. Enable/Disable Local Rules
    info "Local rules are stored in /usr/local/etc/snort/rules/local.rules"
    read -p "Do you want to enable the local rules file? (y/n): " enable_local_rules
    if [[ "$enable_local_rules" == "y" ]]; then
        sed -i "/include \$RULE_PATH\/local.rules/s/^#//" /usr/local/etc/snort/snort.conf
        info "Local rules enabled in snort.conf."
    else
        sed -i "/include \$RULE_PATH\/local.rules/s/^/#/" /usr/local/etc/snort/snort.conf
        info "Local rules remain commented out (disabled) in snort.conf."
    fi

    # 3. Oinkcode (Optional - for Registered or Subscriber Rules)
    read -p "Do you have a Snort Oinkcode (for Registered/Subscriber rules)? (y/n): " use_oinkcode
    if [[ "$use_oinkcode" == "y" ]]; then
        read -p "Enter your Oinkcode: " oinkcode

        # Download rules using Oinkcode
        wget "https://www.snort.org/rules/snortrules-snapshot-29200.tar.gz?oinkcode=$oinkcode" -O /usr/local/etc/snort/rules/snortrules.tar.gz || error "Failed to download rules with Oinkcode."

        # Extract and configure
        tar -xvzf /usr/local/etc/snort/rules/snortrules.tar.gz -C /usr/local/etc/snort/ || error "Failed to extract rules."
        rm /usr/local/etc/snort/rules/snortrules.tar.gz

        # You might need to uncomment include lines in snort.conf based on your rule selection
        info "Registered/Subscriber rules downloaded and extracted. Update snort.conf includes as needed."
    fi

    info "Snort rules configured."
}

# Function to create Snort systemd service
create_snort_service() {
    info "Creating Snort systemd service..."

    cat > /etc/systemd/system/snort.service << EOF
[Unit]
Description=Snort NIDS Daemon
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snort -q -u snort -g snort -c /usr/local/etc/snort/snort.conf -i eth0
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF

    # Create snort user and group
    groupadd snort
    useradd -r -s /sbin/nologin -d /usr/local/etc/snort -c snort -g snort snort

    # Permissions for directories and files
    mkdir /var/log/snort
    chown -R snort:snort /var/log/snort
    chmod -R g+w /var/log/snort
    touch /usr/local/etc/snort/rules/white_list.rules /usr/local/etc/snort/rules/black_list.rules
    chown snort:snort /usr/local/etc/snort/rules/white_list.rules /usr/local/etc/snort/rules/black_list.rules

    systemctl daemon-reload
    systemctl enable snort
    systemctl start snort

    info "Snort systemd service created and started."
}

# --- Main Script ---

check_root

install_prerequisites

install_snort

configure_network

configure_rules

create_snort_service

info "Snort installation and configuration complete!"