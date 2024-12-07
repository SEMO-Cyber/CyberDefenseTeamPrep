#!/bin/bash
#I was lazy. A fully AI generated script to implement banners.


# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Define the banner
BANNER="WARNING: This system is for authorized use only. Unauthorized access or use is prohibited and may result in disciplinary action and/or civil and criminal penalties. All activities on this system are monitored and recorded. By logging in, you agree to comply with all applicable policies and regulations. If you are not an authorized user, disconnect immediately."

# Determine the OS
OS=$(cat /etc/os-release | grep ^NAME= | cut -d= -f2 | tr -d '"')

# For Debian-based systems
if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
    # Update /etc/issue
    echo "$BANNER" | sudo tee /etc/issue
    
    # Update /etc/motd
    echo "$BANNER" | sudo tee /etc/motd
    
    # Create a script in /etc/profile.d/
    cat << EOF | sudo tee /etc/profile.d/login-banner.sh
#!/bin/bash
echo "$BANNER"
EOF
    sudo chmod +x /etc/profile.d/login-banner.sh

# For Red Hat-based systems
elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
    # Update /etc/issue
    echo "$BANNER" | sudo tee /etc/issue
    
    # Update /etc/motd
    echo "$BANNER" | sudo tee /etc/motd
    
    # Create a script in /etc/profile.d/
    cat << EOF | sudo tee /etc/profile.d/login-banner.sh
#!/bin/bash
echo "$BANNER"
EOF
    sudo chmod +x /etc/profile.d/login-banner.sh

else
    echo "Unsupported OS. Please implement the banner manually."
    exit 1
fi

echo "Login banner has been implemented successfully."
