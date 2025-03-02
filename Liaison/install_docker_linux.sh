#!/bin/bash
set -e

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case $ID in
        debian|ubuntu)
            DISTRO="debian"
            PKG_MANAGER="apt-get"
            ;;
        centos|rhel|fedora)
            DISTRO="redhat"
            if [ "$ID" = "fedora" ] || [ "${VERSION_ID:0:1}" = "8" ]; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            ;;
        *)
            echo "Unsupported distribution: $ID"
            exit 1
            ;;
    esac
else
    echo "Cannot determine distribution"
    exit 1
fi

# Install Docker
if [ "$DISTRO" = "debian" ]; then
    sudo $PKG_MANAGER update
    sudo $PKG_MANAGER install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL "https://download.docker.com/linux/$ID/gpg" | sudo apt-key add -
    echo "deb [arch=amd64] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
    sudo $PKG_MANAGER update
    sudo $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io
elif [ "$DISTRO" = "redhat" ]; then
    if [ "$ID" = "fedora" ]; then
        REPO_URL="https://download.docker.com/linux/fedora/docker-ce.repo"
    else
        REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"
    fi
    if [ "$PKG_MANAGER" = "yum" ]; then
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo "$REPO_URL"
        sudo yum install -y docker-ce docker-ce-cli containerd.io
    elif [ "$PKG_MANAGER" = "dnf" ]; then
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo "$REPO_URL"
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
    fi
fi

# Start and enable Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Install Docker Compose if not already installed
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Installing Docker Compose..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$COMPOSE_VERSION" ]; then
        echo "Failed to fetch latest Docker Compose version. Using default version 2.20.0"
        COMPOSE_VERSION="2.20.0"
    fi
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose installed successfully"
else
    echo "Docker Compose is already installed"
fi

# Verify installations
echo "Verifying installations..."
if command -v docker >/dev/null 2>&1; then
    echo "Docker is installed: $(docker --version)"
else
    echo "Docker is not installed or not in PATH"
fi
if command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose is installed: $(docker-compose --version)"
else
    echo "Docker Compose is not installed or not in PATH"
fi
