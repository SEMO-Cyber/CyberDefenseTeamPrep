#!/bin/bash

# This script is safe and legit. It's short, read and confirm that. The label "DoNotRun__" is so that my teammates don't accidentally perform a full Splunk installation
# instead of the forwarder installation lol. Again, this is safe, just don't run it in comp because you'll have a bad time undoing this.
# super quick automatic script to install Splunk 9.3.2
# Mostly original with a little sprinkle of AI
#
# Samuel Brucker 2024-2025


# Define variables
#SPLUNK_VERSION="9.4.2"
#SPLUNK_BUILD="e9664af3d956"

SPLUNK_VERSION="9.3.2"
SPLUNK_BUILD="d8bb32809498"
SPLUNK_PASS="Changeme1!"

# Detect package manager
if which dnf >/dev/null 2>&1; then
    DISTRO="rhel"
    PKG_MANAGER="dnf"
elif which yum >/dev/null 2>&1; then
    DISTRO="rhel"
    PKG_MANAGER="yum"
elif which apt >/dev/null 2>&1; then
    DISTRO="debian"
    PKG_MANAGER="apt"
else
    echo "Unsupported distribution. No compatible package manager found (dnf, yum, or apt)."
    exit 1
fi

# Set Splunk package and URL based on distribution
if [ "$DISTRO" = "rhel" ]; then
    SPLUNK_PKG="splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}.x86_64.rpm"
    SPLUNK_URL="https://download.splunk.com/products/splunk/releases/${SPLUNK_VERSION}/linux/${SPLUNK_PKG}"
elif [ "$DISTRO" = "debian" ]; then
    SPLUNK_PKG="splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-amd64.deb"
    SPLUNK_URL="https://download.splunk.com/products/splunk/releases/${SPLUNK_VERSION}/linux/${SPLUNK_PKG}"
fi

# Install prerequisites for RHEL-based systems
if [ "$DISTRO" = "rhel" ]; then
    echo "Installing prerequisites..."
    sudo $PKG_MANAGER install -y libxcrypt-compat
    if [ $? -ne 0 ]; then
        echo "Failed to install prerequisites. Exiting."
        exit 1
    fi
fi

# Download the Splunk package
echo "Downloading Splunk package..."
wget -O $SPLUNK_PKG $SPLUNK_URL
if [ $? -ne 0 ]; then
    echo "Failed to download Splunk package. Exiting."
    exit 1
fi

# Install the Splunk package
echo "Installing Splunk..."
if [ "$DISTRO" = "rhel" ]; then
    sudo $PKG_MANAGER localinstall -y $SPLUNK_PKG
elif [ "$DISTRO" = "debian" ]; then
    sudo $PKG_MANAGER install -y ./$SPLUNK_PKG
fi
if [ $? -ne 0 ]; then
    echo "Failed to install Splunk. Exiting."
    exit 1
fi

# Create user-seed.conf to set admin credentials
echo "Creating user-seed.conf for admin account..."
sudo mkdir -p /opt/splunk/etc/system/local
cat > /opt/splunk/etc/system/local/user-seed.conf <<EOF
[user_info]
USERNAME = admin
PASSWORD = Changeme1!
EOF

sudo chown splunk:splunk /opt/splunk/etc/system/local/user-seed.conf
sudo chmod 600 /opt/splunk/etc/system/local/user-seed.conf

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

# Configure Splunk to receive logs on ports 9997 and 514
echo "Configuring Splunk ports..."
sudo /opt/splunk/bin/splunk add udp 514 -auth admin:$SPLUNK_PASS
sudo /opt/splunk/bin/splunk add tcp 9997 -auth admin:$SPLUNK_PASS

# Final restart
echo "Performing final restart..."
sudo /opt/splunk/bin/splunk restart
if [ $? -ne 0 ]; then
    echo "Final restart failed. Please investigate."
    exit 1
fi

# Clean up user-seed.conf for security
echo "Cleaning up user-seed.conf..."
sudo rm /opt/splunk/etc/system/local/user-seed.conf

echo "Splunk installation and configuration complete!"
