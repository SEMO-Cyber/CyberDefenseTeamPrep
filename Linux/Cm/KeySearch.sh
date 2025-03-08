#!/bin/bash

# Load config
MALICIOUS_KEYS_CONFIG="./maliciouskeys.config"
MALICIOUS_DIRS_CONFIG="./maliciousdir.config"
LOG_FILE="/var/log/malicious_keys.log"

# Function to search for malicious keywords
search_keywords() {
    keyword_count=0  # Initialize keyword count
    while read -r dir; do
        if [ -d "$dir" ]; then
            for keyword in $(grep -oP "Language=\K.*" "$MALICIOUS_KEYS_CONFIG"); do
                result=$(grep -rni "$keyword" "$dir")
                if [ ! -z "$result" ]; then
                    while IFS= read -r line; do
                        filename=$(echo $line | cut -d: -f1)
                        lineno=$(echo $line | cut -d: -f2)
                        column=$(echo $line | cut -d: -f3)
                        echo "$(date): Warning - Malicious keyword '$keyword' found in $filename at line $lineno, column $column"  # Console warning
                        echo "$(date): Malicious keyword '$keyword' found in $filename at line $lineno, column $column" >> "$LOG_FILE"
                    done <<< "$result"
                    keyword_count=$((keyword_count + 1))  # Increment the counter for each malicious keyword found
                fi
            done
        else
            echo "$(date): Warning - Directory $dir does not exist."  # Console warning
            echo "$(date): Directory $dir does not exist." >> "$LOG_FILE"
        fi
    done < "$MALICIOUS_DIRS_CONFIG"

    # Print the warning with count of keywords found
    if [ "$keyword_count" -gt 0 ]; then
        echo "$(date): Warning - Found $keyword_count new malicious keyword(s)."  # Console warning
        echo "$(date): Found $keyword_count new malicious keyword(s)." >> "$LOG_FILE"
    else
        echo "$(date): No new malicious keywords found."  # Console info
        echo "$(date): No new malicious keywords found." >> "$LOG_FILE"
    fi
}

# Run the search
search_keywords
