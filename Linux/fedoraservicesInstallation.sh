#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Update system packages
yum update -y

# Install MySQL server
yum install -y community-mysql-server
systemctl start mysqld
systemctl enable mysqld


# Secure MySQL installation
mysql_secure_installation << EOF

y
Changeme1!
Changeme1!
y
y
y
y
EOF

# Log into MySQL and set up databases
mysql -u root -pChangeme1! << EOF
CREATE DATABASE roundcube_db;
GRANT ALL ON roundcube_db.* TO 'roundcube_user'@'localhost' IDENTIFIED BY 'Changeme1!';
FLUSH PRIVILEGES;

CREATE DATABASE mailserver_db;
GRANT ALL ON mailserver_db.* TO 'mail_user'@'localhost' IDENTIFIED BY 'Changeme1!';
FLUSH PRIVILEGES;

USE mailserver_db;

CREATE TABLE virtual_domains (
    id INT NOT NULL AUTO_INCREMENT,
    name VARCHAR(50) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE virtual_users (
    id INT NOT NULL AUTO_INCREMENT,
    domain_id INT NOT NULL,
    password VARCHAR(106) NOT NULL,
    email VARCHAR(120) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY email (email),
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE virtual_aliases (
    id INT NOT NULL AUTO_INCREMENT,
    domain_id INT NOT NULL,
    source VARCHAR(100) NOT NULL,
    destination VARCHAR(100) NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO virtual_domains (name) VALUES ('comp.local\');
INSERT INTO virtual_users (domain_id, password, email) VALUES
('1', ENCRYPT('Changeme1!', CONCAT('$6$', SUBSTRING(SHA(RAND()), -16))), 'sysadmin@comp.local');
EOF

# Install Dovecot and MySQL support
yum install -y dovecot dovecot-mysql

# Configure Dovecot
cat > /etc/dovecot/dovecot.conf << EOF
protocols = imap
mail_location = maildir:/var/mail/vhosts/%d/%n
EOF

cat > /etc/dovecot/conf.d/10-auth.conf << EOF
disable_plaintext_auth = no
auth_mechanisms = plain login
!include auth-sql.conf.ext
EOF

cat > /etc/dovecot/dovecot-sql.conf.ext <<EOF
driver = mysql
connect = host=127.0.0.1 dbname=mailserver_db user=mail_user password=Changeme1!
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u';
user_query = SELECT email as user, password, '/var/mail/vhosts/%d/%n' as home, 5000 AS uid, 5000 AS gid FROM virtual_users WHERE email='%u';
EOF

systemctl start dovecot
systemctl enable dovecot

# Install Apache, PHP, and Roundcube
yum install -y httpd php php-mysqlnd php-intl php-pear php-xml php-mbstring roundcubemail

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Configure Roundcube
cat > /etc/roundcubemail/config.inc.php <<EOF
<?php
$config['db_dsnw'] = 'mysql://roundcube_user:Changeme1!@localhost/roundcube_db';
$config['default_host'] = 'localhost';
$config['smtp_server'] = 'localhost';
EOF

# Import Roundcube database schema
mysql -u roundcube_user -pChangeme1! roundcube_db < /usr/share/roundcubemail/SQL/mysql.initial.sql

# Configure Apache for Roundcube
cat > /etc/httpd/conf.d/roundcubemail.conf << EOF
<Directory /usr/share/roundcubemail/>
    Require all granted
</Directory>
EOF

systemctl restart httpd

echo "Installation and configuration complete. Access Roundcube at http://your_server_ip/roundcube/"
