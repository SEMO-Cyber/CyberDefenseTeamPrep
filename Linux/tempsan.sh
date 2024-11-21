#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 [-v] [-p PORT_RANGE] [--http-port PORT] [--https-port PORT]"
    echo "-v: Enable verbose mode"
    echo "-p PORT_RANGE: Specify port range (e.g., 1-65535)"
    echo "--http-port PORT: Specify HTTP port (default: 80)"
    echo "--https-port PORT: Specify HTTPS port (default: 443)"
}

# Parse command-line arguments
VERBOSE=false
PORT_RANGE="1-65535"
HTTP_PORT=80
HTTPS_PORT=443

while getopts ":v:p:h:H:" opt; do
    case $opt in
        v ) VERBOSE=true;;
        p ) PORT_RANGE="$OPTARG";;
        h ) HTTP_PORT="$OPTARG";;
        H ) HTTPS_PORT="$OPTARG";;
        \? ) echo "Invalid option: -$OPTARG" >&2; usage >&2; exit 1 ;;
        : ) echo "Option -$OPTARG requires an argument." >&2; usage >&2; exit 1 ;;
    esac
done

# Check if nmap is installed
if ! command -v nmap &> /dev/null; then
    echo "Error: nmap is not installed. Please install nmap and try again."
    exit 1
fi

# Perform the nmap scan
echo "Starting nmap scan..."
nmap -v -p $PORT_RANGE --script http-* -p $HTTP_PORT,$HTTPS_PORT localhost > "scanResults.txt"

# Display scan results
if [ "$VERBOSE" = true ]; then
    cat "scanResults.txt"
else
    echo "Scan completed. Results saved in scanResults.txt"
fi
