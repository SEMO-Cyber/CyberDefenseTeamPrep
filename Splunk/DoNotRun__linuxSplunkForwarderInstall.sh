#!/bin/bash

########################## FUNC 
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

cat >> /opt/splunkforwarder/etc/apps/nwl_all_deploymentclient/local/app.conf << EOF
[install]
state = enabled

[package]
check_for_updates = false

[ui]
is_visible = false
is_manageable = false
EOF



cat >> /opt/splunkforwarder/etc/system/local/user-seed.conf << EOF
[user_info]
USERNAME = sysadmin
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
