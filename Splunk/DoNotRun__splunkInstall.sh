#!/bin/bash

#super quick automatic script to install Splunk 9.3.2
# Mostly original with a little sprinkle of AI
# Samuel Brucker 2024-2025

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
