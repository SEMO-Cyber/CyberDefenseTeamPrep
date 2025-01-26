#!/bin/bash

# Function to calculate the SHA-256 hash of a file
calculate_hash() {
    local filepath="$1"
    sha256sum "$filepath" | awk '{print $1}'
}

# Function to monitor files in a directory
monitor_files() {
    local directory="$1"
    local interval="${2:-5}" # Default interval is 5 seconds

    echo "Monitoring directory: $directory"
    declare -A initial_hashes

    # Create the directory if it doesn't exist
    if [[ ! -d "$directory" ]]; then
        mkdir -p "$directory"
        echo "Created directory: $directory"
    fi

    # Get initial hashes
    find "$directory" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' filepath; do
        initial_hashes["$filepath"]=$(calculate_hash "$filepath")
        echo "Initial hash for $filepath: ${initial_hashes[$filepath]}"
    done

    echo "Starting monitoring loop..."
    while true; do
        sleep "$interval"
        echo "Checking for changes in $directory..."

        declare -A current_files
        find "$directory" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' filepath; do
            current_files["$filepath"]=1
            current_hash=$(calculate_hash "$filepath")

            if [[ -z "${initial_hashes[$filepath]}" ]]; then
                echo "  New file detected: $filepath"
                initial_hashes["$filepath"]="$current_hash"
            elif [[ "${initial_hashes[$filepath]}" != "$current_hash" ]]; then
                echo "  File modified: $filepath"
                initial_hashes["$filepath"]="$current_hash"
            fi
        done

        # Check for deleted files
        for filepath in "${!initial_hashes[@]}"; do
            if [[ -z "${current_files[$filepath]}" ]]; then
                echo "  File deleted: $filepath"
                unset "initial_hashes[$filepath]"
            fi
        done
    done
}

# --- Main Execution ---
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <directory_to_monitor>"
    exit 1
fi

directory_to_monitor="$1"

if [[ ! -d "$directory_to_monitor" ]]; then
    echo "Error: Invalid directory path provided."
    exit 1
fi

# Monitor the files in the specified directory
monitor_files "$directory_to_monitor" 5