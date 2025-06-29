#!/bin/bash

# Script to install Wazuh Manager on a system with Splunk Enterprise
# For use in cybersecurity competition environments
# Focuses on infrastructure setup only - no active response configuration

# Set up logging
LOG_DIR="/var/log/wazuh-install"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_FILE="$LOG_DIR/wazuh_install_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE" 2>/dev/null

# Check if we can write to the log file
if [ ! -w "$LOG_FILE" ]; then
    # Try alternative location if /var/log isn't writable
    LOG_DIR="/tmp"
    LOG_FILE="$LOG_DIR/wazuh_install_$(date +%Y%m%d_%H%M%S).log"
    touch "$LOG_FILE"
fi

# Function to log messages to both console and log file
log() {
    echo "$@" | tee -a "$LOG_FILE"
}

# Redirect all stdout and stderr to the log file while maintaining console output
exec > >(tee -a "$LOG_FILE") 2>&1

log "Logging started at $(date). Log file: $LOG_FILE"

# Function to display error messages and exit
error_exit() {
    echo "[ERROR] $1" >&2
    echo "[ERROR] Please check logs and system configuration, then try again." >&2
    echo "[ERROR] Full installation log available at: $LOG_FILE" >&2
    exit 1
}

# Function to display information messages
info() {
    echo "[INFO] $1"
}

# Function to display success messages
success() {
    echo "[SUCCESS] $1"
}

# Function to check if a command is available
check_command() {
    command -v "$1" &> /dev/null || error_exit "Command '$1' not found. Please install it and try again."
}

# Function to check if a service is active
check_service_active() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name"; then
        success "$service_name is running."
    else
        error_exit "$service_name failed to start. Check logs with: journalctl -u $service_name"
    fi
}

# Function to retry network commands
retry_network() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        info "Attempt $attempt/$max_attempts: $cmd"
        eval "$cmd" && return 0
        sleep 5
        attempt=$((attempt + 1))
    done
    error_exit "Failed to execute network command: $cmd"
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    error_exit "This script must be run as root"
fi

# Display welcome message
echo "====================================================="
echo "  Wazuh Manager Installation for Splunk Integration  "
echo "====================================================="
echo ""
echo "This script will install the Wazuh Manager and integrate"
echo "it with your existing Splunk Enterprise installation."
echo "All output is being logged to: $LOG_FILE"
echo ""
echo "Press Enter to continue or Ctrl+C to abort..."
read

# Detect Linux distribution
info "Detecting Linux distribution..."
if [ -f /etc/oracle-release ]; then
    DISTRO="oracle"
    PKG_MANAGER="dnf"
    info "Detected Oracle Linux"
elif [ -f /etc/redhat-release ]; then
    DISTRO="redhat"
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi
    info "Detected Red Hat-based distribution"
elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
    PKG_MANAGER="apt-get"
    info "Detected Debian-based distribution"
else
    error_exit "Unsupported Linux distribution. This script supports Oracle, Red Hat, and Debian-based distributions."
fi

# Check for systemd
USE_SYSTEMD=1
check_command systemctl || USE_SYSTEMD=0

# Find Splunk installation
info "Locating Splunk Enterprise installation..."
SPLUNK_HOME=$(find /opt /usr/local -maxdepth 3 -name "splunk" -type d 2>/dev/null | grep -v "splunkforwarder" | head -n 1)
if [ -z "$SPLUNK_HOME" ]; then
    if [ -d "/opt/splunk" ]; then
        SPLUNK_HOME="/opt/splunk"
    else
        error_exit "Could not find Splunk Enterprise installation in /opt or /usr/local. Please ensure Splunk is installed."
    fi
fi
info "Found Splunk Enterprise at $SPLUNK_HOME"

# Detect Splunk user
SPLUNK_USER=$(ps aux | grep "[s]plunkd" | awk '{print $1}' | head -n 1)
if [ -z "$SPLUNK_USER" ]; then
    SPLUNK_USER="splunk"
    info "No running Splunk process found. Assuming Splunk user is 'splunk'."
fi
SPLUNK_GROUP="$SPLUNK_USER"

# Check if Splunk is running
if ! pgrep -f "splunkd" > /dev/null; then
    info "Splunk service is not running. Starting Splunk..."
    if [ -x "$SPLUNK_HOME/bin/splunk" ]; then
        su - "$SPLUNK_USER" -c "$SPLUNK_HOME/bin/splunk start --accept-license --answer-yes --no-prompt" || error_exit "Failed to start Splunk. Verify Splunk installation at $SPLUNK_HOME."
        sleep 5
        check_service_active splunkd
    else
        error_exit "Splunk binary not found at $SPLUNK_HOME/bin/splunk."
    fi
else
    info "Splunk is already running."
fi

# Check package manager availability and locks
info "Checking package manager availability..."
if [ "$DISTRO" == "debian" ]; then
    check_command apt-get
    if [ -f /var/lib/dpkg/lock-frontend ]; then
        error_exit "APT is locked by another process. Wait or kill the process: ps aux | grep apt"
    fi
