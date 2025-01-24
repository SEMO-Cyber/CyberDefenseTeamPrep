#!/bin/bash

# Script for installing Splunk Universal Forwarder v9.1.1 on supported Linux distributions
# Works with Debian, Ubuntu, CentOS, Fedora, and Oracle Linux
# Ensure you have root/sudo privileges before running this script

set -e

# Define Splunk Forwarder variables
SPLUNK_VERSION="9.1.1"
SPLUNK_BUILD="9a45dc0f2ebf"
SPLUNK_PACKAGE_DEB="splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.deb"
SPLUNK_PACKAGE_RPM="splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.rpm"
SPLUNK_DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux"
INSTALL_DIR="/opt/splunkforwarder"

# Check the OS and install the necessary package
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "Unable to detect the operating system. Aborting."
  exit 1
fi

# Function to install Splunk Forwarder on Debian/Ubuntu
install_deb() {
  echo "Downloading Splunk Forwarder DEB package..."
  wget -O $SPLUNK_PACKAGE_DEB ${SPLUNK_DOWNLOAD_URL}/${SPLUNK_PACKAGE_DEB}

  echo "Installing Splunk Forwarder DEB package..."
  sudo dpkg -i $SPLUNK_PACKAGE_DEB
  rm -f $SPLUNK_PACKAGE_DEB
}

# Function to install Splunk Forwarder on RHEL-based systems (CentOS, Fedora, Oracle Linux)
install_rpm() {
  echo "Downloading Splunk Forwarder RPM package..."
  wget -O $SPLUNK_PACKAGE_RPM ${SPLUNK_DOWNLOAD_URL}/${SPLUNK_PACKAGE_RPM}

  echo "Installing Splunk Forwarder RPM package..."
  sudo rpm -i $SPLUNK_PACKAGE_RPM
  rm -f $SPLUNK_PACKAGE_RPM
}

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

echo "Splunk Universal Forwarder v$SPLUNK_VERSION installation complete!"
