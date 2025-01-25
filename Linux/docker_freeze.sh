#!/bin/bash

# Function to pause all running Docker containers
pause_all_containers() {
    echo "Pausing all running Docker containers..."

    # Get the IDs of all running containers
    container_ids=$(docker ps --format "{{.ID}}")

    # Check if there are any running containers
    if [ -z "$container_ids" ]; {
        echo "No running Docker containers found."
    } else
        # Iterate through each container ID and pause it
        for container_id in $container_ids; do
            echo "Pausing container: $container_id"
            docker pause $container_id
        done

        echo "All running Docker containers have been paused."
    fi
}

# Call the function to pause all containers
pause_all_containers
