#!/bin/bash

# Script for installing Splunk Universal Forwarder v9.1.1 on supported Linux distributions
# Works with Debian, Ubuntu, CentOS, Fedora, and Oracle Linux
# Ensure you have root/sudo privileges before running this script

set -e

# Define Splunk Forwarder variables
SPLUNK_VERSION="9.1.1"
SPLUNK_BUILD="64e843ea36b1"
SPLUNK_PACKAGE_TGZ="splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.tgz"
SPLUNK_DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/${SPLUNK_PACKAGE_TGZ}"
INSTALL_DIR="/opt/splunkforwarder"

# Check the OS and install the necessary package
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "Unable to detect the operating system. Aborting."
  exit 1
fi

# Function to install Splunk Forwarder
install_splunk() {
  echo "Downloading Splunk Forwarder tarball..."
  wget -O $SPLUNK_PACKAGE_TGZ $SPLUNK_DOWNLOAD_URL

  echo "Extracting Splunk Forwarder tarball..."
  sudo tar -xvzf $SPLUNK_PACKAGE_TGZ -C /opt
  rm -f $SPLUNK_PACKAGE_TGZ

  echo "Setting permissions..."
  sudo chown -R splunk:splunk $INSTALL_DIR
}

# Perform installation
install_splunk

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