elif [ "$DISTRO" == "redhat" ] || [ "$DISTRO" == "oracle" ]; then
    check_command "$PKG_MANAGER"
    if [ -f /var/run/yum.pid ] || [ -f /var/run/dnf.pid ]; then
        error_exit "$PKG_MANAGER is locked by another process. Wait or kill the process: ps aux | grep $PKG_MANAGER"
    fi
fi

# Install dependencies
info "Installing dependencies..."
if [ "$DISTRO" == "debian" ]; then
    retry_network "apt-get update"
    apt-get install -y curl apt-transport-https gnupg2 ca-certificates lsb-release iptables || error_exit "Failed to install dependencies. Check /var/log/apt/term.log."
elif [ "$DISTRO" == "redhat" ] || [ "$DISTRO" == "oracle" ]; then
    $PKG_MANAGER install -y curl ca-certificates iptables-services || error_exit "Failed to install dependencies. Check /var/log/yum.log or /var/log/dnf.log."
    if [ $USE_SYSTEMD -eq 1 ]; then
        systemctl enable iptables || info "Failed to enable iptables service. Rules may not persist."
        systemctl start iptables || info "Failed to start iptables service."
    else
        service iptables start || info "Failed to start iptables service."
    fi
fi

# Install Wazuh Manager
info "Installing Wazuh Manager..."
if [ "$DISTRO" == "debian" ]; then
    retry_network "curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import"
    chmod 644 /usr/share/keyrings/wazuh.gpg || error_exit "Failed to set permissions on Wazuh GPG key."
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | tee -a /etc/apt/sources.list.d/wazuh.list || error_exit "Failed to add Wazuh repository."
    retry_network "apt-get update"
    apt-get install -y wazuh-manager || error_exit "Failed to install Wazuh Manager. Check /var/log/apt/term.log."
elif [ "$DISTRO" == "redhat" ] || [ "$DISTRO" == "oracle" ]; then
    retry_network "rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH"
    cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
    [ $? -eq 0 ] || error_exit "Failed to add Wazuh repository."
    $PKG_MANAGER install -y wazuh-manager || error_exit "Failed to install Wazuh Manager. Check /var/log/yum.log or /var/log/dnf.log."
fi

# Start and enable Wazuh Manager
info "Starting Wazuh Manager service..."
if [ $USE_SYSTEMD -eq 1 ]; then
    systemctl daemon-reload || error_exit "Failed to reload systemd daemon."
    systemctl enable wazuh-manager || info "Failed to enable Wazuh Manager service."
    systemctl start wazuh-manager || error_exit "Failed to start Wazuh Manager."
    check_service_active wazuh-manager
else
    service wazuh-manager start || error_exit "Failed to start Wazuh Manager."
    chkconfig wazuh-manager on || info "Failed to enable Wazuh Manager service."
fi

# Wait for Wazuh Manager to fully start
info "Waiting for Wazuh Manager to initialize..."
ATTEMPTS=0
MAX_ATTEMPTS=12
TIMEOUT_SECONDS=120
START_TIME=$(date +%s)
while ! grep -q "Started <ossec-analysisd>" /var/ossec/logs/ossec.log 2>/dev/null; do
    if [ $ATTEMPTS -ge $MAX_ATTEMPTS ] || [ $(( $(date +%s) - START_TIME )) -ge $TIMEOUT_SECONDS ]; then
        info "Wazuh Manager initialization is taking longer than expected. Check /var/ossec/logs/ossec.log for issues."
        break
    fi
    info "Waiting for Wazuh Manager to complete initialization... ($((ATTEMPTS+1))/$MAX_ATTEMPTS)"
    sleep 10
    ATTEMPTS=$((ATTEMPTS+1))
done

if [ $ATTEMPTS -lt $MAX_ATTEMPTS ] && [ -f /var/ossec/logs/ossec.log ] && grep -q "Started <ossec-analysisd>" /var/ossec/logs/ossec.log; then
    success "Wazuh Manager initialized successfully!"
fi

# Install Wazuh API
info "Installing Wazuh API..."
if [ "$DISTRO" == "debian" ]; then
    apt-get install -y wazuh-api || error_exit "Failed to install Wazuh API. Check /var/log/apt/term.log."
elif [ "$DISTRO" == "redhat" ] || [ "$DISTRO" == "oracle" ]; then
    $PKG_MANAGER install -y wazuh-api || error_exit "Failed to install Wazuh API. Check /var/log/yum.log or /var/log/dnf.log."
fi

# Start and enable Wazuh API
info "Starting Wazuh API service..."
if [ $USE_SYSTEMD -eq 1 ]; then
    systemctl enable wazuh-api || info "Failed to enable Wazuh API service."
    systemctl start wazuh-api || error_exit "Failed to start Wazuh API."
    check_service_active wazuh-api
else
    service wazuh-api start || error_exit "Failed to start Wazuh API."
    chkconfig wazuh-api on || info "Failed to enable Wazuh API service."
fi

