#!/bin/bash

# Function to display error messages and exit
error_exit() {
  echo "Error: $1" >&2
  exit 1
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  error_exit "This script must be run as root."
fi

# Detect the operating system
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID=$ID
  OS_VERSION=$VERSION_ID
else
  error_exit "Could not determine the operating system."
fi

# Check for supported OS and version
case "$OS_ID" in
  ubuntu|debian)
    if [[ ! "$OS_VERSION" =~ ^(20.04|22.04|24.04|24.10|10|11|12)$ ]]; then
      error_exit "Unsupported Ubuntu/Debian version: $OS_VERSION. T-Pot supports Ubuntu 20.04, 22.04, 24.04, 24.10 and Debian 10, 11, 12."
    fi
    ;;
  fedora)
    if [[ ! "$OS_VERSION" =~ ^(37|38|39)$ ]]; then
      error_exit "Unsupported Fedora version: $OS_VERSION. T-Pot supports Fedora 37, 38, 39."
    fi
    ;;
  *)
    error_exit "Unsupported operating system: $OS_ID. This script supports Ubuntu, Debian and Fedora."
    ;;
esac

# Update package list and install dependencies
echo "Updating package list and installing dependencies..."
case "$OS_ID" in
  ubuntu|debian)
    apt-get update || error_exit "Failed to update package list."
    # Add Docker's official GPG key:
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y git curl docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error_exit "Failed to install dependencies."
    ;;
  fedora|rhel)
    dnf update || error_exit "Failed to update package list."
    dnf install -y git curl docker docker-compose || error_exit "Failed to install dependencies."
    ;;
esac

# Clone the T-Pot repository
echo "Cloning T-Pot repository..."
git clone https://github.com/telekom-security/tpotce /opt/tpot || error_exit "Failed to clone T-Pot repository."

# Change directory to T-Pot installation directory
cd /opt/tpot || error_exit "Failed to change directory to /opt/tpot."

# Run the T-Pot installer
echo "Starting T-Pot installation..."
case "$OS_ID" in
  ubuntu|debian)
        # Create a non-root user for T-Pot
        T_POT_USER="tpotuser"
        T_POT_PASS="tpotpassword"  # Choose a strong password

        # Check if the user already exists
        id -u "$T_POT_USER" &>/dev/null

        # If the user doesn't exist, create it
        if [ $? -ne 0 ]; then
        useradd -m -s /bin/bash "$T_POT_USER"
        echo "$T_POT_USER:$T_POT_PASS" | chpasswd
        echo "User '$T_POT_USER' created with password '$T_POT_PASS'"
        fi
        # Switch to the non-root user and run the installer
        sudo -u "$T_POT_USER" ./install.sh --type=user
    ;;
  fedora)
    # Fedora needs SELinux adjustments for T-Pot
    dnf install -y policycoreutils-python-utils || error_exit "Failed to install policycoreutils-python-utils."
    semanage permissive -a docker_t
    ./install.sh --type=user || error_exit "Failed to run T-Pot installer."
    ;;
esac

echo "T-Pot installation completed. Please reboot your system."
echo "After reboot, access the T-Pot web interface (Kibana) at https://<your_server_ip>:64297"

#Make sure to use this command before running the script: sudo apt-get install -y ansible