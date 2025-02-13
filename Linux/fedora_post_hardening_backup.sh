#!/bin/bash

# Define backup directory
BACKUP_DIR="/etc/backs/post_hardening"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "Starting Post-Hardening Backup..."

# Backup only the changed files after security hardening
tar --exclude='/root/CyberDefenseTeamPrep' -czvf $BACKUP_DIR/post_hardening_backup.tar.gz \
    /root \
    /var/www/html \
    /etc/roundcubemail \
    /etc/httpd \
    /etc/dovecot \
    /etc/postfix \
    /etc/passwd \
    /etc/group \
    /etc/shadow \
    /etc/sudoers* \
    /usr/share/httpd \
    /srv/vmail \
    /usr/share/roundcubemail \
    /usr/share/dovecot

echo "Post-Hardening Backup Completed Successfully and stored in $BACKUP_DIR"
