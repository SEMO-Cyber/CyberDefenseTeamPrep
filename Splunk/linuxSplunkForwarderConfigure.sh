#!/bin/bash

#filepaths to monitor
sudo /opt/splunkforwarder/bin/splunk add monitor /var/log

#add forward server
sudo /opt/splunkforwarder/bin/splunk add forward-server 172.20.241.20:9997
sudo /opt/splunkforwarder/bin/splunk restart