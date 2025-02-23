#!/bin/bash

read -p "Enter directory to scan: " directory
hash_file="file-check.txt"

read -p "Do you want to rehash the files? (yes/no): " rehash_choice

generate_hash() {
    md5sum "$1" | awk '{print $1}'
}

save_file_hashes() {
    find "$directory" -type f -print0 | while IFS= read -r -d '' file; do
        file_hash=$(generate_hash "$file")
        echo "$file|$file_hash" >> "$hash_file"
    done
}

compare_hashes() {
    if [[ ! -f "$hash_file" ]]; then
        echo "Hash file not found. Run script again to generate it."
        exit 1
    fi

    temp_file="/tmp/current_hashes.txt"
    > "$temp_file"
    find "$directory" -type f -print0 | while IFS= read -r -d '' file; do
        file_hash=$(generate_hash "$file")
        echo "$file|$file_hash" >> "$temp_file"
    done

    diff_output=$(diff "$hash_file" "$temp_file")
    if [[ -n "$diff_output" ]]; then
        echo "File integrity check failed! The following files have been modified:" > /var/log/file-integrity-alert.log
        echo "$diff_output" >> /var/log/file-integrity-alert.log
        modified_files=$(echo "$diff_output" | grep "^>" | awk -F '|' '{print $1}' | tr '\n' ', ' | sed 's/, $//')
        echo "File Integrity Alert: Modified files: $modified_files. Check /var/log/file-integrity-alert.log" | wall
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

while true; do
    compare_hashes
    sleep 30  # Check every 30 seconds
done &
