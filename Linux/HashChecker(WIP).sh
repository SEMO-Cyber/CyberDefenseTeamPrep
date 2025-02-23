#!/bin/bash

read -p "Enter directory to scan: " directory
hash_file="file-check.json"

read -p "Do you want to rehash the files? (yes/no): " rehash_choice

generate_hash() {
    md5sum "$1" | awk '{print $1}'
}

get_files() {
    local dir="$1"
    local json="{"
    
    while IFS= read -r -d '' file; do
        rel_path="${file#$dir/}"
        file_hash=$(generate_hash "$file")
        json+="\"$rel_path\": {\"hash\": \"$file_hash\", \"path\": \"$file\"},"
    done < <(find "$dir" -type f -print0)
    
    json="${json%,}" # Remove trailing comma
    json+="}"
    echo "$json"
}

save_file_hashes() {
    get_files "$directory" > "$hash_file"
}

compare_hashes() {
    if [[ ! -f "$hash_file" ]]; then
        echo "Hash file not found. Run script again to generate it."
        exit 1
    fi

    current_json=$(get_files "$directory")
    old_json=$(cat "$hash_file")
    
    diff_output=$(diff <(echo "$old_json" | jq -r 'to_entries | .[] | "\(.key) \(.value.hash)"') \
                        <(echo "$current_json" | jq -r 'to_entries | .[] | "\(.key) \(.value.hash)"'))
    
    if [[ -n "$diff_output" ]]; then
        echo "File integrity check failed! The following files have been modified:" > /tmp/file-integrity-alert.log
        echo "$diff_output" >> /tmp/file-integrity-alert.log
        modified_files=$(echo "$diff_output" | awk '{print $2}' | tr '\n' ', ' | sed 's/, $//')
        notify-send "File Integrity Alert" "Modified files: $modified_files. Check /tmp/file-integrity-alert.log"
    fi
}

echo "Running file integrity scan in the background."
if [[ "$rehash_choice" == "yes" ]]; then
    echo "Rehashing files and updating records."
    save_file_hashes
elif [[ ! -f "$hash_file" ]]; then
    echo "Generating initial file hash records."
    save_file_hashes
fi

while true; do
    compare_hashes
    sleep 60  # Check every 60 seconds
done &
