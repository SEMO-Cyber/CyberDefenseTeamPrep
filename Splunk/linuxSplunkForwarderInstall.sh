#!/bin/bash
# Automates the installation of the Splunk Universal Forwarder. Currently set to v9.1.1, but that is easily changed.
# Works with Debian, Ubuntu, CentOS, Fedora, and Oracle Linux. You need to run this as sudo

# This was put together as an amalgamation of code from my own work, other automatic installation scripts, and AI to tie everything together.
# Lots time went into this script. Be nice to it plz <3
#
# Samuel Brucker 2024-2025
#

# Define Splunk Forwarder variables
SPLUNK_VERSION="9.1.1"
SPLUNK_BUILD="64e843ea36b1"
SPLUNK_PACKAGE_TGZ="splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-x86_64.tgz"
SPLUNK_DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/${SPLUNK_PACKAGE_TGZ}"
INSTALL_DIR="/opt/splunkforwarder"
INDEXER_IP="172.20.241.20"
RECEIVER_PORT="9997"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="Changeme1!"  # Replace with a secure password

# Pretty colors :)
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[0;33m'
BLUE=$'\e[0;34m'
NC=$'\e[0m'  #No Color - resets the color back to default

# Make sure this is being run as root or sudo
if [[ $EUID -ne 0 ]]; then
    echo "${RED}This script must be run as root or with sudo.${NC}"
    exit 1
fi

# Check the OS and install the necessary packageå
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "${RED}Unable to detect the operating system. Aborting.${NC}"
  exit 1
fi

# Output detected OS
echo "${GREEN}Detected OS ID: $ID ${NC}"

# Function to create the Splunk user and group
create_splunk_user() {
  if ! id -u splunk &>/dev/null; then
    echo "${BLUE}Creating splunk user and group...${NC}"
    sudo groupadd splunk
    sudo useradd -r -g splunk -d $INSTALL_DIR splunk
  else
    echo "${GREEN}Splunk user already exists.${NC}"
  fi
}

# Function to install Splunk Forwarder
install_splunk() {
  echo "${BLUE}Downloading Splunk Forwarder tarball...${NC}"
  wget -O $SPLUNK_PACKAGE_TGZ $SPLUNK_DOWNLOAD_URL

  echo "${BLUE}Extracting Splunk Forwarder tarball...${NC}"
  sudo tar -xvzf $SPLUNK_PACKAGE_TGZ -C /opt
  rm -f $SPLUNK_PACKAGE_TGZ

  echo "${BLUE}Setting permissions...${NC}"
  create_splunk_user
  sudo chown -R splunk:splunk $INSTALL_DIR
}

# Function to set admin credentials
set_admin_credentials() {
  echo "${BLUE}Setting admin credentials...${NC}"
  USER_SEED_FILE="$INSTALL_DIR/etc/system/local/user-seed.conf"
  sudo bash -c "cat > $USER_SEED_FILE" <<EOL
[user_info]
USERNAME = $ADMIN_USERNAME
PASSWORD = $ADMIN_PASSWORD
EOL
  sudo chown splunk:splunk $USER_SEED_FILE
  echo "${GREEN}Admin credentials set.${NC}"
}

# Function to add basic monitors
setup_monitors() {
  echo "${BLUE}Setting up basic monitors for Splunk...${NC}"
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

[monitor:///tmp/test.log]
index = main
sourcetype = test_log
EOL

  sudo chown splunk:splunk $MONITOR_CONFIG
  echo "${GREEN}Monitors added to inputs.conf.${NC}"
}

# Function to configure the forwarder to send logs to the Splunk indexer
configure_forwarder() {
  echo "${BLUE}Configuring Splunk Universal Forwarder to send logs to $INDEXER_IP:$RECEIVER_PORT...${NC}"
  sudo $INSTALL_DIR/bin/splunk add forward-server $INDEXER_IP:$RECEIVER_PORT -auth $ADMIN_USERNAME:$ADMIN_PASSWORD
  echo "${GREEN}Forward-server configuration complete.${NC}"
}

# Perform installation
install_splunk

# Set admin credentials before starting the service
set_admin_credentials

# Enable Splunk service and accept license agreement
if [ -d "$INSTALL_DIR/bin" ]; then
  echo "${BLUE}Starting and enabling Splunk Universal Forwarder service...${NC}"
  sudo $INSTALL_DIR/bin/splunk start --accept-license --answer-yes --no-prompt
  sudo $INSTALL_DIR/bin/splunk enable boot-start

  # Add basic monitors
  setup_monitors

  # Configure forwarder to send logs to the Splunk indexer
  configure_forwarder

  # Restart Splunk to apply configuration
  sudo $INSTALL_DIR/bin/splunk restart
else
  echo "${RED}Installation directory not found. Something went wrong.${NC}"
  exit 1
fi

# Verify installation
sudo $INSTALL_DIR/bin/splunk version

echo "${YELLOW}Splunk Universal Forwarder v$SPLUNK_VERSION installation complete with basic monitors and forwarder configuration!${NC}"

# CentOS-specific fixes
if [[ "$ID" == "centos" || "$ID_LIKE" == *"centos"* ]]; then
  echo "${RED}Applying CentOS-specific fixes...${NC}"
  
  # Remove AmbientCapabilities line from the systemd service file
  # This needs to be performed on every reboot, because CentOS. This section makes sure it's applied at install, so it can run immediately.
  SERVICE_FILE="/etc/systemd/system/SplunkForwarder.service"
  if [ -f "$SERVICE_FILE" ]; then
    sudo sed -i '/AmbientCapabilities/d' "$SERVICE_FILE"
    echo "${GREEN}Removed AmbientCapabilities line from $SERVICE_FILE ${NC}"
  fi

# This makes turns the fix into a systemd service, which should hopefully catch the error on startup and eliminate any need to constantly implement the fix manually.
# Note that there is another Splunk error that I have not fixed. At least for my CentOS machines, if you turn off the Splunk service it will not turn back on without a reboot.
# Thus, for now, rebooting is the best way to fix the Splunk forwarder.

    # Create a systemd service to handle the fix
    FIX_SERVICE_FILE="/etc/systemd/system/splunk-fix.service"
  
# Create the service file
cat > "$FIX_SERVICE_FILE" <<EOL
[Unit]
Description=Splunk Fix Service
Before=network-online.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "/usr/bin/sed -i \'/AmbientCapabilities/d\' /etc/systemd/system/SplunkForwarder.service"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

    # Enable and start the fix service
    echo "${BLUE}Enabling and starting the fix service${NC}"
    sudo systemctl daemon-reload
    sudo systemctl enable splunk-fix.service
    sudo systemctl start splunk-fix.service
    
    # Verify the fix service status
    echo "${BLUE}Verifying fix service status: ${NC}"
    sudo systemctl status splunk-fix.service
    
    echo "${BLUE}Creating test log. ${NC}"
    echo "Test log entry" > /tmp/test.log
    sudo setfacl -m u:splunk:r /tmp/test.log
      
    # Reload systemd daemon
    echo "${BLUE}Reloading systemctl daemons${NC}"
    sudo systemctl daemon-reload
    
    # Run Splunk again  
    echo "${BLUE}Restarting the Splunk Forwarder${NC}"
    sudo systemctl restart SplunkForwarder
    
    echo "${YELLOW}Restart complete, forwarder installation on CentOS complete${NC}" 
      
  else
      echo "${GREEN}Operating system not recognized as CentOS. Skipping CentOS fix.${NC}"
  fi

# Fedora specific fix. The forwarder doesn't like to work when you install it. For some reason, rebooting just solves this so nicely
# I've looked for logs, tried starting it manually, etc. I couldn't figure it out and am running out of time. Therefore, this beautiful addition.
# This will reboot the machine after a 10 second timer. 
if [[ "$ID" == "fedora" ]]; then
    echo "${RED}Fedora system detected, a reboot is required. System will reboot in 10 seconds.${NC}"
    sleep 10;
    
    # Reboot with 10 second delay
    if ! sudo shutdown -r +0 "${GREEN}First reboot attempt failed. System will reattempt in 5 seconds${NC}" & sleep 5; then
        echo "${RED}Warning: Graceful reboot failed, attempting forced reboot${NC}"
        if ! sudo reboot -f; then
            echo "${RED}Error: Unable to initiate reboot. Manual reboot required.${NC}"
            exit 1
        fi
    fi
    exit 0
fi

