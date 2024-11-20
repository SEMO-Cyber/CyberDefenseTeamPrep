#!/bin/bash

#super quick automatic script to install Splunk. Made with a heavy sprinkle of AI

# Define variables
SPLUNK_URL="https://download.splunk.com/products/splunk/releases/9.3.2/linux/splunk-9.3.2-d8bb32809498.x86_64.rpm"
SPLUNK_RPM="splunk-9.3.2-d8bb32809498.x86_64.rpm"

# Download the Splunk RPM package
echo "Downloading Splunk RPM package..."
wget -O $SPLUNK_RPM $SPLUNK_URL

# Check if the download was successful
if [ $? -ne 0 ]; then
    echo "Failed to download Splunk RPM package. Exiting."
    exit 1
fi

# Install the Splunk RPM package
echo "Installing Splunk..."
sudo rpm -i $SPLUNK_RPM

# Check if the installation was successful
if [ $? -ne 0 ]; then
    echo "Failed to install Splunk. Exiting."
    exit 1
fi

# Start Splunk and accept the license
echo "Starting Splunk and accepting the license..."
sudo /opt/splunk/bin/splunk start --accept-license

# Enable Splunk to start at boot
echo "Enabling Splunk to start at boot..."
sudo /opt/splunk/bin/splunk enable boot-start

echo "Splunk installation and setup completed successfully."
