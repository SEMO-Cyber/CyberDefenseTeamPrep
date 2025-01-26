#!/bin/bash

# Script to install Splunk Universal Forwarder 9.1.1 on various Linux distributions
# Supported distributions: Debian, Ubuntu, CentOS, Fedora, Oracle Linux

# --- Variables ---
SPLUNK_VERSION="9.1.1"
SPLUNK_PACKAGE="splunkforwarder-${SPLUNK_VERSION}"
DOWNLOAD_URL="https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux"
INSTALL_DIR="/opt/splunkforwarder"

# --- Functions ---

# Function to detect the operating system and version
detect_os() {
  if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID}"
  elif [ -f /etc/redhat-release ]; then
    # shellcheck source=/dev/null
    . /etc/redhat-release
    OS_ID=$(awk '{print tolower($1)}' /etc/redhat-release | cut -d ' ' -f1 | sed 's/linux$//')
      if [[ "$OS_ID" == "oracle" ]]; then
         OS_ID="oraclelinux"
      fi
     OS_VERSION=$(sed -E 's/.* ([0-9]+(\.[0-9]+)?).*$/\1/' /etc/redhat-release)
  else
    echo "Unsupported operating system."
    exit 1
  fi
}

# Function to download the Splunk Universal Forwarder package
download_package() {
  echo "Downloading Splunk Universal Forwarder ${SPLUNK_VERSION}..."
  case "${OS_ID}" in
    debian|ubuntu)
      wget "${DOWNLOAD_URL}/${SPLUNK_PACKAGE}-linux-2.6-amd64.deb" -O "${SPLUNK_PACKAGE}.deb"
      ;;
    centos|fedora|oraclelinux|rhel)
      wget "${DOWNLOAD_URL}/${SPLUNK_PACKAGE}-linux-2.6-x86_64.rpm" -O "${SPLUNK_PACKAGE}.rpm"
      ;;
    *)
      echo "Unsupported operating system for download."
      exit 1
      ;;
  esac
}

# Function to install the Splunk Universal Forwarder package
install_package() {
  echo "Installing Splunk Universal Forwarder ${SPLUNK_VERSION}..."
  case "${OS_ID}" in
    debian|ubuntu)
      sudo dpkg -i "${SPLUNK_PACKAGE}.deb"
      ;;
    centos|fedora|oraclelinux|rhel)
        sudo rpm -ivh "${SPLUNK_PACKAGE}.rpm"
      ;;
    *)
      echo "Unsupported operating system for installation."
      exit 1
      ;;
  esac
}

# Function to accept the license agreement
accept_license() {
   echo "Accepting Splunk License..."
   sudo ${INSTALL_DIR}/bin/splunk start --accept-license --answer-yes --no-prompt
}

# Function to enable boot start
enable_boot_start() {
  echo "Enabling Splunk Universal Forwarder to start at boot..."
  case "${OS_ID}" in
      debian|ubuntu)
          if command -v systemctl &> /dev/null; then
              sudo systemctl enable splunk
          elif command -v update-rc.d &> /dev/null; then
              sudo update-rc.d splunk defaults
          else
             echo "Could not find init system to enable boot-start"
          fi
        ;;
      centos|fedora|oraclelinux|rhel)
          sudo systemctl enable splunk
        ;;
      *)
         echo "Could not find init system to enable boot-start"
         ;;
  esac
}

# --- Main Script ---

# Detect the operating system
detect_os()

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

# Download the package
download_package

# Install the package
install_package

# Accept License
accept_license

# Enable boot-start (optional, but recommended)
enable_boot_start

echo "Splunk Universal Forwarder ${SPLUNK_VERSION} installation complete."
echo "You can configure the forwarder by running: ${INSTALL_DIR}/bin/splunk help"
echo "Remember to configure inputs and outputs for proper functionality."

# --- Cleanup ---
case "${OS_ID}" in
  debian|ubuntu)
    rm -f "${SPLUNK_PACKAGE}.deb"
    ;;
  centos|fedora|oraclelinux|rhel)
    rm -f "${SPLUNK_PACKAGE}.rpm"
    ;;
esac

exit 0