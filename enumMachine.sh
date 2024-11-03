#!/bin/bash

# Define report file with a timestamp
REPORT="$HOME/system_report_$(date +'%Y%m%d_%H%M%S').txt"

# Title and date
echo "System Enumeration Report" > "$REPORT"
echo "Generated on: $(date)" >> "$REPORT"
echo "----------------------------------------" >> "$REPORT"

# 1. Operating System Information
echo -e "\n[Operating System Information]" >> "$REPORT"
echo "OS Details:" >> "$REPORT"
uname -a >> "$REPORT"
cat /etc/*-release >> "$REPORT" 2>/dev/null
echo -e "\nKernel Modules:" >> "$REPORT"
lsmod >> "$REPORT" 2>/dev/null

# 2. Applications and Services
echo -e "\n[Installed Applications]" >> "$REPORT"
if command -v dpkg &> /dev/null; then
    dpkg -l >> "$REPORT"
elif command -v rpm &> /dev/null; then
    rpm -qa >> "$REPORT"
else
    echo "Package manager not found." >> "$REPORT"
fi

echo -e "\n[Running Services]" >> "$REPORT"
if command -v systemctl &> /dev/null; then
    systemctl list-units --type=service --state=running >> "$REPORT"
elif command -v service &> /dev/null; then
    service --status-all 2>/dev/null | grep running >> "$REPORT"
else
    echo "No service manager found." >> "$REPORT"
fi

echo -e "\n[Top 10 Memory-Consuming Processes]" >> "$REPORT"
ps aux --sort=-%mem | awk 'NR<=10{print $0}' >> "$REPORT"

echo -e "\n[Cron Jobs]" >> "$REPORT"
for user in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
    echo "Cron jobs for user: $user" >> "$REPORT"
    crontab -u "$user" -l >> "$REPORT" 2>/dev/null || echo "No cron jobs for $user" >> "$REPORT"
done
echo "System-wide cron jobs:" >> "$REPORT"
if [ -f /etc/crontab ]; then
    cat /etc/crontab >> "$REPORT"
else
    echo "No /etc/crontab file found." >> "$REPORT"
fi
for dir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly; do
    if [ -d "$dir" ]; then
        echo "$dir jobs:" >> "$REPORT"
        ls "$dir" >> "$REPORT"
    fi
done

# 3. Communications and Networking
echo -e "\n[Network Configuration]" >> "$REPORT"
ip a >> "$REPORT" 2>/dev/null || ifconfig >> "$REPORT" 2>/dev/null
echo -e "\n[Routing Table]" >> "$REPORT"
route -n >> "$REPORT" 2>/dev/null
echo -e "\n[Listening Ports]" >> "$REPORT"
if command -v ss &> /dev/null; then
    ss -tuln | awk '/LISTEN/' >> "$REPORT"
elif command -v netstat &> /dev/null; then
    netstat -tuln | awk '/LISTEN/' >> "$REPORT"
else
    echo "Neither ss nor netstat found for open ports." >> "$REPORT"
fi
echo -e "\n[Firewall Rules]" >> "$REPORT"
if command -v iptables &> /dev/null; then
    iptables -L >> "$REPORT" 2>/dev/null
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --list-all >> "$REPORT" 2>/dev/null
elif command -v ufw &> /dev/null; then
    ufw status >> "$REPORT" 2>/dev/null
else
    echo "No firewall configuration command found." >> "$REPORT"
fi
echo -e "\n[DNS Servers]" >> "$REPORT"
cat /etc/resolv.conf >> "$REPORT" 2>/dev/null

# 4. Confidential Information and Users
echo -e "\n[User Information]" >> "$REPORT"
cat /etc/passwd >> "$REPORT"
echo -e "\n[Shadow File (if accessible)]" >> "$REPORT"
cat /etc/shadow >> "$REPORT" 2>/dev/null || echo "No access to /etc/shadow" >> "$REPORT"
echo -e "\n[Groups]" >> "$REPORT"
cat /etc/group >> "$REPORT"
echo -e "\n[Currently Logged-In Users]" >> "$REPORT"
who >> "$REPORT"
echo -e "\n[User Login History]" >> "$REPORT"
last >> "$REPORT" 2>/dev/null
echo -e "\n[Environment Variables]" >> "$REPORT"
env >> "$REPORT"

# 5. File Systems
echo -e "\n[Disk Usage]" >> "$REPORT"
df -h >> "$REPORT"
echo -e "\n[Mounted File Systems]" >> "$REPORT"
lsblk >> "$REPORT"
echo -e "\n[SUID and SGID Files]" >> "$REPORT"
find / -type f -perm -4000 -exec ls -l {} \; 2>/dev/null >> "$REPORT"
find / -type f -perm -2000 -exec ls -l {} \; 2>/dev/null >> "$REPORT"
echo -e "\n[Configuration Files]" >> "$REPORT"
find /etc -name "*.conf" 2>/dev/null >> "$REPORT"

# 6. Confidential Information
echo -e "\n[Searching for Sensitive Information]" >> "$REPORT"
grep -Ri "password" /etc 2>/dev/null >> "$REPORT"
grep -Ri "secret" /home 2>/dev/null >> "$REPORT"
echo -e "\n[SSH Keys and Credentials]" >> "$REPORT"
ls ~/.ssh >> "$REPORT" 2>/dev/null
find / -name "id_rsa" 2>/dev/null >> "$REPORT"
echo -e "\n[Sudo Permissions for Current User]" >> "$REPORT"
sudo -l >> "$REPORT" 2>/dev/null

# Completion message
echo "Enumeration complete. Report saved to $REPORT."
