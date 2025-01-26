#!/bin/bash

# Script to install and configure Tailscale VPN on Ubuntu

# --- Script Configuration ---
TAILSCALE_VERSION="stable"  # You can change this to "unstable" for the latest features, but with potential instability

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Functions ---

# Function to display error message and exit
error_exit() {
  echo -e "${RED}Error: $1${NC}"
  exit 1
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check if running as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root."
  fi
}

# --- Main Script ---

# Check if running as root
check_root()

echo -e "${GREEN}Starting Tailscale VPN installation...${NC}"

# Update package list
echo -e "${YELLOW}Updating package list...${NC}"
apt-get update || error_exit "Failed to update package list."

# Install required packages (curl, gnupg, lsb-release)
echo -e "${YELLOW}Installing required packages...${NC}"
if ! command_exists "curl" || ! command_exists "gnupg" || ! command_exists "lsb_release"; then
  apt-get install -y curl gnupg lsb-release || error_exit "Failed to install required packages."
fi

# Add Tailscale repository
echo -e "${YELLOW}Adding Tailscale repository...${NC}"
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/$(lsb_release -cs)/$(lsb_release -cs) $TAILSCALE_VERSION main" | tee /etc/apt/sources.list.d/tailscale.list || error_exit "Failed to add Tailscale repository"
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -rs).noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg  > /dev/null || error_exit "Failed to download Tailscale archive key"

# Update package list again
echo -e "${YELLOW}Updating package list again...${NC}"
apt-get update || error_exit "Failed to update package list after adding Tailscale repository."

# Install Tailscale
echo -e "${YELLOW}Installing Tailscale...${NC}"
apt-get install -y tailscale || error_exit "Failed to install Tailscale."

# Start and enable Tailscale service
echo -e "${YELLOW}Starting and enabling Tailscale service...${NC}"
systemctl enable --now tailscaled || error_exit "Failed to start and enable Tailscale service."

# Authenticate with Tailscale (interactive step)
echo -e "${GREEN}Tailscale installed! Now authenticating...${NC}"
echo -e "${YELLOW}Please complete the authentication process in your web browser.${NC}"
tailscale up

echo -e "${GREEN}Tailscale VPN installation and configuration complete!${NC}"
echo -e "${YELLOW}Your Tailscale IP address can be found using: ${GREEN}tailscale ip -4${NC}"

exit 0