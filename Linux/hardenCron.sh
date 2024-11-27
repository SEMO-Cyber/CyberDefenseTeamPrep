#!/bin/bash
#A script meant to harden some of the perms for cron jobs and copy all cron locations into a central, easy to reference directory. This is a time saver with a tiny bit of hardening, nothing special.

#I took both influences, made some changes, ran it through AI, and then did a little more configuration. 



if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi


echo "Locking down Cron and AT permissions..."
touch /etc/cron.allow
chmod 600 /etc/cron.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/cron.deny

touch /etc/at.allow
chmod 600 /etc/at.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/at.deny



echo "Dumping cron jobs into /cronJobs"
mkdir -p ~/cronJobs
mkdir -p ~/cronJobs/varSpool/
mkdir -p ~/cronJobs/etc/hourly
mkdir -p ~/cronJobs/etc/daily
mkdir -p ~/cronJobs/etc/weekly
mkdir -p ~/cronJobs/etc/monthly

echo "Dumping /var/spool"
cp -r /var/spool/cron/crontabs ~/cronJobs/varSpool/
echo "Dumping /etc"
cp -r /etc/crontab ~/cronJobs/etc/
echo "Dumping hourly,daily,weekly,monthly"
cp -r /etc/cron.hourly ~/cronJobs/etc/hourly
cp -r /etc/cron.daily ~/cronJobs/daily
cp -r /etc/cron.weekly ~/cronJobs/weekly
cp -r /etc/cron.monthly ~/cronJobs/monthly

input=""
read -p "Display list of files? (y/n) " input
if [ $input = "y" ]
        then find ~/cronJobs/ -type f
fi