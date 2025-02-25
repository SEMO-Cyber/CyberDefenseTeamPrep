#!/bin/bash

# Color definitions
declare -A COLORS
COLORS=(
    [RESET]='\033[0m'
    [BLACK]='\033[30m'
    [RED]='\033[31m'
    [GREEN]='\033[32m'
    [YELLOW]='\033[33m'
    [BLUE]='\033[34m'
    [MAGENTA]='\033[35m'
    [CYAN]='\033[36m'
    [WHITE]='\033[37m'
    [BRIGHT_BLACK]='\033[90m'
    [BRIGHT_RED]='\033[91m'
    [BRIGHT_GREEN]='\033[92m'
    [BRIGHT_YELLOW]='\033[93m'
    [BRIGHT_BLUE]='\033[94m'
    [BRIGHT_MAGENTA]='\033[95m'
    [BRIGHT_CYAN]='\033[96m'
    [BRIGHT_WHITE]='\033[97m'
)

# Configuration
MANAGER_SETTINGS="managersettings.txt"
IMMUTABLE_DIRS=("/etc/httpd/" "/etc/nginx/" "/etc/mysql/" "/etc/postgresql/")
MUTABLE_DIRS=("/var/log/" "/var/cache/" "/tmp/")
BACKUP_DIR="/backup"

# Service configuration
declare -A SERVICES
SERVICES=(
    [apache2]="Apache HTTP Server"
    [nginx]="Nginx Web Server"
    [mysql]="MySQL Database Server"
    [postgresql]="PostgreSQL Database Server"
    [php-fpm]="PHP-FPM Server"
    [redis]="Redis Cache Server"
    [memcached]="Memcached Cache Server"
    [docker]="Docker Container Runtime"
    [elasticsearch]="Elasticsearch Search Engine"
    [rabbitmq]="RabbitMQ Message Broker"
    [systemd]="Systemd Service Manager"
    [cron]="Cron Job Scheduler"
    [sshd]="SSH Server"
    [kubernetes]="Kubernetes Container Orchestrator"
)

# Service file paths
declare -A SERVICE_PATHS
SERVICE_PATHS=(
    [apache2.static]="/etc/httpd/ /etc/ssl/ /var/www/"
    [apache2.dynamic]="/var/log/httpd/ /var/cache/httpd/ /tmp/ /var/lib/apache2/"
    [nginx.static]="/etc/nginx/ /usr/share/nginx/html/ /etc/ssl/"
    [nginx.dynamic]="/var/log/nginx/ /var/cache/nginx/ /tmp/ /var/lib/nginx/"
    [mysql.static]="/etc/mysql/ /etc/my.cnf.d/"
    [mysql.dynamic]="/var/lib/mysql/ /var/log/mysql/ /var/run/mysqld/ /tmp/"
    [postgresql.static]="/etc/postgresql/ /etc/postgresql/pg_conf.d/"
    [postgresql.dynamic]="/var/lib/postgresql/ /var/log/postgresql/ /var/run/postgresql/ /tmp/"
    [php-fpm.static]="/etc/php/ /etc/ssl/"
    [php-fpm.dynamic]="/var/log/php-fpm/ /run/php/ /var/lib/php/ /tmp/"
    [redis.static]="/etc/redis/"
    [redis.dynamic]="/var/log/redis/ /var/lib/redis/ /tmp/"
    [memcached.static]="/etc/memcached/"
    [memcached.dynamic]="/var/log/memcached/ /var/lib/memcached/ /tmp/"
    [docker.static]="/etc/docker/"
    [docker.dynamic]="/var/lib/docker/ /var/log/docker/ /tmp/"
    [elasticsearch.static]="/etc/elasticsearch/"
    [elasticsearch.dynamic]="/var/lib/elasticsearch/ /var/log/elasticsearch/ /tmp/"
    [rabbitmq.static]="/etc/rabbitmq/"
    [rabbitmq.dynamic]="/var/lib/rabbitmq/ /var/log/rabbitmq/ /tmp/"
    [systemd.static]="/etc/systemd/"
    [systemd.dynamic]="/var/log/journal/ /run/systemd/"
    [cron.static]="/etc/crontab/ /etc/cron.d/ /var/spool/cron/crontabs/"
    [cron.dynamic]="/var/log/cron/ /tmp/"
    [sshd.static]="/etc/ssh/ /etc/ssl/"
    [sshd.dynamic]="/var/log/auth.log/ /run/sshd/ /tmp/"
    [kubernetes.static]="/etc/kubernetes/"
    [kubernetes.dynamic]="/var/lib/kubelet/ /var/log/kubernetes/ /tmp/"
)

