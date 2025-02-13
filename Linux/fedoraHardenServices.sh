#!/bin/bash
# Security Hardening for Fedora 21
# Run as root

set -e #Exit on error

# 1. Ensure SELinux is Enforcing
echo "Verifying SELinux enforcement..."
sed -i 's/SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config
setenforce 1

echo "SELinux enforced."

# 2. Secure HTTPD Configuration
echo "Hardening Apache HTTPD..."
sed -i 's/ServerTokens OS/ServerTokens Prod/' /etc/httpd/conf/httpd.conf
sed -i 's/ServerSignature On/ServerSignature Off/' /etc/httpd/conf/httpd.conf
systemctl restart httpd

echo "Apache HTTPD secured."

# 3. Secure Dovecot Configuration
echo "Hardening Dovecot..."
echo 'disable_plaintext_auth = yes' >> /etc/dovecot/dovecot.conf
echo 'ssl = required' >> /etc/dovecot/dovecot.conf
systemctl restart dovecot

echo "Dovecot secured."

# 4. Secure Postfix Configuration
echo "Hardening Postfix..."
postconf -e 'smtpd_helo_required = yes'
postconf -e 'disable_vrfy_command = yes'
postconf -e 'smtpd_tls_security_level = may'
systemctl restart postfix

echo "Postfix secured."

# 5. Secure RoundcubeMail Configuration
echo "Hardening RoundcubeMail..."
sed -i "s/\$config\['enable_installer'\] = true;/\$config['enable_installer'] = false;/" /etc/roundcubemail/config.inc.php
sed -i "s/\$config\['default_host'\] = '';/\$config['default_host'] = 'ssl:\/\/localhost';/" /etc/roundcubemail/config.inc.php

echo "RoundcubeMail secured."

echo "Security misconfiguration hardening complete."
