#!/bin/bash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

SCRIPT_NAME=$(basename "$0")
PID_FILE="/tmp/${SCRIPT_NAME}.pid" 

stop_old_process() {
    if [[ -f "$PID_FILE" ]]; then
        OLD_PID=$(cat "$PID_FILE")
        # Check if the process is actually running
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo "Stopping old instance of the script (PID: $OLD_PID)..."
            kill -9 "$OLD_PID"
            sleep 2  # Wait for the process to terminate
        fi
        rm -f "$PID_FILE"
    fi
}

generate_hash() {
   md5sum "$1" | awk '{print $1}'
}

save_file_hashes() {
   local TARGET_PATH="$1"
   # argument was provieded, used that instead
   if [[ -n "$TARGET_PATH" ]]; then
      if [[ -d "$TARGET_PATH" ]]; then
         # If it's a directory, find all files within it
         find "$TARGET_PATH" -type f -print0 | while IFS= read -r -d '' FILE; do
            FILE_HASH=$(generate_hash "$FILE")
            echo "$FILE|$FILE_HASH" >> "$HASH_FILE"
         done
      elif [[ -f "$TARGET_PATH" ]]; then
         # If it's an individual file, just hash it
         FILE_HASH=$(generate_hash "$TARGET_PATH")
         echo "$TARGET_PATH|$FILE_HASH" >> "$HASH_FILE"
      fi

   # argument was not provided, used paths array
   else
      for DIR in "${PATHS[@]}"; do
         if [[ -d "$DIR" ]]; then
            find "$DIR" -type f -print0 | while IFS= read -r -d '' FILE; do
               FILE_HASH=$(generate_hash "$FILE")
               echo "$FILE|$FILE_HASH" >> "$HASH_FILE"
            done
         elif [[ -f "$DIR" ]]; then
            FILE_HASH=$(generate_hash "$DIR")
            echo "$DIR|$FILE_HASH" >> "$HASH_FILE"
         fi
      done
   fi
}

compare_hashes() {
    if [[ ! -s "$HASH_FILE" ]]; then
        echo "Hash file not found or is empty. Run script again to generate it."
        exit 1
    fi

    TEMP_FILE="/tmp/current_hashes.txt"
    > "$TEMP_FILE"
    
    for DIR in "${PATHS[@]}"; do
        if [[ -d "$DIR" ]]; then
            # If it's a directory, find all files within it
            find "$DIR" -type f -print0 | while IFS= read -r -d '' FILE; do
                FILE_HASH=$(generate_hash "$FILE")
                echo "$FILE|$FILE_HASH" >> "$TEMP_FILE"
            done
        elif [[ -f "$DIR" ]]; then
            # If it's an individual file, just hash it
            FILE_HASH=$(generate_hash "$DIR")
            echo "$DIR|$FILE_HASH" >> "$TEMP_FILE"
        fi
    done

    DIFF_OUTPUT=$(diff "$HASH_FILE" "$TEMP_FILE")
    if [[ -n "$DIFF_OUTPUT" ]]; then
        echo "File integrity check failed! The following files have been modified:" > /var/log/file-integrity-alert.log
        echo "$DIFF_OUTPUT" >> /var/log/file-integrity-alert.log
        MODIFIED_FILES=$(echo "$DIFF_OUTPUT" | grep "^>" | sed 's/^> //' | awk -F '|' '{print $1}' | paste -sd "   " -)
        echo "File Integrity Alert: Modified files: $MODIFIED_FILES. Check /var/log/file-integrity-alert.log"
    fi
    rm "$TEMP_FILE"
}

# Remove old script process and create a new one
stop_old_process()
echo $$ > "$PID_FILE"
echo "Starting new instance of the script (PID: $$)..."

mkdir /etc/conf_srv $$ chmod 700
PATH_FILE="/etc/conf_srv/scan_paths.txt"
HASH_FILE="/etc/conf_srv/file-check.txt"

# Check if the file does not exists or is empty
if [[ ! -s "$PATH_FILE" ]]; then
    read -p "Enter directories or files to monitor (separated by space): " -a PATHS
    echo "${PATHS[@]}" > "$PATH_FILE"  # Save the paths to a file
else
    IFS=' ' read -r -a PATHS < "$PATH_FILE"
   read -p "Do you want to add additional directories or files to monitor? (yes/no): " ADD_CHOICE
   if [[ "$ADD_CHOICE" == "yes" ]]; then
       read -p "Enter directories or files to monitor (separated by space): " -a NEW_PATHS
       PATHS+=("${NEW_PATHS[@]}")  # Add the new paths to the list
       echo "${NEW_PATHS[@]}" >> "$PATH_FILE"
   fi
   echo "Would you like to hash the files?"
   echo "1) Hash all paths"
   echo "2) Select a specific path to hash"
   echo "3) Skip hashing"
   read -p "Enter your choice (1/2/3): " HASH_CHOICE
fi

# run through hashing options
if [[ "$HASH_CHOICE" == "1" ]]; then
    echo "Hashing files and updating records."
    > "$HASH_FILE"
    save_file_hashes
elif [[ "$HASH_CHOICE" == "2" ]]; then
      echo "Available paths:"
      for i in "${!PATHS[@]}"; do
         echo "$((i+1))) ${PATHS[i]}"
      done
      read -p "Enter the number of the path you want to hash: " SELECTED_INDEX
      if (( SELECTED_INDEX >= 1 && SELECTED_INDEX <= ${#PATHS[@]} )); then
         SELECTED_PATH="${PATHS[SELECTED_INDEX-1]}"
         echo "Hashing $SELECTED_PATH..."
         grep -v "^$SELECTED_PATH|" "$HASH_FILE" > /tmp/temp_hashes && mv /tmp/temp_hashes "$HASH_FILE"   # gets rid of old hash of the selected path
         save_file_hashes $SELECTED_PATH
      else
         echo "Invalid selection. Skipping hashing..."
      fi
elif [[ "$HASH_CHOICE" == "3" ]]; then
   echo "Skipping hashing..."         
elif [[ ! -s "$HASH_FILE" ]]; then
    echo "Generating initial file hash records."
    save_file_hashes
fi

echo "Running file integrity scan in the background."
# Loop to periodically check integrity
while true; do
    compare_hashes
    sleep 45  # Check every 45 seconds
done &
