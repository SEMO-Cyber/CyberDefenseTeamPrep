#!/bin/bash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Define variables
BIND_CONFIG_FILE="/etc/bind/named.conf.options"  # Adjust this path if necessary
LOGGING_CONFIG_FILE="bind9_logging_config.conf"  # Temporary file to store logging config

# Check if the logging block already exists
if grep -q "logging {" "$BIND_CONFIG_FILE"; then
    echo "Logging configuration already exists in $BIND_CONFIG_FILE. Aborting..."
    exit 1
fi

# Backup the original BIND configuration file
backup_file="${BIND_CONFIG_FILE}.bak_$(date +%Y%m%d%H%M%S)"
cp "$BIND_CONFIG_FILE" "$backup_file"
echo "Backup of $BIND_CONFIG_FILE created at $backup_file"

echo "Making directory and files to store bind logs..."
mkdir /var/log/dns; chmod 705 /var/log/dns; chown bind:bind /var/log/dns

# Write the logging configuration to a temporary file
cat << EOF > "$LOGGING_CONFIG_FILE"
logging {
     channel default_log {
          file "/var/log/dns/default" versions 2 size 5m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity info;
     };
     channel auth_servers_log {
          file "/var/log/dns/auth_servers" versions 2 size 20m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity info;
     };
     channel dnssec_log {
          file "/var/log/dns/dnssec" versions 2 size 5m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity info;
     };
     channel zone_transfers_log {
          file "/var/log/dns/zone_transfers" versions 2 size 5m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity info;
     };
     channel ddns_log {
          file "/var/log/dns/ddns" versions 2 size 5m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity info;
     };
     channel client_security_log {
          file "/var/log/dns/client_security" versions 2 size 5m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity info;
     };
     channel rate_limiting_log {
          file "/var/log/dns/rate_limiting" versions 2 size 5m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity info;
     };
     channel queries_log {
          file "/var/log/dns/queries" versions 2 size 20m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity info;
     };
     channel query-errors_log {
          file "/var/log/dns/query-errors" versions 2 size 5m;
          print-time yes;
          print-category yes;
          print-severity yes;
          severity dynamic;
     };
     category default { default_log; };
     category config { default_log; };
     category dispatch { default_log; };
     category network { default_log; };
     category general { default_log; };
     category resolver { auth_servers_log; };
     category cname { auth_servers_log; };
     category delegation-only { auth_servers_log; };
     category lame-servers { auth_servers_log; };
     category edns-disabled { auth_servers_log; };
     category dnssec { dnssec_log; };
     category notify { zone_transfers_log; };
     category xfer-in { zone_transfers_log; };
     category xfer-out { zone_transfers_log; };
     category update{ ddns_log; };
     category update-security { ddns_log; };
     category client{ client_security_log; };
     category security { client_security_log; };
     category rate-limit { rate_limiting_log; };
     category spill { rate_limiting_log; };
     category database { rate_limiting_log; };
     category queries { queries_log; };
     category query-errors { query-errors_log; };
};
EOF

# Append the logging configuration to the BIND configuration file
cat "$LOGGING_CONFIG_FILE" >> "$BIND_CONFIG_FILE"
echo "Logging configuration added to $BIND_CONFIG_FILE"

# Clean up the temporary file
rm -f "$LOGGING_CONFIG_FILE"

# Restart BIND9 service
echo "Restarting BIND9 service..."
systemctl restart bind9

# Check if the service restarted successfully
if systemctl is-active --quiet bind9; then
    echo "BIND9 restarted successfully."
else
    echo "Failed to restart BIND9. Check apparmor profile for bind. If changes were made to the apparmor profile then
    RELOAD APPARMOR. (/etc/apparmor.d/usr.sbin.named)"
    exit 1
fi
