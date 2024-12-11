#!/bin/bash


# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi


/opt/splunkforwarder/bin/splunk add monitor /var/log
/opt/splunkforwarder/bin/splunk add forward-server 172.20.241.20:9997
