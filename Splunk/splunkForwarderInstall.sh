#!/bin/bash

# Define variables
SPLUNK_URL="https://download.splunk.com/products/universalforwarder/releases/8.2.6/linux/splunkforwarder-8.2.6-87bd0d129ee3-linux-2.6-x86_64.tgz"
SPLUNK_TGZ="splunkforwarder-8.2.6-87bd0d129ee3-linux-2.6-x86_64.tgz"
SPLUNK_INSTALL_DIR="/opt/splunkforwarder"
SPLUNK_SERVER="172.20.241.20:9997"

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!" 
   exit 1
fi

# Detect the OS type
OS_TYPE=$(lsb_release -si 2>/dev/null || cat /etc/*release | grep ^ID= | cut -d= -f2)

# Function to install dependencies for Debian/Ubuntu-based systems
install_debian_ubuntu_dependencies() {
    echo "Installing dependencies for Debian/Ubuntu..."
    apt-get update && apt-get install -y wget tar
}

# Function to install dependencies for CentOS/Fedora-based systems
install_centos_fedora_dependencies() {
    echo "Installing dependencies for CentOS/Fedora..."
    yum install -y wget tar
}

# Function to install dependencies for Oracle Linux
install_oracle_linux_dependencies() {
    echo "Installing dependencies for Oracle Linux..."
    yum install -y wget tar
}

# Function to download and install Splunk forwarder
install_splunk_forwarder() {
    echo "Downloading and installing Splunk Universal Forwarder..."
    
    # Download the Splunk forwarder
    wget -O $SPLUNK_TGZ $SPLUNK_URL

    # Extract the tarball
    tar -xvf $SPLUNK_TGZ -C /opt/

    # Remove the tarball after extraction
    rm -f $SPLUNK_TGZ

    # Change ownership to root
    chown -R root:root $SPLUNK_INSTALL_DIR

    # Accept the license agreement
    $SPLUNK_INSTALL_DIR/bin/splunk start --accept-license --answer-yes

    # Enable Splunk to start on boot
    $SPLUNK_INSTALL_DIR/bin/splunk enable boot-start -user root
}

# Function to configure Splunk forwarder to forward logs to the specified server
configure_splunk_forwarder() {
    echo "Configuring Splunk Universal Forwarder..."

    # Set the forwarder destination
    $SPLUNK_INSTALL_DIR/bin/splunk add forward-server $SPLUNK_SERVER

    # Configure to monitor specific directories (example: /var/log)
    $SPLUNK_INSTALL_DIR/bin/splunk add monitor /var/log

    # Restart Splunk forwarder
    $SPLUNK_INSTALL_DIR/bin/splunk restart
}

# Install dependencies based on OS type
case $OS_TYPE in
    debian|ubuntu)
        install_debian_ubuntu_dependencies
        ;;
    centos|fedora)
        install_centos_fedora_dependencies
        ;;
    ol)
        install_oracle_linux_dependencies
        ;;
    *)
        echo "Unsupported OS: $OS_TYPE"
        exit 1
        ;;
esac

# Install and configure Splunk forwarder
install_splunk_forwarder
configure_splunk_forwarder

echo "Splunk Universal Forwarder installation and configuration is complete!"
