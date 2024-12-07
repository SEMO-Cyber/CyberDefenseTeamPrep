#!/bin/bash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Determine the OS
OS=$(cat /etc/os-release | grep ^NAME= | cut -d= -f2 | tr -d '"')

# Install Splunk forwarder (adjust URL as needed)
echo "Installing Splunk forwarder..."
if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
    wget -O splunkforwarder.deb "https://download.splunk.com/products/universalforwarder/releases/9.0.3/linux/splunkforwarder-9.0.3-82c987350fde-Linux-x86_64.deb"
    dpkg -i splunkforwarder.deb
elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
    wget -O splunkforwarder.rpm "https://download.splunk.com/products/universalforwarder/releases/9.0.3/linux/splunkforwarder-9.0.3-82c987350fde-Linux-x86_64.rpm"
    rpm -i splunkforwarder.rpm
else
    echo "Unsupported OS. Please install Splunk forwarder manually."
    exit 1
fi

# Start Splunk forwarder
/opt/splunkforwarder/bin/splunk start --accept-license

# Configure Splunk forwarder
echo "Configuring Splunk forwarder..."

# Create or update inputs.conf
cat << EOF | sudo tee /opt/splunkforwarder/etc/system/local/inputs.conf
[monitor:///var/log]
disabled = false
index = linux_logs

[monitor:///opt/splunkforwarder/var/log/splunk]
disabled = false
index = _internal

# Add OS-specific monitors
if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
    echo "[monitor:///var/log/apache2/access.log]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = web_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = access_combined" >> /opt/splunkforwarder/etc/system/local/inputs.conf

    echo "[monitor:///var/log/apache2/error.log]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = web_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = apache_error" >> /opt/splunkforwarder/etc/system/local/inputs.conf

elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
    echo "[monitor:///var/log/httpd/access_log]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = web_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = access_combined" >> /opt/splunkforwarder/etc/system/local/inputs.conf

    echo "[monitor:///var/log/httpd/error_log]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = web_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = apache_error" >> /opt/splunkforwarder/etc/system/local/inputs.conf
fi

# Add OS-specific monitors
if [[ $OS == *"Ubuntu"* ]]; then
    echo "[monitor:///home/*/.*history]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = user_activity" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = shell_history" >> /opt/splunkforwarder/etc/system/local/inputs.conf

    echo "[monitor:///home/*/.*browser*]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = browser_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = browser_history" >> /opt/splunkforwarder/etc/system/local/inputs.conf
fi

# Add Prestashop-specific monitors
if [[ $OS == *"CentOS"* ]]; then
    echo "[monitor:///var/www/prestashop/var/logs]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = prestashop_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = prestashop" >> /opt/splunkforwarder/etc/system/local/inputs.conf
fi

# Add DNS and NTP monitors for Debian
if [[ $OS == *"Debian"* ]]; then
    echo "[monitor:///var/log/named]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = dns_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = dns" >> /opt/splunkforwarder/etc/system/local/inputs.conf

    echo "[monitor:///var/log/ntp]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = ntp_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = ntp" >> /opt/splunkforwarder/etc/system/local/inputs.conf
fi

# Add LDAP, Dovecot, and RoundCube monitors for Fedora
if [[ $OS == *"Fedora"* ]]; then
    echo "[monitor:///var/log/slapd]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = ldap_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = ldap" >> /opt/splunkforwarder/etc/system/local/inputs.conf

    echo "[monitor:///var/log/dovecot]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = dovecot_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = dovecot" >> /opt/splunkforwarder/etc/system/local/inputs.conf

    echo "[monitor:///var/log/roundcube]" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "disabled = false" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "index = roundcube_logs" >> /opt/splunkforwarder/etc/system/local/inputs.conf
    echo "sourcetype = roundcube" >> /opt/splunkforwarder/etc/system/local/inputs.conf
fi

# Create or update outputs.conf
cat << EOF | sudo tee /opt/splunkforwarder/etc/system/local/outputs.conf
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = 172.20.241.20:9997
EOF

# Restart Splunk forwarder
/opt/splunkforwarder/bin/splunk restart

echo "Splunk forwarder configuration complete."
