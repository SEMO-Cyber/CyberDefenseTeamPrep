#!/bin/bash

# Script to install Splunk Universal Forwarder 9.1.1
# Works on Debian, Ubuntu, CentOS, Fedora, Oracle Linux

SPLUNK_VERSION="9.1.1"
SPLUNK_DOWNLOAD_BASE="https://download.splunk.com/products/universalforwarder/releases/$SPLUNK_VERSION/linux"

# Determine the OS type
if [[ -f /etc/debian_version ]]; then
    OS="debian"
elif [[ -f /etc/redhat-release ]]; then
    OS="redhat"
else
    echo "Unsupported operating system. Exiting."
    exit 1
fi

# Update and install prerequisites
if [[ "$OS" == "debian" ]]; then
    echo "Detected Debian-based system. Installing prerequisites..."
    sudo apt update
    sudo apt install -y wget dpkg
    PACKAGE_URL="$SPLUNK_DOWNLOAD_BASE/splunkforwarder-${SPLUNK_VERSION}-linux-2.6-amd64.deb"
elif [[ "$OS" == "redhat" ]]; then
    echo "Detected Red Hat-based system. Installing prerequisites..."
    sudo yum install -y wget
    PACKAGE_URL="$SPLUNK_DOWNLOAD_BASE/splunkforwarder-${SPLUNK_VERSION}-linux-2.6-x86_64.rpm"
fi

# Download the Splunk Forwarder package
echo "Downloading Splunk Universal Forwarder..."
wget -O splunkforwarder.$([[ "$OS" == "debian" ]] && echo "deb" || echo "rpm") $PACKAGE_URL

# Install Splunk Forwarder
if [[ "$OS" == "debian" ]]; then
    echo "Installing Splunk Universal Forwarder on Debian-based system..."
    sudo dpkg -i splunkforwarder.deb
elif [[ "$OS" == "redhat" ]]; then
    echo "Installing Splunk Universal Forwarder on Red Hat-based system..."
    sudo rpm -ivh splunkforwarder.rpm
fi

# Clean up downloaded package
rm -f splunkforwarder.$([[ "$OS" == "debian" ]] && echo "deb" || echo "rpm")

# Enable Splunk service and set to start on boot
echo "Enabling and starting Splunk Universal Forwarder..."
sudo /opt/splunkforwarder/bin/splunk start --accept-license --answer-yes
sudo /opt/splunkforwarder/bin/splunk enable boot-start

echo "Splunk Universal Forwarder 9.1.1 installation complete!"
