#!/bin/bash

# --- Function to install the Splunk Forwarder ---
install_forwarder() {
  cd /tmp
  # Fetch the Splunk Forwarder package for Ubuntu (adjust URL if needed)
  wget `curl -s https://www.splunk.com/en_us/download/universal-forwarder.html\?locale\=en_us | grep -oP '"https:.*(?<=download).*amd64.deb"' | sed 's/\"//g' | head -n 1` -O splunkforwarder.deb

  # Install the package
  dpkg -i splunkforwarder.deb

  sleep 5
}

# --- Function to configure basic settings ---
configure_splunk() {
  # Create the necessary directory
  mkdir -p /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/
  cd /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/

  # Configure app.conf
  cat <<EOF> /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/app.conf
[install]
state = enabled

[package]
check_for_updates = false

[ui]
is_visible = false
is_manageable = false
EOF

  # Configure deploymentclient.conf (replace with your deployment server details)
  cat <<EOF> /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/deploymentclient.conf
[deployment-client]
phoneHomeIntervalInSecs = 60
[target-broker:deploymentServer]
targetUri = 172.20.241.20:9997  # Replace with your deployment server address
EOF

  # Configure user-seed.conf 
  cat <<EOF> /opt/splunkforwarder/etc/system/local/user-seed.conf
[user_info]
USERNAME = admin
PASSWORD = Changeme1!  # Change this password immediately after installation
EOF

  # Run btool and start Splunk
  /opt/splunkforwarder/bin/splunk cmd btool deploymentclient list --debug
  /opt/splunkforwarder/bin/splunk start --accept-license
}

# --- Function to add a monitor stanza to inputs.conf ---
add_monitor() {
  local filepath="$1"
  local index="$2"

  echo "
[monitor://$filepath]
disabled = false
index = $index" >> /opt/splunkforwarder/etc/system/local/inputs.conf
}

# --- Main section ---

# 1. Install the Splunk Forwarder
install_forwarder

# 2. Configure basic settings
configure_splunk

# 3. Add monitors for specific log files with corresponding indexes
add_monitor /var/log/nessus/nessus.log nessus_logs
add_monitor /var/log/auth.log ubuntu_auth
add_monitor /var/log/syslog ubuntu_system
# Add more add_monitor calls for other log files as needed

# 4. Restart Splunk to apply the input configuration
sudo /opt/splunkforwarder/bin/splunk restart