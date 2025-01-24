#!/bin/bash

# Variables
SPLUNK_URL_RPM="https://www.splunk.com/en_us/download/universal-forwarder.html?locale=en_us"
SPLUNK_INSTALL_DIR="/opt/splunkforwarder"
SPLUNK_SERVER="172.20.241.20:9997"
SPLUNK_VERSION="8.2.6"
SPLUNK_TGZ="splunkforwarder-${SPLUNK_VERSION}-87bd0d129ee3-linux-2.6-x86_64.tgz"
DEPENDENCY_PACKAGES=("wget" "curl" "tar")

# Function to install required dependencies
install_dependencies() {
    echo "Installing required dependencies..."
    for package in "${DEPENDENCY_PACKAGES[@]}"; do
        if ! command -v $package &>/dev/null; then
            echo "$package not found. Installing..."
            if command -v apt-get &>/dev/null; then
                apt-get install -y $package
            elif command -v yum &>/dev/null; then
                yum install -y $package
            else
                echo "Package manager not found. Cannot install $package."
                exit 1
            fi
        fi
    done
}

# Function to detect OS type (Debian/Ubuntu, CentOS/RedHat/Fedora, Oracle Linux)
detect_os() {
    if command -v lsb_release &>/dev/null; then
        OS_TYPE=$(lsb_release -si)
    elif [[ -f /etc/os-release ]]; then
        OS_TYPE=$(grep -i ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        OS_TYPE=$(uname -s)
    fi
    echo $OS_TYPE
}

# Function to install Splunk forwarder on YUM-based systems (CentOS, RHEL, Oracle Linux)
install_splunk_yum() {
    echo "Installing Splunk Universal Forwarder using YUM..."
    cd /tmp
    RPM_URL=$(curl -s $SPLUNK_URL_RPM | grep -oP '"https:.*(?<=download).*x86_64.rpm"' | sed 's/\"//g' | head -n 1)
    if [ -z "$RPM_URL" ]; then
        echo "Error: Unable to find RPM package URL."
        exit 1
    fi
    rpm -Uvh --nodeps $RPM_URL
    yum -y install splunkforwarder.x86_64
}

# Function to install Splunk forwarder on DEB-based systems (Debian, Ubuntu)
install_splunk_deb() {
    echo "Installing Splunk Universal Forwarder using DEB..."
    cd /tmp
    DEB_URL=$(curl -s $SPLUNK_URL_RPM | grep -oP '"https:.*(?<=download).*amd64.deb"' | sed 's/\"//g' | head -n 1)
    if [ -z "$DEB_URL" ]; then
        echo "Error: Unable to find DEB package URL."
        exit 1
    fi
    wget $DEB_URL -O splunkforwarder.deb
    dpkg -i splunkforwarder.deb
}

# Function to install Splunk forwarder on systems where neither YUM nor DEB is available
install_splunk_tarball() {
    echo "Installing Splunk Universal Forwarder using TAR package..."
    cd /tmp
    wget -O $SPLUNK_TGZ "https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/splunkforwarder-${SPLUNK_VERSION}-87bd0d129ee3-linux-2.6-x86_64.tgz"
    tar -xvf $SPLUNK_TGZ -C /opt/
    rm -f $SPLUNK_TGZ
    chown -R root:root $SPLUNK_INSTALL_DIR
}

# Function to configure the Splunk forwarder to forward logs to Splunk server
configure_splunk_forwarder() {
    echo "Configuring Splunk Universal Forwarder..."

    # Configure deployment client
    mkdir -p $SPLUNK_INSTALL_DIR/etc/apps/nwl_all_deploymentclient/local/
    cat > $SPLUNK_INSTALL_DIR/etc/apps/nwl_all_deploymentclient/local/deploymentclient.conf << EOF
[deployment-client]
phoneHomeIntervalInSecs = 60
[target-broker:deploymentServer]
targetUri = $SPLUNK_SERVER
EOF

    # Configure inputs (monitoring /var/log)
    cat > $SPLUNK_INSTALL_DIR/etc/system/local/inputs.conf << EOF
[monitor:///var/log]
disabled = false
index = os_logs
sourcetype = syslog
EOF

    # Configure user-seed.conf (change as per your environment)
    cat > $SPLUNK_INSTALL_DIR/etc/system/local/user-seed.conf << EOF
[user_info]
USERNAME = sysadmin
PASSWORD = Changeme1!
EOF

    # Verify configuration
    $SPLUNK_INSTALL_DIR/bin/splunk cmd btool deploymentclient list --debug

    # Start Splunk forwarder
    $SPLUNK_INSTALL_DIR/bin/splunk start --accept-license --answer-yes
    $SPLUNK_INSTALL_DIR/bin/splunk enable boot-start -user root
}

# Function to install and configure Splunk forwarder
install_and_configure_splunk() {
    OS_TYPE=$(detect_os)
    echo "Detected OS: $OS_TYPE"

    # Install dependencies
    install_dependencies

    case $OS_TYPE in
        debian|ubuntu)
            install_splunk_deb
            ;;
        centos|fedora|rhel|ol)
            install_splunk_yum
            ;;
        *)
            echo "Unsupported OS: $OS_TYPE. Falling back to TAR installation."
            install_splunk_tarball
            ;;
    esac

    # Configure the Splunk forwarder to forward logs to Splunk server
    configure_splunk_forwarder

    echo "Splunk Universal Forwarder installation and configuration complete!"
}

# Main execution
install_and_configure_splunk