# Malicious keyword database
declare -A MALICIOUS_KEYWORDS
MALICIOUS_KEYWORDS=(
    [python]="socket, requests, ftplib, asyncio, os.system, subprocess.run, subprocess.call, subprocess.Popen"
    [c]="socket, send, recv, sendto, recvfrom, bind, listen, system, popen, execvp, fork"
    [cpp]="socket, send, recv, bind, listen, select, system, popen, exec, fork"
    [java]="Socket, ServerSocket, DatagramSocket, URLConnection, Runtime.getRuntime().exec, ProcessBuilder.start"
    [javascript]="net, http, dgram, tls, child_process.exec, child_process.spawn, child_process.fork"
    [go]="net.Dial, net.Listen, http.Get, http.Post, exec.Command, os/exec"
    [ruby]="Net::HTTP, Net::FTP, Socket, UDPSocket, system, exec, IO.popen"
    [php]="fsockopen, stream_socket_client, curl, socket_create, shell_exec, exec, system, popen"
    [bash]="nc, curl, wget, ss, telnet, nmap, $(command), command, exec, sh, bash -c"
    [perl]="IO::Socket, LWP::UserAgent, Net::FTP, Net::HTTP, system, exec, backticks"
    [swift]="URLSession, NWConnection, NWListener, Process, NSTask"
    [rust]="std::net::TcpStream, std::net::TcpListener, std::process::Command"
)

# Function to print colored text
print_colored() {
    local color=$1
    local text=$2
    echo -e "${COLORS[$color]}$text${COLORS[RESET]}"
}

# Function to list services and their file types
list_service_files() {
    print_colored BLUE "Listing services and their file types..."
    print_colored CYAN "%-20s %-50s"
    for service in "${!SERVICES[@]}"; do
        static_paths=${SERVICE_PATHS[$service.static]}
        dynamic_paths=${SERVICE_PATHS[$service.dynamic]}
        print_colored CYAN "%-20s %-50s" "$service" "Static: $static_paths, Dynamic: $dynamic_paths"
    done
}

# Function to monitor immutable directories
monitor_immutable_dirs() {
    for service in "${!SERVICES[@]}"; do
        static_paths=${SERVICE_PATHS[$service.static]}
        for dir in $static_paths; do
            if [[ ! -d "$BACKUP_DIR$dir" ]]; then
                cp -r "$dir" "$BACKUP_DIR$dir"
                print_colored YELLOW "Created backup for $dir"
            fi
            diff -rq "$dir" "$BACKUP_DIR$dir" > /dev/null
            if [[ $? -ne 0 ]]; then
                print_colored RED "Immutable directory $dir has been modified!"
                print_colored YELLOW "Restoring backup..."
                cp -r "$BACKUP_DIR$dir" "$dir"
                systemctl restart $service
                print_colored GREEN "Service restarted successfully"
            fi
        done
    done
}

# Function to scan for malicious keywords
scan_for_malicious_keywords() {
    print_colored BLUE "Enter directory to scan: "
    read scan_dir
    print_colored BLUE "Scanning for malicious keywords..."
    for lang in "${!MALICIOUS_KEYWORDS[@]}"; do
        for keyword in ${MALICIOUS_KEYWORDS[$lang]}; do
            grep -rIl "$keyword" "$scan_dir" 2>/dev/null | while read file; do
                print_colored RED "Malicious keyword '$keyword' found in $file (Language: $lang)!"
            done
        done
    done
}

# Function to display live status table
show_live_status() {
    print_colored GREEN "Monitoring Services..."
    while true; do
        clear
        print_colored BLUE "%-20s %-10s"
        for service in "${!SERVICES[@]}"; do
            status=$(systemctl is-active $service 2>/dev/null)
            if [[ $status == "active" ]]; then
                print_colored GREEN "%-20s %-10s" "$service" "$status"
            else
                print_colored RED "%-20s %-10s" "$service" "$status"
            fi
        done
        sleep 5
    done
}

# Main Menu
while true; do
    print_colored BLUE "CustomManager - Blue Team Cyber Defense"
    print_colored CYAN "1. List Services and File Types"
    print_colored CYAN "2. Monitor Immutable Directories"
    print_colored CYAN "3. Scan for Malicious Keywords"
    print_colored CYAN "4. Show Live Status"
    print_colored CYAN "5. Exit"
    read -p "Select an option: " choice
    
    case $choice in
        1) list_service_files ;;
        2) monitor_immutable_dirs ;;
        3) scan_for_malicious_keywords ;;
        4) show_live_status & ;;
        5) exit 0 ;;
        *) print_colored RED "Invalid option!" ;;
    esac
done
