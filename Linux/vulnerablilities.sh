#!/bin/bash

# Define report file with a timestamp
REPORT="$HOME/cve_report_$(date +'%Y%m%d_%H%M%S').txt"
CVE_REPORT="$HOME/system_cve_report_$(date +'%Y%m%d_%H%M%S').txt"

# Title and date for the report
echo "CVE Report" > "$CVE_REPORT"
echo "Generated on: $(date)" >> "$CVE_REPORT"
echo "----------------------------------------" >> "$CVE_REPORT"

# 1. Operating System Information and Kernel Version
echo -e "\n[Operating System Information]" >> "$CVE_REPORT"
echo "OS Details:" >> "$CVE_REPORT"
OS_VERSION=$(cat /etc/*-release 2>/dev/null)
echo "$OS_VERSION" >> "$CVE_REPORT"

KERNEL_VERSION=$(uname -r)
echo "Kernel Version: $KERNEL_VERSION" >> "$CVE_REPORT"
# Check for known CVEs for this OS and Kernel version
# Example for Red Hat-based systems: 'yum list installed kernel' | grep kernel

# 2. Installed Applications and Versions
echo -e "\n[Installed Applications]" >> "$CVE_REPORT"
if command -v dpkg &> /dev/null; then
    INSTALLED_PACKAGES=$(dpkg -l)
    echo "$INSTALLED_PACKAGES" >> "$CVE_REPORT"
    echo -e "\n[Checking CVEs for Installed Packages]" >> "$CVE_REPORT"
    # You can use CVE databases like cve.mitre.org or exploit-db to search for installed package versions.
    # For example, you could use `apt list --installed` and match with CVEs from an API or NVD
    echo "For each installed package, check the following CVE databases:" >> "$CVE_REPORT"
    echo "  - https://cve.mitre.org" >> "$CVE_REPORT"
    echo "  - https://www.cvedetails.com" >> "$CVE_REPORT"
elif command -v rpm &> /dev/null; then
    INSTALLED_PACKAGES=$(rpm -qa)
    echo "$INSTALLED_PACKAGES" >> "$CVE_REPORT"
else
    echo "Package manager not found." >> "$CVE_REPORT"
fi

# 3. Running Services and Exposed Ports
echo -e "\n[Running Services]" >> "$CVE_REPORT"
if command -v systemctl &> /dev/null; then
    SERVICES=$(systemctl list-units --type=service --state=running)
    echo "$SERVICES" >> "$CVE_REPORT"
elif command -v service &> /dev/null; then
    SERVICES=$(service --status-all 2>/dev/null | grep running)
    echo "$SERVICES" >> "$CVE_REPORT"
fi

echo -e "\n[Exposed Ports]" >> "$CVE_REPORT"
if command -v ss &> /dev/null; then
    EXPOSED_PORTS=$(ss -tuln | awk '/LISTEN/')
    echo "$EXPOSED_PORTS" >> "$CVE_REPORT"
elif command -v netstat &> /dev/null; then
    EXPOSED_PORTS=$(netstat -tuln | awk '/LISTEN/')
    echo "$EXPOSED_PORTS" >> "$CVE_REPORT"
else
    echo "Neither ss nor netstat found for open ports." >> "$CVE_REPORT"
fi

# 4. Search for Specific Vulnerabilities in Services
# Example for checking CVEs for Apache or Nginx:
echo -e "\n[Check for Known CVEs in Running Services]" >> "$CVE_REPORT"
for SERVICE in $(echo "$SERVICES" | awk '{print $1}'); do
    echo "Checking CVEs for service: $SERVICE" >> "$CVE_REPORT"
    # Example: Use the CVE database or tool like `searchsploit` to find CVEs for the service version
    # E.g., searchsploit apache2 or curl "https://www.cvedetails.com/vulnerability-list.php?vendor_id=45"
done

# 5. Configuration Checks for Sensitive Data
echo -e "\n[Searching for Sensitive Data]" >> "$CVE_REPORT"
grep -Ri "password" /etc 2>/dev/null >> "$CVE_REPORT"
grep -Ri "secret" /home 2>/dev/null >> "$CVE_REPORT"

echo -e "\n[SSH Keys and Credentials]" >> "$CVE_REPORT"
ls ~/.ssh 2>/dev/null >> "$CVE_REPORT"
find / -name "id_rsa" 2>/dev/null >> "$CVE_REPORT"

echo -e "\n[Sudo Permissions for Current User]" >> "$CVE_REPORT"
sudo -l 2>/dev/null >> "$CVE_REPORT"

# 6. File System and SUID/SGID Files
echo -e "\n[SUID/SGID Files]" >> "$CVE_REPORT"
find / -type f -perm -4000 -exec ls -l {} \; 2>/dev/null | column -t >> "$CVE_REPORT"
find / -type f -perm -2000 -exec ls -l {} \; 2>/dev/null | column -t >> "$CVE_REPORT"

# 7. Firewall Configuration and Security Tools
echo -e "\n[Firewall Configuration]" >> "$CVE_REPORT"
if command -v iptables &> /dev/null; then
    iptables -L | column -t >> "$CVE_REPORT"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --list-all | column -t >> "$CVE_REPORT"
elif command -v ufw &> /dev/null; then
    ufw status | column -t >> "$CVE_REPORT"
fi

# Completion message
echo "CVE Report generation complete. Report saved to $CVE_REPORT."
