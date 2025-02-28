#!/bin/bash

# Set installation directory
INSTALL_DIR="/root/linpeas"

# Function to download linpeas using preferred method
download_linpeas() {
    echo "Downloading linpeas..."

    # Prefer wget if available, fall back to curl
    if command -v wget >/dev/null 2>&1; then
        wget https://raw.githubusercontent.com/carlospolop/privilege-escalation-awesome-scripts-suite/master/linPEAS/linpeas.sh
    else
        curl -LO https://raw.githubusercontent.com/carlospolop/privilege-escalation-awesome-scripts-suite/master/linPEAS/linpeas.sh
    fi
}

# Main program flow
main() {
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit 1
    
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
