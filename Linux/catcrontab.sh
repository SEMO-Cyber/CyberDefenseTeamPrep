#!/bin/bash
(awk -F: '{print "echo \""$1":\"; crontab -l -u "$1"; echo"}' /etc/passwd; echo "echo Cron.daily etc:"; echo "find -type f -path \"/etc/cron.*\" -print0 | xargs cat")| sudo bash | tee cronstat
