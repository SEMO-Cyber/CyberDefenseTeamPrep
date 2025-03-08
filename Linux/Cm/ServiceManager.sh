#!/bin/bash

# Load config
SERVICE_CONFIG="./serviceup.config"
LOG_FILE="/var/log/service_interrupt.log"

# Function to check services
check_services() {
    while read -r service; do
        if ! systemctl is-active --quiet "$service"; then
            echo "$(date): Warning - Service $service is down. Restarting..."  # Console warning
            echo "$(date): Service $service is down. Restarting..." >> "$LOG_FILE"
            systemctl restart "$service"
            echo "$(date): Service $service was down and has been restarted."  # Console info
        fi
    done < "$SERVICE_CONFIG"
}

# Run in background every 10 seconds
while true; do
    check_services
    sleep 5
done
