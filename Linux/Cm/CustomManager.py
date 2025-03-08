import os
import subprocess
import time
import shutil
import re
from datetime import datetime

# Config file paths
FS_CONFIG = "./fs.config"
SERVICE_CONFIG = "./serviceup.config"
MALICIOUS_KEYS_FILE = "./maliciouskeys.config"
MALICIOUS_DIRS_FILE = "./maliciousdir.config"
BACKUP_CONFIG_FILE = "./backup.config"
LOG_FILE = "/var/log/integrity_monitor.log"
SERVICE_LOG_FILE = "/var/log/service_interrupt.log"
MALICIOUS_LOG_FILE = "/var/log/malicious_keys.log"
BACKUP_LOG_FILE = "/var/log/backup.log"

# Function to log messages
def log(message, log_file):
    with open(log_file, "a") as file:
        file.write(message + "\n")
    print(message)

# 1. IntegrityCheck: Check files and directories for immutability
def check_immutable():
    with open(FS_CONFIG, "r") as config_file:
        for line in config_file:
            path = line.strip()
            if os.path.exists(path):
                if os.path.isdir(path):
                    # Check if directory is immutable
                    if 'i' not in subprocess.getoutput(f"lsattr -d {path}"):
                        subprocess.run(["chattr", "+i", path])
                        log(f"Warning - Directory {path} is not immutable, setting it to immutable.", LOG_FILE)
                elif os.path.isfile(path):
                    # Check if file is immutable
                    if 'i' not in subprocess.getoutput(f"lsattr {path}"):
                        subprocess.run(["chattr", "+i", path])
                        log(f"Warning - File {path} is not immutable, setting it to immutable.", LOG_FILE)

# 2. ServiceManager: Ensure services are running
def check_services():
    with open(SERVICE_CONFIG, "r") as config_file:
        for line in config_file:
            service = line.strip()
            if not is_service_active(service):
                restart_service(service)

def is_service_active(service):
    status = subprocess.getoutput(f"systemctl is-active --quiet {service}")
    return status == "active"

def restart_service(service):
    subprocess.run(["systemctl", "restart", service])
    log(f"Service {service} was down and has been restarted.", SERVICE_LOG_FILE)

# 3. KeySearch: Search for malicious keywords in files and directories
def load_malicious_keywords():
    malicious_keywords = {}
    with open(MALICIOUS_KEYS_FILE, "r") as file:
        for line in file:
            language, keywords = line.strip().split("=")
            malicious_keywords[language] = keywords.split()
    return malicious_keywords

def search_keywords():
    malicious_keywords = load_malicious_keywords()
    with open(MALICIOUS_DIRS_FILE, "r") as dirs_file:
        for line in dirs_file:
            directory = line.strip()
            if os.path.isdir(directory):
                for root, dirs, files in os.walk(directory):
                    for file in files:
                        check_file_for_malicious_keywords(os.path.join(root, file), malicious_keywords)

def check_file_for_malicious_keywords(file, malicious_keywords):
    try:
        with open(file, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
            for language, keywords in malicious_keywords.items():
                for keyword in keywords:
                    if re.search(rf"\b{re.escape(keyword)}\b", content):
                        log(f"Malicious keyword '{keyword}' found in file: {file}", MALICIOUS_LOG_FILE)
    except Exception as e:
        log(f"Error processing file {file}: {str(e)}", MALICIOUS_LOG_FILE)

# 4. BackupHandler: Handle backups and restores
def create_backup(source_dir, backup_dir):
    if not os.path.exists(source_dir):
        log(f"Source directory {source_dir} does not exist.", BACKUP_LOG_FILE)
        return

    if not os.path.exists(backup_dir):
        os.makedirs(backup_dir)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = os.path.join(backup_dir, f"backup_{timestamp}.tar.gz")
    shutil.make_archive(backup_file.replace(".tar.gz", ""), 'gztar', source_dir)

    log(f"Backup of {source_dir} created at {backup_file}", BACKUP_LOG_FILE)

def restore_backup(backup_file, restore_dir):
    if not os.path.exists(backup_file):
        log(f"Backup file {backup_file} does not exist.", BACKUP_LOG_FILE)
        return

    if not os.path.exists(restore_dir):
        os.makedirs(restore_dir)

    shutil.unpack_archive(backup_file, restore_dir)
    log(f"Restored backup from {backup_file} to {restore_dir}", BACKUP_LOG_FILE)

# 5. ConfigManager: Modify configuration files and restart services
def modify_config(file_path, action="view"):
    if action == "view":
        with open(file_path, "r") as file:
            for line in file:
                print(line.strip())
    elif action == "modify":
        with open(file_path, "r") as file:
            lines = file.readlines()

        print("Enter the line number to modify:")
        line_number = int(input()) - 1
        new_value = input("Enter the new value: ")

        lines[line_number] = new_value + "\n"

        with open(file_path, "w") as file:
            file.writelines(lines)

        print(f"Config file {file_path} modified.")

# Main menu to handle various tasks
def main_menu():
    while True:
        print("\nSelect an option:")
        print("1) Run Integrity Check")
        print("2) Monitor Services")
        print("3) Search for Malicious Keywords")
        print("4) Create a Backup")
        print("5) Restore a Backup")
        print("6) Modify Configurations")
        print("7) Exit")

        choice = input("Enter your choice (1-7): ")

        if choice == '1':
            check_immutable()
        elif choice == '2':
            check_services()
        elif choice == '3':
            search_keywords()
        elif choice == '4':
            source_dir = input("Enter source directory to back up: ")
            backup_dir = input("Enter backup directory: ")
            create_backup(source_dir, backup_dir)
        elif choice == '5':
            backup_file = input("Enter backup file to restore: ")
            restore_dir = input("Enter directory to restore to: ")
            restore_backup(backup_file, restore_dir)
        elif choice == '6':
            config_file = input("Enter config file path (fs.config, serviceup.config, etc.): ")
            action = input("Enter action (view/modify): ")
            modify_config(config_file, action)
        elif choice == '7':
            print("Exiting...")
            break
        else:
            print("Invalid choice, please try again.")

if __name__ == "__main__":
    main_menu()
