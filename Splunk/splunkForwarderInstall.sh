#!/bin/bash

# Script for installing the latest Splunk Universal Forwarder on supported Linux distributions
# Works with Debian, Ubuntu, CentOS, Fedora, and Oracle Linux
# Ensure you have root/sudo privileges before running this script

set -e

# Function to determine the latest version and build of Splunk Universal Forwarder
get_latest_version() {
  echo "Fetching the latest Splunk Universal Forwarder version information..."
  DOWNLOAD_PAGE="https://www.splunk.com/en_us/download/universal-forwarder.html"
  LATEST_VERSION=$(curl -s $DOWNLOAD_PAGE | grep -oP 'splunkforwarder-\K[0-9]+\.[0-9]+\.[0-9]+(?=-)' | head -n 1)
  LATEST_BUILD=$(curl -s $DOWNLOAD_PAGE | grep -oP "splunkforwarder-${LATEST_VERSION}-\K[0-9a-f]+(?=-linux)" | head -n 1)
  echo "Latest Version: $LATEST_VERSION"
  echo "Latest Build: $LATEST_BUILD"
}

# Function to download and install the Splunk Universal Forwarder on Debian/Ubuntu
install_deb() {
  PACKAGE_NAME="splunkforwarder-${LATEST_VERSION}-${LATEST_BUILD}-linux-2.6-amd64.deb"
  DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${LATEST_VERSION}/linux/${PACKAGE_NAME}"
  
  echo "Downloading Splunk Universal Forwarder DEB package..."
  wget -O $PACKAGE_NAME $DOWNLOAD_URL

  echo "Installing Splunk Universal Forwarder DEB package..."
  sudo dpkg -i $PACKAGE_NAME
  rm -f $PACKAGE_NAME
}

# Function to download and install the Splunk Universal Forwarder on RHEL-based systems (CentOS, Fedora, Oracle Linux)
install_rpm() {
  PACKAGE_NAME="splunkforwarder-${LATEST_VERSION}-${LATEST_BUILD}.x86_64.rpm"
  DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${LATEST_VERSION}/linux/${PACKAGE_NAME}"
  
  echo "Downloading Splunk Universal Forwarder RPM package..."
  wget -O $PACKAGE_NAME $DOWNLOAD_URL

  echo "Installing Splunk Universal Forwarder RPM package..."
  sudo rpm -i $PACKAGE_NAME
  rm -f $PACKAGE_NAME
}

# Determine the OS and install the necessary package
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "Unable to detect the operating system. Aborting."
  exit 1
fi

# Fetch the latest version and build information
get_latest_version

# Perform installation based on OS
case "$ID" in
  ubuntu|debian)
    echo "Detected Debian-based distribution: $PRETTY_NAME"
    install_deb
    ;;
  centos|fedora|ol|oraclelinux|rhel)
    echo "Detected RHEL-based distribution: $PRETTY_NAME"
    install_rpm
    ;;
  *)
    echo "Unsupported distribution: $ID"
    exit 1
    ;;
esac

# Enable Splunk service and accept license agreement
INSTALL_DIR="/opt/splunkforwarder"
if [ -d "$INSTALL_DIR/bin" ]; then
  echo "Starting and enabling Splunk Universal Forwarder service..."
  sudo $INSTALL_DIR/bin/splunk start --accept-license --answer-yes --no-prompt
  sudo $INSTALL_DIR/bin/splunk enable boot-start
else
  echo "Installation directory not found. Something went wrong."
  exit 1
fi

# Verify installation
sudo $INSTALL_DIR/bin/splunk version

echo "Splunk Universal Forwarder installation complete!"
