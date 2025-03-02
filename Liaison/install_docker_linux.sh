#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (e.g., with sudo)"
  exit 1
fi

# Determine the Linux distribution
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "Cannot determine Linux distribution: /etc/os-release not found"
  exit 1
fi

# Check if Docker is already installed
if command -v docker &> /dev/null; then
  echo "Docker is already installed"
else
  case "$ID" in
    ubuntu|debian)
      echo "Installing Docker on Debian-based system ($ID)"
      # Update package index and install prerequisites
      apt update
      apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
      # Add Docker's GPG key
      curl -fsSL https://download.docker.com/linux/$ID/gpg | apt-key add -
      # Add Docker repository
      add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$ID $(lsb_release -cs) stable"
      # Update package index again and install Docker
      apt update
      apt install -y docker-ce docker-ce-cli containerd.io
      ;;
    centos|rhel)
      echo "Installing Docker on RedHat-based system ($ID)"
      # Install yum-utils for repository management
      yum install -y yum-utils
      # Add Docker repository (using CentOS repo, compatible with RHEL)
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      # Install Docker
      yum install -y docker-ce docker-ce-cli containerd.io
      ;;
    *)
      echo "Unsupported distribution: $ID"
      exit 1
      ;;
  esac
fi

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Add the original user (if run with sudo) to the Docker group
if [ -n "$SUDO_USER" ]; then
  usermod -aG docker "$SUDO_USER"
  echo "Added $SUDO_USER to the docker group. Please log out and log back in for changes to take effect."
fi

echo "Docker installation completed."