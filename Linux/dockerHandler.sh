#!/bin/bash

# Check if the script is run as root (Docker requires root privileges)
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Docker command alias
DOCKER_CMD="docker"

# Log file to store Docker monitoring output
LOG_FILE="docker_monitor.log"

# Check if Docker is installed
if ! command -v $DOCKER_CMD &> /dev/null; then
    echo "Docker is not installed. Please install Docker and try again."
    exit 1
fi

# Create a results directory to store reports if it doesn't exist
mkdir -p results

# Function to log Docker events in real-time
log_docker_events() {
    echo "Monitoring Docker events..." >> $LOG_FILE
    $DOCKER_CMD events --filter 'event=start' --filter 'event=stop' --filter 'event=die' --filter 'event=health' >> $LOG_FILE &
    echo "Docker events logging started in background."
}

# Function to monitor container status and resource usage
monitor_containers() {
    echo "Monitoring Docker containers..." >> $LOG_FILE
    # Get the list of running containers
    containers=$($DOCKER_CMD ps -q)

    if [ -z "$containers" ]; then
        echo "No running containers found." >> $LOG_FILE
    else
        # Loop through containers to gather their status and resource usage
        for container in $containers; do
            container_name=$($DOCKER_CMD inspect --format '{{.Name}}' $container | sed 's/\///')
            container_status=$($DOCKER_CMD inspect --format '{{.State.Status}}' $container)
            container_health=$($DOCKER_CMD inspect --format '{{.State.Health.Status}}' $container)
            
            # Resource Usage (CPU and Memory)
            container_stats=$($DOCKER_CMD stats --no-stream --format "{{.Name}}: CPU {{.CPUPerc}} | Memory {{.MemUsage}}" $container)

            echo "Container: $container_name, Status: $container_status, Health: $container_health" >> $LOG_FILE
            echo "$container_stats" >> $LOG_FILE
        done
    fi
}

# Function to fetch logs from all containers
fetch_container_logs() {
    echo "Fetching logs for all containers..." >> $LOG_FILE
    containers=$($DOCKER_CMD ps -q)

    if [ -z "$containers" ]; then
        echo "No running containers found." >> $LOG_FILE
    else
        for container in $containers; do
            container_name=$($DOCKER_CMD inspect --format '{{.Name}}' $container | sed 's/\///')
            echo "Logs for container: $container_name" >> $LOG_FILE
            $DOCKER_CMD logs $container >> $LOG_FILE
        done
    fi
}

# Function to monitor Docker system-wide stats
monitor_system_stats() {
    echo "Monitoring system-wide Docker statistics..." >> $LOG_FILE
    $DOCKER_CMD system df >> $LOG_FILE
    $DOCKER_CMD info >> $LOG_FILE
}

# Function to monitor specific container
monitor_specific_container() {
    read -p "Enter the container ID or name to monitor: " container
    if $DOCKER_CMD ps -q --filter "id=$container" --filter "name=$container" > /dev/null; then
        echo "Monitoring container: $container" >> $LOG_FILE
        $DOCKER_CMD stats --no-stream $container >> $LOG_FILE
        $DOCKER_CMD logs $container >> $LOG_FILE
    else
        echo "Container $container not found." >> $LOG_FILE
    fi
}

# Function to check Docker health and status
check_docker_health() {
    echo "Checking Docker health..." >> $LOG_FILE
    docker_info=$($DOCKER_CMD info)
    
    if echo "$docker_info" | grep -q "Server Version"; then
        echo "Docker is running fine." >> $LOG_FILE
    else
        echo "Docker is not running. Please start Docker." >> $LOG_FILE
    fi
}

# Main menu for monitoring options
while true; do
    echo -e "\nDocker Monitoring Menu"
    echo "1. Monitor Docker containers and resource usage"
    echo "2. Fetch logs for all containers"
    echo "3. Monitor system-wide Docker stats"
    echo "4. Monitor a specific container"
    echo "5. Check Docker health"
    echo "6. Log Docker events"
    echo "7. Exit"
    read -p "Select an option [1-7]: " option

    case $option in
        1)
            monitor_containers
            ;;
        2)
            fetch_container_logs
            ;;
        3)
            monitor_system_stats
            ;;
        4)
            monitor_specific_container
            ;;
        5)
            check_docker_health
            ;;
        6)
            log_docker_events
            ;;
        7)
            echo "Exiting."
            break
            ;;
        *)
            echo "Invalid option. Please select a valid option from the menu."
            ;;
    esac
done
