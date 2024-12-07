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

# Function to add monitor
function add_monitor() {
    /opt/splunkforwarder/bin/splunk add monitor "$1" -index "$2" -sourcetype "$3"
}

# Add monitors
add_monitor "/var/log" "linux_logs" "linux_log"
add_monitor "/opt/splunkforwarder/var/log/splunk" "_internal" "splunk_log"

# Add OS-specific monitors
if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
    add_monitor "/var/log/apache2/access.log" "web_logs" "access_combined"
    add_monitor "/var/log/apache2/error.log" "web_logs" "apache_error"
elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
    add_monitor "/var/log/httpd/access_log" "web_logs" "access_combined"
    add_monitor "/var/log/httpd/error_log" "web_logs" "apache_error"
fi

# Add OS-specific monitors
if [[ $OS == *"Ubuntu"* ]]; then
    add_monitor "/home/*/.*history" "user_activity" "shell_history"
    add_monitor "/home/*/.*browser*" "browser_logs" "browser_history"
fi

# Add Prestashop-specific monitors
if [[ $OS == *"CentOS"* ]]; then
    add_monitor "/var/www/prestashop/var/logs" "prestashop_logs" "prestashop"
fi

# Add DNS and NTP monitors for Debian
if [[ $OS == *"Debian"* ]]; then
    add_monitor "/var/log/named" "dns_logs" "dns"
    add_monitor "/var/log/ntp" "ntp_logs" "ntp"
fi

# Add LDAP, Dovecot, and RoundCube monitors for Fedora
if [[ $OS == *"Fedora"* ]]; then
    add_monitor "/var/log/slapd" "ldap_logs" "ldap"
    add_monitor "/var/log/dovecot" "dovecot_logs" "dovecot"
    add_monitor "/var/log/roundcube" "roundcube_logs" "roundcube"
fi

# Add forward server
/opt/splunkforwarder/bin/splunk add forward-server 172.20.241.20:9997

# Restart Splunk forwarder
/opt/splunkforwarder/bin/splunk restart

echo "Splunk forwarder configuration complete."

}

# Main execution
install_splunk_forwarder
configure_splunk_forwarder