# Install Wazuh app for Splunk
info "Installing Wazuh app for Splunk..."
mkdir -p /tmp/wazuh_splunk || error_exit "Failed to create temporary directory /tmp/wazuh_splunk."
cd /tmp/wazuh_splunk
retry_network "curl -LO https://packages.wazuh.com/4.x/splunkapp/wazuh-splunk-4.5.2.tar.gz"

# Extract and install the app
tar -xzf wazuh-splunk-4.5.2.tar.gz -C "$SPLUNK_HOME/etc/apps/" || error_exit "Failed to extract Wazuh app to $SPLUNK_HOME/etc/apps/."
chown -R "$SPLUNK_USER:$SPLUNK_GROUP" "$SPLUNK_HOME/etc/apps/wazuh" || error_exit "Failed to set permissions for Wazuh app."

# Restart Splunk to apply changes
info "Restarting Splunk to apply changes..."
if [ -x "$SPLUNK_HOME/bin/splunk" ]; then
    su - "$SPLUNK_USER" -c "$SPLUNK_HOME/bin/splunk restart" || error_exit "Failed to restart Splunk."#!/bin/bash

# Script to install Wazuh Manager on a system with Splunk Enterprise
# For use in cybersecurity competition environments
# Focuses on infrastructure setup only - no active response configuration

# Function to display error messages and exit
error_exit() {
    echo "[ERROR] $1" >&2
    echo "[ERROR] Please check logs and system configuration, then try again." >&2
    exit 1
}

# Function to display information messages
info() {
    echo "[INFO] $1"
}

# Function to display success messages
success() {
    echo "[SUCCESS] $1"
}

# Function to check if a command is available
check_command() {
    command -v "$1" &> /dev/null || error_exit "Command '$1' not found. Please install it and try again."
}

# Function to check if a service is active
check_service_active() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name"; then
        success "$service_name is running."
    else
        error_exit "$service_name failed to start. Check logs with: journalctl -u $service_name"
    fi
}

# Function to retry network commands
retry_network() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        info "Attempt $attempt/$max_attempts: $cmd"
        eval "$cmd" && return 0
        sleep 5
        attempt=$((attempt + 1))
    done
    error_exit "Failed to execute network command: $cmd"
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    error_exit "This script must be run as root"
fi

# Display welcome message
echo "====================================================="
echo "  Wazuh Manager Installation for Splunk Integration  "
echo "====================================================="
echo ""
echo "This script will install the Wazuh Manager and integrate"
echo "it with your existing Splunk Enterprise installation."
echo ""
echo "Press Enter to continue or Ctrl+C to abort..."
read

# Detect Linux distribution
info "Detecting Linux distribution..."
if [ -f /etc/oracle-release ]; then
    SERVER_IP="127.0.0.1"
    sleep 5
    check_service_active splunkd
else
    error_exit "Splunk binary not found at $SPLUNK_HOME/bin/splunk."
fi

# Configure iptables
info "Configuring iptables firewall rules..."
check_command iptables
iptables -A INPUT -p tcp --dport 1514 -j ACCEPT  # Wazuh agent connection
iptables -A INPUT -p tcp --dport 1515 -j ACCEPT  # Wazuh agent enrollment
iptables -A INPUT -p udp --dport 514 -j ACCEPT   # Syslog
iptables -A INPUT -p tcp --dport 55000 -j ACCEPT # Wazuh API
[ $? -eq 0 ] || error_exit "Failed to configure iptables rules."

# Save iptables rules
if [ "$DISTRO" == "debian" ]; then
    if command -v iptables-save > /dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 || info "Failed to save iptables rules. They may not persist after reboot."
    else
        info "iptables-save not found. Rules will not persist after reboot."
    fi
elif [ "$DISTRO" == "redhat" ] || [ "$DISTRO" == "oracle" ]; then
    if command -v service > /dev/null; then
        service iptables save || info "Failed to save iptables rules. They may not persist after reboot."
    else
        info "service command not found. iptables rules may not persist."
    fi
fi

# Get server IP for agent configuration
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    info "Failed to detect server IP. Using localhost as fallback."
    SERVER_IP="127.0.0.1
fi

# Clean up
cd -
rm -rf /tmp/wazuh_splunk || info "Failed to clean up /tmp/wazuh_splunk directory."

# Display registration information
success "Wazuh Manager installation completed successfully!"
success "Your Wazuh Manager IP: $SERVER_IP"
success "Wazuh Manager is now integrated with Splunk Enterprise."
success "You can access the Wazuh app in Splunk at: http://$SERVER_IP:8000 -> Apps -> Wazuh"
info "To register agents, use one of the following methods:"
info "1. Use '/var/ossec/bin/manage_agents' on the manager."
info "2. Use the Wazuh API (port 55000) with appropriate credentials."
info "3. If password-based auth is enabled, check: cat /var/ossec/etc/authd.pass"
echo ""
info "Next steps:"
info "1. Deploy Wazuh agents to your endpoints."
info "2. Configure Splunk Universal Forwarders on endpoints."
info "3. Configure Wazuh to send logs to Splunk (e.g., via syslog or API)."
info "4. Start monitoring your environment through Splunk."
