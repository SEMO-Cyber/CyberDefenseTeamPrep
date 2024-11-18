#!/bin/bash

# --- Function to install the Splunk Forwarder ---
install_forwarder() {
  cd /tmp
  # Fetch the Splunk Forwarder package for FreeBSD (adjust URL if needed)
  fetch -o splunkforwarder.txz `curl -s https://www.splunk.com/en_us/download/universal-forwarder.html\?locale\=en_us | grep -oP '"https:.*(?<=download).*freebsd-amd64.txz"' | sed 's/\"//g' | head -n 1`

  # Install the package
  pkg add splunkforwarder.txz 

  sleep 5
}

# --- Function to configure basic settings ---
configure_splunk() {
  # Create the necessary directory
  mkdir -p /usr/local/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/
  cd /usr/local/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/

  # Configure app.conf
  cat <<EOF> /usr/local/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/app.conf
[install]
state = enabled

[package]
check_for_updates = false

[ui]
is_visible = false
is_manageable = false
EOF

  # Configure deploymentclient.conf (replace with your deployment server details)
  cat <<EOF> /usr/local/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/deploymentclient.conf
[deployment-client]
phoneHomeIntervalInSecs = 60
[target-broker:deploymentServer]
targetUri = 172.20.241.20:9997  # Replace with your deployment server address
EOF

  # Configure user-seed.conf 
  cat <<EOF> /usr/local/splunkforwarder/etc/system/local/user-seed.conf
[user_info]
USERNAME = admin
PASSWORD = Changeme1!  # Change this password immediately after installation
EOF

  # Run btool and start Splunk
  /usr/local/splunkforwarder/bin/splunk cmd btool deploymentclient list --debug
  /usr/local/splunkforwarder/bin/splunk start --accept-license
}

# --- Function to add a monitor stanza to inputs.conf ---
add_monitor() {
  local filepath="$1"
  local index="$2"

  echo "
[monitor://$filepath]
disabled = false
index = $index" >> /usr/local/splunkforwarder/etc/system/local/inputs.conf
}

# --- Main section ---

# 1. Install the Splunk Forwarder
install_forwarder

# 2. Configure basic settings
configure_splunk

# 3. Add monitors for specific log files with corresponding indexes
add_monitor /var/log/filter.log opnsense_firewall
add_monitor /var/log/system.log opnsense_system
add_monitor /var/log/dhcpd.log opnsense_dhcp
add_monitor /var/log/portalauth.log opnsense_portalauth
add_monitor /var/log/suricata opnsense_suricata 
# Add more add_monitor calls for other log files as needed

# 4. Restart Splunk to apply the input configuration
sudo /usr/local/splunkforwarder/bin/splunk restart