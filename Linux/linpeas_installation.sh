#!/bin/bash

# Set installation directory
INSTALL_DIR="/root/CyberDefenseTeamPrep/Linux/"

# Function to download linpeas using preferred method
download_linpeas() {
    echo "Downloading linpeas..."

    # Prefer wget if available, fall back to curl
    if command -v wget >/dev/null 2>&1; then
        wget https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh
    else
        curl -LO https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh
    fi
}

# Main program flow
main() {
    
    # Check if tools are already installed
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        install_download_tools
    fi
    
    # Download linpeas
    download_linpeas
    
    # Make script executable
    chmod +x linpeas.sh
    
    echo "Installation complete!"
    echo "Usage: $INSTALL_DIR/linpeas.sh [options]"
}

main
