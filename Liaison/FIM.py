import hashlib 
import os 
import time 
import argparse 
import sys 
 
def calculate_hash(filepath): 
    """Calculates the SHA-256 hash of a file.""" 
    hasher = hashlib.sha256() 
    with open(filepath, 'rb') as file: 
        while True: 
            chunk = file.read(4096) 
            if not chunk: 
                break 
            hasher.update(chunk) 
    return hasher.hexdigest() 
 
def monitor_files(directory, interval=5): 
    """Monitors files in a directory for changes and new files. 
 
    Args: 
        directory: The directory to monitor. 
        interval: The time interval (in seconds) between checks. 
    """ 
 
    print(f"Monitoring directory: {directory}") 
    initial_hashes = {} 
 
    # Create the directory if it doesn't exist 
    if not os.path.exists(directory): 
        os.makedirs(directory) 
        print(f"Created directory: {directory}") 
 
    # Get initial hashes 
    for filename in os.listdir(directory): 
        filepath = os.path.join(directory, filename) 
        if os.path.isfile(filepath): 
            initial_hashes[filepath] = calculate_hash(filepath) 
            print(f"Initial hash for {filepath}: {initial_hashes[filepath]}") 
 
    print("Starting monitoring loop...") 
    while True: 
        time.sleep(interval) 
        print(f"Checking for changes in {directory}...") 
 
        current_files = set() 
        for filename in os.listdir(directory): 
            filepath = os.path.join(directory, filename) 
            if os.path.isfile(filepath): 
                current_files.add(filepath) 
                current_hash = calculate_hash(filepath) 
 
                if filepath not in initial_hashes: 
                    print(f"  New file detected: {filepath}") 
                    initial_hashes[filepath] = current_hash 
                elif initial_hashes[filepath] != current_hash: 
                    print(f"  File modified: {filepath}") 
                    initial_hashes[filepath] = current_hash 
 
        # Check for deleted files 
        deleted_files = set(initial_hashes.keys()) - current_files 
        for filepath in deleted_files: 
            print(f"  File deleted: {filepath}") 
            del initial_hashes[filepath] 
 
# --- Main Execution --- 
if __name__ == "__main__": 
    parser = argparse.ArgumentParser(description="File Integrity Monitor") 
    parser.add_argument("directory", help="Directory to monitor") 
    args = parser.parse_args() 
 
    directory_to_monitor = args.directory 
 
    if not os.path.isdir(directory_to_monitor): 
        print("Error: Invalid directory path provided.") 
        sys.exit(1) 
 
    # Monitor the files in the specified directory 
    monitor_files(directory_to_monitor, interval=5)