#!/bin/bash

# --- Script to Install and Configure TFTP Server (tftpd-hpa) ---

# Function to display messages in color
info() {
    echo -e "\e[32m[INFO] $1\e[0m" # Green
}

error() {
    echo -e "\e[31m[ERROR] $1\e[0m" # Red
    exit 1
}

# Function to check if the script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root."
    fi
}

# Function to install tftpd-hpa
install_tftp_server() {
    info "Updating package list..."
    apt-get update || error "Failed to update package list."

    info "Installing tftpd-hpa..."
    apt-get install -y tftpd-hpa || error "Failed to install tftpd-hpa."
}

# Function to configure network settings
configure_network() {
    # Default values (can be customized)
    DEFAULT_TFTP_DIRECTORY="/var/lib/tftpboot"
    DEFAULT_TFTP_ADDRESS="0.0.0.0:69"
    DEFAULT_OPTIONS="--secure" # Other common options: --create (allow uploads)

    # User input for TFTP directory
    read -p "Enter the TFTP root directory [$DEFAULT_TFTP_DIRECTORY]: " tftp_directory
    tftp_directory="${tftp_directory:-$DEFAULT_TFTP_DIRECTORY}" # Use default if empty

    # User input for TFTP address
    read -p "Enter the TFTP server address [$DEFAULT_TFTP_ADDRESS]: " tftp_address
    tftp_address="${tftp_address:-$DEFAULT_TFTP_ADDRESS}"

    # User input for options
    read -p "Enter additional TFTP options [$DEFAULT_OPTIONS]: " tftp_options
    tftp_options="${tftp_options:-$DEFAULT_OPTIONS}"

    # Configure /etc/default/tftpd-hpa
    sed -i "s|TFTP_DIRECTORY=.*|TFTP_DIRECTORY=\"$tftp_directory\"|" /etc/default/tftpd-hpa
    sed -i "s|TFTP_ADDRESS=.*|TFTP_ADDRESS=\"$tftp_address\"|" /etc/default/tftpd-hpa
    sed -i "s|TFTP_OPTIONS=.*|TFTP_OPTIONS=\"$tftp_options\"|" /etc/default/tftpd-hpa

    # Create TFTP directory if it doesn't exist and set permissions
    if [[ ! -d "$tftp_directory" ]]; then
        mkdir -p "$tftp_directory"
        info "Created TFTP directory: $tftp_directory"
    fi
    chown tftp:tftp "$tftp_directory"
    chmod 755 "$tftp_directory"

    info "TFTP server configured:"
    info "  Directory: $tftp_directory"
    info "  Address: $tftp_address"
    info "  Options: $tftp_options"
}

# Function to start and enable the TFTP service
start_tftp_service() {
    info "Restarting tftpd-hpa service..."
    systemctl restart tftpd-hpa || error "Failed to restart tftpd-hpa."

    info "Enabling tftpd-hpa service..."
    systemctl enable tftpd-hpa || error "Failed to enable tftpd-hpa."

    info "tftpd-hpa service started and enabled."
}

# --- Main Script ---

check_root

install_tftp_server()

configure_network()

start_tftp_service()

info "TFTP server installation and configuration complete!"