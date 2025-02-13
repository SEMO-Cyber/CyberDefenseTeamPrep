#  This is the first half of the SplunkHarden.sh script. 
#  This is pretty much just for if I need to reset the firewall rules, run backups again, etc.
#  I highly recommend running the SplunkHarden.sh script if you have not already. This script is to
#  make sure I don't accidently overwrite Splunk's stuff.
#
#  Samuel Brucker 2024-2025




# Add at the beginning of the script
LOG_FILE="/var/log/splunk_harden_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

SPLUNK_HOME="/opt/splunk"

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

#Start the basic box hardening
echo "Starting the basic hardening."

echo "Setting device banner"
cat > /etc/issue << EOF
LEGAL DISCLAIMER: This computer system is the property of Team 10 LLC. By using this system, all users acknowledge notice of, and agree to comply with, the Acceptable User of Information Technology Resources Polity (AUP). 
By using this system, you consent to these terms and conditions. Use is also consent to monitoring, logging, and use of logging to prosecute abuse. 
If you do NOT wish to comply with these terms and conditions, you must LOG OFF IMMEDIATELY.
EOF

# Determine package manager
if command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
else
   echo "Neither dnf nor yum found. Exiting."
   exit 1
fi

# Check if nmap is already installed
if command -v nmap &> /dev/null; then
    echo "nmap is already installed"
fi

# Install necessary tools and dependencies
echo "Installing necessary tools and dependencies..."
$PKG_MANAGER install -y curl wget nmap iptables-services cronie

# Verify iptables-save is installed
if ! command -v iptables-save &> /dev/null; then
    echo "iptables-save not found. Installing..."
    $PKG_MANAGER install -y iptables
fi

#
#   IPTables Rules
#
#

# Configure firewall rules using iptables
echo "Configuring firewall rules..."

# Flush existing rules
iptables -F
iptables -X
iptables -Z

# Set default policies
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Allow loopback traffic
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow limited incoming ICMP traffic and log packets that don't fit the rules
#sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -m limit --limit 1/s --limit-burst 5 -j ACCEPT
#sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 0:192 -j LOG --log-prefix "Rate-limit exceeded: " --log-level 4
#sudo iptables -A INPUT -p icmp --icmp-type echo-request -m length ! --length 0:192 -j LOG --log-prefix "Invalid size: " --log-level 4
#sudo iptables -A INPUT -p icmp --icmp-type echo-reply -m limit --limit 1/s --limit-burst 5 -j ACCEPT
#sudo iptables -A INPUT -p icmp -j DROP

# Allow DNS traffic
iptables -A OUTPUT -p udp --dport 53 -m limit --limit 20/min --limit-burst 50 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -m limit --limit 20/min --limit-burst 50 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -m state --state ESTABLISHED -j ACCEPT

# Allow HTTP/HTTPS traffic
iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m limit --limit 100/min --limit-burst 200 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW -m limit --limit 100/min --limit-burst 200 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# Allow Splunk-specific traffic
iptables -A INPUT -p tcp --dport 9997 -m conntrack --ctstate NEW -j ACCEPT  #Splunk Forwarders
iptables -A OUTPUT -p tcp --sport 9997 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

iptables -A INPUT -p tcp --dport 514 -m conntrack --ctstate NEW -j ACCEPT   #Logs from Palo
iptables -A OUTPUT -p tcp --sport 514 -m conntrack --ctstate ESTABLISHED -j ACCEPT

#sudo iptables -A INPUT -p tcp --dport 8089 -j ACCEPT   #NOT NEEDED
#sudo iptables -A OUTPUT -p tcp --sport 8089 -j ACCEPT  #NOT NEEDED

iptables -A INPUT -p tcp --dport 8000 -m conntrack --ctstate NEW -j ACCEPT  #Splunk webGUI
iptables -A OUTPUT -p tcp --sport 8000 -m conntrack --ctstate ESTABLISHED -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "DROP-IN:" --log-level 4 --log-ip-options --log-tcp-options --log-tcp-sequence
iptables -A OUTPUT -j LOG --log-prefix "DROP-OUT:" --log-level 4 --log-ip-options --log-tcp-options --log-tcp-sequence

mkdir /etc/iptables

# Save the rules
iptables-save > /etc/iptables/rules.v4

# disable and remove unneeded firewalld. It's not needed.
systemctl stop firewalld

systemctl disable firewalld

$PKG_MANAGER remove firewalld -y


#
#   Backup Configurations
#
#

# Create backup directory if it doesn't exist
BACKUP_DIR="/etc/BacService/"
mkdir -p "$BACKUP_DIR"

# Backup network interface configurations (critical for security)
echo "Backing up network interface configurations..."
cp -R /etc/sysconfig/network-scripts/* "$BACKUP_DIR"    # Network interface configs
cp /etc/sysconfig/network "$BACKUP_DIR"                 # Network configuration
cp /etc/resolv.conf "$BACKUP_DIR"                       # DNS configuration
cp /etc/iptables/rules.v4 "$BACKUP_DIR"                 # A redundant backup for the iptable rules

echo "Backing up original Splunk configurations..."
mkdir -p "$BACKUP_DIR/splunkORIGINAL"
cp -R "$SPLUNK_HOME" "$BACKUP_DIR/splunkORIGINAL"

#
#   System Hardening
#
#

echo "restricting user creation to root only"
chmod 700 /usr/sbin/useradd
chmod 700 /usr/sbin/groupadd

# Clear crontab
echo "Clearing crontab..."
echo "" > /etc/crontab

# Password Management
echo "Setting new passwords..."

# Set root password
while true; do
    echo "Enter new root password: "
    stty -echo
    read rootPass
    stty echo
    echo "Confirm root password: "
    stty -echo
    read confirmRootPass
    stty echo

    if [ "$rootPass" = "$confirmRootPass" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

echo "root:$rootPass" | chpasswd

# Set sysadmin password
while true; do
    echo "Enter new sysadmin password: "
    stty -echo
    read sysadminPass
    stty echo
    echo "Confirm sysadmin password: "
    stty -echo
    read confirmSysadminPass
    stty echo

    if [ "$sysadminPass" = "$confirmSysadminPass" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

echo "sysadmin:$sysadminPass" | chpasswd

# Say hi to BackdoorBob! This account is in case I get locked out of the root and sysadmin account
echo "Creating user 'bbob'..."
useradd bbob

#set bbob's password
while true; do
   echo "Enter password for user bbob:"
   stty -echo
   read bbobPass
   stty echo
   echo "Confirm bbob password:"
   stty -echo
   read confirmBbobPass

   if [ "$bbobPass" = "$confirmBbobPass" ]; then
      break
   else
      echo "Passwords do not match. Please try again."
   fi
done
echo "bbob:$bbobPass" | chpasswd

echo "Adding bbob sudo"
usermod -aG wheel bbob

# Uninstall SSH
echo "Uninstalling SSH..."
$PKG_MANAGER remove openssh-server -y

# Harden cron
echo "Locking down Cron and AT permissions..."
touch /etc/cron.allow
chmod 600 /etc/cron.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/cron.deny

touch /etc/at.allow
chmod 600 /etc/at.allow
awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/at.deny

# Final steps
echo "Final steps for the basic box hardening..."
$PKG_MANAGER autoremove -y
