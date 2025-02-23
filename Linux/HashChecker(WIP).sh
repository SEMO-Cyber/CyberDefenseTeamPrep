#!/bin/bash

path_file="scan_paths.txt"
hash_file="file-check.txt"

# Check if the path file exists and prompt the user to enter paths if not
if [[ ! -f "$path_file" ]]; then
    read -p "Enter directories or files to scan (separated by space): " -a paths
    echo "${paths[@]}" > "$path_file"  # Save the paths to a file
else
    # Read paths from the file
    IFS=' ' read -r -a paths < "$path_file"
fi

# Ask if the user wants to add more paths to scan
read -p "Do you want to add additional directories or files to scan? (yes/no): " add_choice
if [[ "$add_choice" == "yes" ]]; then
    read -p "Enter the additional directory or file to scan: " new_path
    paths+=("$new_path")  # Add the new path to the list
    echo "$new_path" >> "$path_file"  # Save the new path to the path file
fi

read -p "Do you want to rehash the files? (yes/no): " rehash_choice

generate_hash() {
    md5sum "$1" | awk '{print $1}'
}

save_file_hashes() {
    for path in "${paths[@]}"; do
        if [[ -d "$path" ]]; then
            # If it's a directory, find all files within it
            find "$path" -type f -print0 | while IFS= read -r -d '' file; do
                file_hash=$(generate_hash "$file")
                echo "$file|$file_hash" >> "$hash_file"
            done
        elif [[ -f "$path" ]]; then
            # If it's an individual file, just hash it
            file_hash=$(generate_hash "$path")
            echo "$path|$file_hash" >> "$hash_file"
        fi
    done
}

compare_hashes() {
    if [[ ! -f "$hash_file" ]]; then
        echo "Hash file not found. Run script again to generate it."
        exit 1
    fi

    temp_file="/tmp/current_hashes.txt"
    > "$temp_file"
    
    for path in "${paths[@]}"; do
        if [[ -d "$path" ]]; then
            # If it's a directory, find all files within it
            find "$path" -type f -print0 | while IFS= read -r -d '' file; do
                file_hash=$(generate_hash "$file")
                echo "$file|$file_hash" >> "$temp_file"
            done
        elif [[ -f "$path" ]]; then
            # If it's an individual file, just hash it
            file_hash=$(generate_hash "$path")
            echo "$path|$file_hash" >> "$temp_file"
        fi
    done

    diff_output=$(diff "$hash_file" "$temp_file")
    if [[ -n "$diff_output" ]]; then
        echo "File integrity check failed! The following files have been modified:" > /tmp/file-integrity-alert.log
        echo "$diff_output" >> /tmp/file-integrity-alert.log
        modified_files=$(echo "$diff_output" | grep "^>" | awk -F '|' '{print $1}' | tr '\n' ', ' | sed 's/, $//')
        echo "File Integrity Alert: Modified files: $modified_files. Check /tmp/file-integrity-alert.log" | wall
    fi
    rm "$temp_file"
}

echo "Running file integrity scan in the background."
if [[ "$rehash_choice" == "yes" ]]; then
    echo "Rehashing files and updating records."
    > "$hash_file"
    save_file_hashes
elif [[ ! -f "$hash_file" ]]; then
    echo "Generating initial file hash records."
    save_file_hashes
fi

# Loop to periodically check integrity
while true; do
    compare_hashes
    sleep 30  # Check every 30 seconds
done &
