#!/bin/bash

# Define file names
CONFIG_FILE="configuration.txt"
IMMUTABLE_BACKUP_FILE="immutablebackups.txt"
MALICIOUS_LOG="malicious_scan.log"
INTEGRITY_LOG="integrity.log"
MALICIOUS_KEYWORDS_FILE="malicious_keywords.txt"

# Create configuration file with service details
cat <<EOL > $CONFIG_FILE
# service_name type directory_path
apache2 static /etc/httpd/
nginx dynamic /var/log/nginx/
mysql static /etc/mysql/
postgresql static /etc/postgresql/
php-fpm dynamic /var/log/php-fpm/
redis static /etc/redis/
memcached dynamic /var/log/memcached/
docker dynamic /var/lib/docker/
elasticsearch dynamic /var/log/elasticsearch/
rabbitmq dynamic /var/log/rabbitmq/
systemd dynamic /etc/systemd/
cron static /etc/crontab/
sshd static /etc/ssh/
kubernetes dynamic /etc/kubernetes/
custom_service1 static /path/to/custom_service1/static/
custom_service2 dynamic /path/to/custom_service2/dynamic/
EOL

echo "Created $CONFIG_FILE with service configurations."

# Create immutable backups file
cat <<EOL > $IMMUTABLE_BACKUP_FILE
# Immutable Directory Path -> Corresponding Backup Directory
/etc/httpd/ -> /backup/httpd/
/etc/nginx/ -> /backup/nginx/
/etc/mysql/ -> /backup/mysql/
/etc/postgresql/ -> /backup/postgresql/
/etc/ssh/ -> /backup/ssh/
/etc/systemd/ -> /backup/systemd/
EOL

echo "Created $IMMUTABLE_BACKUP_FILE with immutable directory backup mapping."

# Create malicious keywords file
cat <<EOL > $MALICIOUS_KEYWORDS_FILE
# Language -> Keywords
python: socket, requests, ftplib, asyncio, os.system, subprocess.run, subprocess.call, subprocess.Popen
c: socket, send, recv, sendto, recvfrom, bind, listen, system, popen, execvp, fork
cpp: socket, send, recv, bind, listen, select, system, popen, exec, fork
java: Socket, ServerSocket, DatagramSocket, URLConnection, Runtime.getRuntime().exec, ProcessBuilder.start
javascript: net, http, dgram, tls, child_process.exec, child_process.spawn, child_process.fork
go: net.Dial, net.Listen, http.Get, http.Post, exec.Command, os/exec
ruby: Net::HTTP, Net::FTP, Socket, UDPSocket, system, exec, IO.popen
php: fsockopen, stream_socket_client, curl, socket_create, shell_exec, exec, system, popen
bash: nc, curl, wget, ss, telnet, nmap, $(command), command, exec, sh, bash -c
perl: IO::Socket, LWP::UserAgent, Net::FTP, Net::HTTP, system, exec, backticks
swift: URLSession, NWConnection, NWListener, Process, NSTask
rust: std::net::TcpStream, std::net::TcpListener, std::process::Command
EOL

echo "Created $MALICIOUS_KEYWORDS_FILE with malicious keyword database."

# Create empty log files
touch $MALICIOUS_LOG
echo "Created empty $MALICIOUS_LOG for malicious scan logs."

touch $INTEGRITY_LOG
echo "Created empty $INTEGRITY_LOG for integrity monitoring logs."

# Set proper permissions
chmod 600 $CONFIG_FILE $IMMUTABLE_BACKUP_FILE $MALICIOUS_LOG $INTEGRITY_LOG $MALICIOUS_KEYWORDS_FILE

echo "All files created and permissions set."
