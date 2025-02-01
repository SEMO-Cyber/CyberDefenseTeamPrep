#!/bin/bash

# This script is safe and legit. It's short, read and confirm that. The label "DoNotRun__" is so that my teammates don't accidentally perform a full Splunk installation
# instead of the forwarder installation lol. Again, this is safe, just don't run it in comp because you'll have a bad time undoing this.
# super quick automatic script to install Splunk 9.3.2
# Mostly original with a little sprinkle of AI
# Samuel Brucker 2024-2025

# Define variables
SPLUNK_URL="https://download.splunk.com/products/splunk/releases/9.3.2/linux/splunk-9.3.2-d8bb32809498.x86_64.rpm"
SPLUNK_RPM="splunk-9.3.2-d8bb32809498.x86_64.rpm"

# Install prerequisites
echo "Installing prerequisites..."
dnf install -y libxcrypt-compat
if [ $? -ne 0 ]; then
    echo "Failed to install prerequisites. Exiting."
    exit 1
fi

# Download the Splunk RPM package
echo "Downloading Splunk RPM package..."
wget -O $SPLUNK_RPM $SPLUNK_URL
if [ $? -ne 0 ]; then
    echo "Failed to download Splunk RPM package. Exiting."
    exit 1
fi

# Install the Splunk RPM package
echo "Installing Splunk..."
sudo dnf localinstall -y $SPLUNK_RPM
if [ $? -ne 0 ]; then
    echo "Failed to install Splunk. Exiting."
    exit 1
fi

# Start Splunk and accept license
echo "Starting Splunk and accepting license..."
sudo /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
if [ $? -ne 0 ]; then
    echo "Failed to start Splunk. Exiting."
    exit 1
fi

# Enable boot start
echo "Enabling boot start..."
sudo /opt/splunk/bin/splunk enable boot-start --accept-license --answer-yes --no-prompt
if [ $? -ne 0 ]; then
    echo "Failed to enable boot start. Exiting."
    exit 1
fi

# Set admin credentials. Currently, this is set to sysadmin/Changeme1!
echo "Setting admin password..."
sudo /opt/splunk/bin/splunk edit user sysadmin -password Changeme1! -auth admin:changeme
if [ $? -ne 0 ]; then
    echo "Failed to set admin password. Exiting."
    exit 1
fi

# Restart Splunk for changes to take effect
echo "Restarting Splunk..."
sudo /opt/splunk/bin/splunk restart
if [ $? -ne 0 ]; then
    echo "Failed to restart Splunk. Exiting."
    exit 1
fi

# Configure Splunk to receive logs on ports 9997 and 514.
echo "Configuring Splunk ports..."
sudo /opt/splunk/bin/splunk add udp 514 -auth admin:Changeme1!
sudo /opt/splunk/bin/splunk add tcp 9997 -auth admin:Changeme1!

# Final restart
echo "Performing final restart..."
sudo /opt/splunk/bin/splunk restart
if [ $? -ne 0 ]; then
    echo "Final restart failed. Please investigate."
    exit 1
fi

echo "Splunk installation and configuration complete!"
