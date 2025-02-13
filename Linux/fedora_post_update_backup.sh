#!/bin/bash

# Define backup directory
BACKUP_DIR="/etc/backs/post_update"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "Starting Post-Update Backup..."

# Backup everything again after applying updates
tar --exclude='/root/CyberDefenseTeamPrep' -czvf $BACKUP_DIR/post_update_backup.tar.gz \
    /root \
    /var/www/html \
    /etc/roundcubemail \
    /etc/httpd \
    /etc/dovecot \
    /etc/postfix \
    /etc/cron* \
    /etc/passwd \
    /etc/group \
    /etc/shadow \
    /etc/sudoers* \
    /etc/hosts \
    /etc/hostname \
    /etc/aliases \
    /etc/systemd \
    /etc/yum* \
    /etc/resolv.conf \
    /usr/share/httpd \
    /srv/vmail \
    /etc/sysconfig \
    /usr/share/roundcubemail \
    /usr/share/dovecot

echo "Post-Update Backup Completed Successfully and stored in $BACKUP_DIR"
