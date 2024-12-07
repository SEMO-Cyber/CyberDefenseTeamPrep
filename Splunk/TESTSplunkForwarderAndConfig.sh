#!/bin/bash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Determine the OS
OS=$(cat /etc/os-release | grep ^NAME= | cut -d= -f2 | tr -d '"')

# Function to install Splunk forwarder
function install_splunk_forwarder() {

    function UFYUM(){
    cd /tmp
    rpm -Uvh --nodeps `curl -s https://www.splunk.com/en_us/download/universal-forwarder.html\?locale\=en_us | grep -oP '"https:.*(?<=download).*x86_64.rpm"' |sed 's/\"//g' | head -n 1`
    yum -y install splunkforwarder.x86_64
    sleep 5

    }

    function UFDEB(){
    cd /tmp
    wget  `curl -s https://www.splunk.com/en_us/download/universal-forwarder.html\?locale\=en_us | grep -oP '"https:.*(?<=download).*amd64.deb"' |sed 's/\"//g' | head -n 1` -O amd64.deb
    dpkg -i amd64.deb
    sleep 5

    }

    function UFConf(){

    mkdir -p /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/
    cd /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/

    cat << EOF > /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/app.conf
    [install]
    state = enabled

    [package]
    check_for_updates = false

    [ui]
    is_visible = false
    is_manageable = false


    cat <<EOF> /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/deploymentclient.conf
    [deployment-client]
    phoneHomeIntervalInSecs = 60
    [target-broker:deploymentServer]
    targetUri = 172.20.241.20:9997
EOF

    cat << EOF > /opt/splunkforwarder/etc/system/local/user-seed.conf
    [user_info]
    USERNAME = admin
    PASSWORD = Changeme1!
EOF



    /opt/splunkforwarder/bin/splunk cmd btool deploymentclient list --debug

    /opt/splunkforwarder/bin/splunk start --accept-license
    }

    ######################################################### MAIN 


    # Check for RPM package managers
    if command -v yum > /dev/null; then
        UFYUM
        UFConf
    else
        echo "No YUM package manager found."
    fi

    # Check for DEB package managers
    if command -v dpkg > /dev/null; then
        UFDEB
        UFConf
    else
        echo "No DEB package manager found."
    fi
    ls
}

# Function to configure Splunk forwarder
function configure_splunk_forwarder() {
    # Start Splunk forwarder
    /opt/splunkforwarder/bin/splunk start --accept-license

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
}

# Main execution
install_splunk_forwarder
configure_splunk_forwarder
