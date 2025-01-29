#!/bin/bash
# Automates the installation of the Splunk Universal Forwarder. Currently set to v9.1.1, but that is easily changed.
# Works with Debian, Ubuntu, CentOS, Fedora, and Oracle Linux. You need to run this as sudo

# This was put together as an amalgamation of code from my own work, other automatic installation scripts, and AI to tie everything together.
# Lots time went into this script. Be nice to it plz <3
#
# Samuel Brucker 2024-2025
#

set -e

# Define Splunk Forwarder variables
SPLUNK_VERSION="9.1.1"
SPLUNK_BUILD="64e843ea36b1"
SPLUNK_PACKAGE_TGZ="splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.tgz"
SPLUNK_DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/${SPLUNK_PACKAGE_TGZ}"
INSTALL_DIR="/opt/splunkforwarder"
INDEXER_IP="172.20.241.20"
RECEIVER_PORT="9997"

# Check the OS and install the necessary package
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "Unable to detect the operating system. Aborting."
  exit 1
fi

# Function to create the Splunk user and group
create_splunk_user() {
  if ! id -u splunk &>/dev/null; then
    echo "Creating splunk user and group..."
    sudo groupadd splunk
    sudo useradd -r -g splunk -d $INSTALL_DIR splunk
  else
    echo "Splunk user already exists."
  fi
}

# Function to install Splunk Forwarder
install_splunk() {
  echo "Downloading Splunk Forwarder tarball..."
  wget -O $SPLUNK_PACKAGE_TGZ $SPLUNK_DOWNLOAD_URL

  echo "Extracting Splunk Forwarder tarball..."
  sudo tar -xvzf $SPLUNK_PACKAGE_TGZ -C /opt
  rm -f $SPLUNK_PACKAGE_TGZ

  echo "Setting permissions..."
  create_splunk_user
  sudo chown -R splunk:splunk $INSTALL_DIR
}

# Function to add basic monitors
setup_monitors() {
  echo "Setting up basic monitors for Splunk..."
  MONITOR_CONFIG="$INSTALL_DIR/etc/system/local/inputs.conf"

  sudo bash -c "cat > $MONITOR_CONFIG" <<EOL
[monitor:///var/log]
index = main
sourcetype = syslog

[monitor:///var/log/messages]
index = main
sourcetype = syslog

[monitor:///var/log/secure]
index = main
sourcetype = syslog

[monitor:///var/log/dmesg]
index = main
sourcetype = syslog
EOL

  echo "Monitors added to inputs.conf."
}

# Function to configure the forwarder to send logs to the Splunk indexer
configure_forwarder() {
  echo "Configuring Splunk Universal Forwarder to send logs to $INDEXER_IP:$RECEIVER_PORT..."
  sudo $INSTALL_DIR/bin/splunk add forward-server $INDEXER_IP:$RECEIVER_PORT -auth admin:changeme
  echo "Forward-server configuration complete."
}

# Perform installation
install_splunk

# Enable Splunk service and accept license agreement
if [ -d "$INSTALL_DIR/bin" ]; then
  echo "Starting and enabling Splunk Universal Forwarder service..."
  sudo $INSTALL_DIR/bin/splunk start --accept-license --answer-yes --no-prompt
  sudo $INSTALL_DIR/bin/splunk enable boot-start

  # Add basic monitors
  setup_monitors

  # Configure forwarder to send logs to the Splunk indexer
  configure_forwarder

  # Restart Splunk to apply configuration
  sudo $INSTALL_DIR/bin/splunk restart
else
  echo "Installation directory not found. Something went wrong."
  exit 1
fi

# Verify installation
sudo $INSTALL_DIR/bin/splunk version

echo "Splunk Universal Forwarder v$SPLUNK_VERSION installation complete with basic monitors and forwarder configuration!"

# CentOS-specific fixes
# Wow I love CentOS 7 sooooo much
if [ "$ID" == "centos" ]; then
  echo "Applying CentOS-specific fixes..."

  # Remove AmbientCapabilities line from the systemd service file
  # Splunk does not work on CentOS 7 if you do not fix this. It's some weird permissions error with what Splunk is allowed to access/use on the system.
  SERVICE_FILE="/usr/lib/systemd/system/SplunkForwarder.service"
  if [ -f "$SERVICE_FILE" ]; then
    sudo sed -i '/AmbientCapabilities/d' "$SERVICE_FILE"
    echo "Removed AmbientCapabilities line from $SERVICE_FILE"
  fi

  # Reload systemd daemon
  sudo systemctl daemon-reload

  # Run Splunk again
  sudo systemctl restart SplunkForwarder
fi
