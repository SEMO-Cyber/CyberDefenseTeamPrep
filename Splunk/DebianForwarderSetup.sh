#/bin/bash

#This script is for installing the Splunk forwarder on Debian-based systems. It's configured for version 9.3.2, but can by easily adapted to other versions. 

#Run update and upgrade ofc
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y


#Sets params
SPLUNK_VERSION="9.3.2"
SPLUNK_DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-x64.deb"
SPLUNK_INSTALL_PATH="/opt/splunkforwarder"
SPLUNK_USER="admin"
SPLUNK_PASSWORD="Changeme1!"  


#Download the forwarder .deb
echo "Downloading Splunk Universal Forwarder version $SPLUNK_VERSION..."
wget -O splunkforwarder.deb "$SPLUNK_DOWNLOAD_URL"

#Install the forwarrder
echo "Installing Splunk Universal Forwarder..."
sudo dpkg -i splunkforwarder.deb

#Cleanup the .deb download
rm splunkforwarder.deb

#First run configuration
echo "Configuring Splunk..."
sudo ${SPLUNK_INSTALL_PATH}/bin/splunk start --accept-license --answer-yes --no-prompt
sudo ${SPLUNK_INSTALL_PATH}/bin/splunk enable boot-start

#Set the admin creds
echo "Setting up admin credentials..."
sudo ${SPLUNK_INSTALL_PATH}/bin/splunk edit user admin -password "$SPLUNK_PASSWORD" -auth admin:changeme

#Start it
echo "Starting Splunk Universal Forwarder..."
sudo ${SPLUNK_INSTALL_PATH}/bin/splunk start

#Yay!
echo "Splunk Universal Forwarder version $SPLUNK_VERSION installed and configured successfully."
echo "Access the Splunk Universal Forwarder CLI using: ${SPLUNK_INSTALL_PATH}/bin/splunk"
