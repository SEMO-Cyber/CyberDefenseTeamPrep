# CustomManager.sh - Blue Team Cyber Defense Script

## Features:
# - Accepts user-specified paths for monitoring.
# - Lists services and categorizes them as mutable or immutable.
# - Monitors immutable and mutable directories.
# - Restores immutable directories from backup if modified.
# - Logs changes in mutable directories and scans for malicious keywords.
# - Service handler to start, restart, and stop services.
# - Displays live status table with colors for service health.
# - Configuration menu for user customization.
# - Predefined service directory data for known services.
# - Automated alerts and logging for unauthorized changes.
# - Lists static and dynamic files for common Linux services.
# - Scans for malicious keywords in various programming languages.

# Configuration File
MANAGER_SETTINGS="managersettings.txt"

# Directory Tracking
IMMUTABLE_DIRS=("/etc/httpd/" "/etc/nginx/" "/etc/mysql/" "/etc/postgresql/")
MUTABLE_DIRS=("/var/log/" "/var/cache/" "/tmp/")
BACKUP_DIR="/backup"

# Malicious Keyword Database
declare -A MALICIOUS_KEYWORDS
MALICIOUS_KEYWORDS=(
  [python]="socket requests ftplib asyncio os.system subprocess.run subprocess.call subprocess.Popen"
  [c]="socket send recv sendto recvfrom bind listen system popen execvp fork"
  [cpp]="socket send recv bind listen select system popen exec fork"
  [java]="Socket ServerSocket DatagramSocket URLConnection Runtime.getRuntime().exec ProcessBuilder.start"
  [javascript]="net http dgram tls child_process.exec child_process.spawn child_process.fork"
  [go]="net.Dial net.Listen http.Get http.Post exec.Command os/exec"
  [ruby]="Net::HTTP Net::FTP Socket UDPSocket system exec IO.popen"
  [php]="fsockopen stream_socket_client curl socket_create shell_exec exec system popen"
  [bash]="nc curl wget ss telnet nmap $(command) command exec sh bash -c"
  [perl]="IO::Socket LWP::UserAgent Net::FTP Net::HTTP system exec backticks"
  [swift]="URLSession NWConnection NWListener Process NSTask"
  [rust]="std::net::TcpStream std::net::TcpListener std::process::Command"
)

# Function to Accept User Input for Paths
configure_paths() {
  read -p "Enter immutable directories (space-separated): " -a IMMUTABLE_DIRS
  read -p "Enter mutable directories (space-separated): " -a MUTABLE_DIRS
  echo "Configuration updated."
}

# Function to List Static and Dynamic Files for Services
list_service_files() {
  echo "Listing static and dynamic files for known services..."
  printf "\e[1;34m%-20s %-50s\e[0m\n" "SERVICE" "FILE TYPE"
  declare -A SERVICES
  SERVICES=(
    [apache2]="/etc/httpd/ (Static), /var/log/httpd/ (Dynamic)"
    [nginx]="/etc/nginx/ (Static), /var/log/nginx/ (Dynamic)"
    [mysql]="/etc/mysql/ (Static), /var/lib/mysql/ (Dynamic)"
    [postgresql]="/etc/postgresql/ (Static), /var/lib/postgresql/ (Dynamic)"
    [php-fpm]="/etc/php/ (Static), /var/lib/php/ (Dynamic)"
    [redis]="/etc/redis/ (Static), /var/lib/redis/ (Dynamic)"
    [docker]="/etc/docker/ (Static), /var/lib/docker/ (Dynamic)"
  )
  for service in "${!SERVICES[@]}"; do
    printf "%-20s %-50s\n" "$service" "${SERVICES[$service]}"
  done
}

# Function to Monitor Immutable Directories
monitor_immutable_dirs() {
  for dir in "${IMMUTABLE_DIRS[@]}"; do
    if [[ ! -d "$BACKUP_DIR$dir" ]]; then
      cp -r "$dir" "$BACKUP_DIR$dir"
    fi
    diff -rq "$dir" "$BACKUP_DIR$dir" > /dev/null
    if [[ $? -ne 0 ]]; then
      echo "Immutable directory $dir has been modified! Restoring backup..."
      cp -r "$BACKUP_DIR$dir" "$dir"
      systemctl restart $(basename "$dir")
    fi
  done
}

# Function to Scan for Malicious Keywords in Code Files
scan_for_malicious_keywords() {
  read -p "Enter the directory to scan: " scan_dir
  for lang in "${!MALICIOUS_KEYWORDS[@]}"; do
    for keyword in ${MALICIOUS_KEYWORDS[$lang]}; do
      grep -rIl "$keyword" "$scan_dir" 2>/dev/null | while read file; do
        echo "Malicious keyword '$keyword' found in $file (Language: $lang)!"
      done
    done
  done
}

# Function to Display Live Status Table
show_live_status() {
  echo "\e[1;32mMonitoring Services...\e[0m"
  while true; do
    clear
    echo -e "\e[1;34m%-20s %-10s\e[0m" "SERVICE" "STATUS"
    for service in apache2 nginx mysql postgresql php-fpm redis docker; do
      status=$(systemctl is-active $service 2>/dev/null)
      if [[ $status == "active" ]]; then
        echo -e "\e[1;32m%-20s %-10s\e[0m" "$service" "$status"
      else
        echo -e "\e[1;31m%-20s %-10s\e[0m" "$service" "$status"
      fi
    done
    sleep 5
  done
}

# Main Menu
while true; do
  echo "\e[1;36mCustomManager - Blue Team Cyber Defense\e[0m"
  echo "1. Configure Paths"
  echo "2. List Services"
  echo "3. List Static & Dynamic Service Files"
  echo "4. Monitor Immutable Directories"
  echo "5. Scan for Malicious Keywords"
  echo "6. Show Live Status"
  echo "7. Exit"
  read -p "Select an option: " choice

  case $choice in
    1) configure_paths ;;
    2) list_services ;;
    3) list_service_files ;;
    4) monitor_immutable_dirs ;;
    5) scan_for_malicious_keywords ;;
    6) show_live_status & ;;
    7) exit 0 ;;
    *) echo "Invalid option!" ;;
  esac

done
