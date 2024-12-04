#!/usr/bin/bash

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Check if a username is provided as an argument
if [[ -z "$1" ]]; then
    echo "Usage: $0 <username>"
    exit 1
fi

# Get the username from the argument
username="$1"

# Determine the home directory based on the user
if [[ "$username" == "root" ]]; then
    SSH_DIR="/root/.ssh"
else
    if ! id "$username" &>/dev/null; then
        echo "User $username does not exist."
        exit 1
    fi
    SSH_DIR="/home/$username/.ssh"
fi

# Ensure the .ssh directory exists
if [[ ! -d "$SSH_DIR" ]]; then
    echo "Creating .ssh directory for $username."
    mkdir -p "$SSH_DIR"
    chown "$username":"$username" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# Backup old SSH keys if they exist
if [[ -f "$SSH_DIR/authorized_keys" ]]; then
    echo "Backing up existing authorized_keys for $username."
    mv "$SSH_DIR/authorized_keys" "$SSH_DIR/authorized_keys.bak_$(date +%F_%T)"
fi

# Generate new SSH keys
echo "Generating new SSH keys for $username."
ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/id_rsa" -N "" -C "$username@$(hostname)"

# Set ownership and permissions for the new keys
chown "$username":"$username" "$SSH_DIR/id_rsa" "$SSH_DIR/id_rsa.pub"
chmod 600 "$SSH_DIR/id_rsa"
chmod 644 "$SSH_DIR/id_rsa.pub"

# Add the new public key to authorized_keys
cat "$SSH_DIR/id_rsa.pub" > "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"
chown "$username":"$username" "$SSH_DIR/authorized_keys"

echo "New SSH keys have been generated and configured for $username."
echo "Private key: $SSH_DIR/id_rsa"
echo "Public key: $SSH_DIR/id_rsa.pub"