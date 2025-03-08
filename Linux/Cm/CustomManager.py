import os
import time
import subprocess
import logging
import threading
from datetime import datetime

# Set up logging for each process
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger(__name__)

# Define the paths for the config files and log files
FS_CONFIG_FILE = './fs.config'
SERVICEUP_CONFIG_FILE = './serviceup.config'
MALICIOUSKEYS_CONFIG_FILE = './maliciouskeys.config'
MALICIOUSDIR_CONFIG_FILE = './maliciousdir.config'
BACKUP_CONFIG_FILE = './backup.config'

INTEGRITY_LOG_FILE = '/var/log/integrity_monitor.log'
SERVICE_INTERRUPT_LOG_FILE = '/var/log/service_interrupt.log'
MALICIOUS_KEYS_LOG_FILE = '/var/log/malicious_keys.log'


# Function to make file/dir immutable
def make_immutable(path):
    if os.path.exists(path):
        try:
            if os.path.isdir(path):
                subprocess.run(["sudo", "chattr", "+i", path], check=True)
            elif os.path.isfile(path):
                subprocess.run(["sudo", "chattr", "+i", path], check=True)
            logger.info(f"Made {path} immutable.")
        except subprocess.CalledProcessError:
            logger.error(f"Failed to make {path} immutable.")
    else:
        logger.warning(f"Path {path} does not exist.")


# Function to make file/dir mutable
def make_mutable(path):
    if os.path.exists(path):
        try:
            if os.path.isdir(path):
                subprocess.run(["sudo", "chattr", "-i", path], check=True)
            elif os.path.isfile(path):
                subprocess.run(["sudo", "chattr", "-i", path], check=True)
            logger.info(f"Made {path} mutable.")
        except subprocess.CalledProcessError:
            logger.error(f"Failed to make {path} mutable.")
    else:
        logger.warning(f"Path {path} does not exist.")


# Function to check and update file/dir immutability based on fs.config
def check_and_update_immutability():
    with open(FS_CONFIG_FILE, 'r') as file:
        paths = file.readlines()

    for path in paths:
        path = path.strip()
        if os.path.exists(path):
            if os.path.isdir(path) or os.path.isfile(path):
                result = subprocess.run(["lsattr", path], capture_output=True, text=True)
                if "i" not in result.stdout:
                    logger.warning(f"{path} is not immutable, making it immutable.")
                    make_immutable(path)
                    with open(INTEGRITY_LOG_FILE, 'a') as log_file:
                        log_file.write(f"{datetime.now()}: {path} was not immutable, made it immutable.\n")
        else:
            logger.warning(f"Path {path} does not exist.")


# Function to check service status and restart if down
def check_and_restart_services():
    with open(SERVICEUP_CONFIG_FILE, 'r') as file:
        services = file.readlines()

    for service in services:
        service = service.strip()
        try:
            result = subprocess.run(["systemctl", "is-active", "--quiet", service])
            if result.returncode != 0:
                logger.warning(f"Service {service} is down, restarting...")
                subprocess.run(["sudo", "systemctl", "restart", service], check=True)
                with open(SERVICE_INTERRUPT_LOG_FILE, 'a') as log_file:
                    log_file.write(f"{datetime.now()}: Service {service} was down and restarted.\n")
        except subprocess.CalledProcessError:
            logger.error(f"Error checking or restarting service {service}.")


# Function to search for malicious keywords in files and directories
def search_malicious_keywords():
    with open(MALICIOUSKEYS_CONFIG_FILE, 'r') as file:
        keywords_data = file.readlines()

    with open(MALICIOUSDIR_CONFIG_FILE, 'r') as file:
        dirs_to_search = file.readlines()

    for dir_path in dirs_to_search:
        dir_path = dir_path.strip()
        for keyword_line in keywords_data:
            keyword_line = keyword_line.strip()
            language, keywords = keyword_line.split("=")
            keywords_list = keywords.split()

            for root, dirs, files in os.walk(dir_path):
                for file in files:
                    file_path = os.path.join(root, file)
                    with open(file_path, 'r', errors='ignore') as f:
                        lines = f.readlines()
                        for i, line in enumerate(lines):
                            for keyword in keywords_list:
                                if keyword in line:
                                    logger.warning(f"Found malicious keyword '{keyword}' in {file_path} at line {i+1}.")
                                    with open(MALICIOUS_KEYS_LOG_FILE, 'a') as log_file:
                                        log_file.write(f"{datetime.now()}: Found '{keyword}' in {file_path} at line {i+1}.\n")


# Function to create a backup
def create_backup():
    source_dir = input("Enter the source directory to back up: ")
    destination_dir = input("Enter the destination directory to save the backup: ")

    if os.path.exists(source_dir):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_filename = f"backup_{timestamp}.tar.gz"
        backup_path = os.path.join(destination_dir, backup_filename)

        subprocess.run(["tar", "-czf", backup_path, source_dir], check=True)
        logger.info(f"Backup created: {backup_path}")

        with open(BACKUP_CONFIG_FILE, 'a') as file:
            file.write(f"{timestamp}|{source_dir}|{backup_path}\n")
    else:
        logger.error(f"Source directory {source_dir} does not exist.")


# Function to restore a backup
def restore_backup():
    with open(BACKUP_CONFIG_FILE, 'r') as file:
        backups = file.readlines()

    print("Available backups:")
    for i, backup in enumerate(backups):
        print(f"{i+1}. {backup.strip()}")

    backup_choice = int(input("Select a backup to restore (enter the number): "))
    backup_info = backups[backup_choice - 1].strip()
    timestamp, source_dir, backup_path = backup_info.split("|")

    if os.path.exists(backup_path):
        subprocess.run(["tar", "-xzf", backup_path, "-C", source_dir], check=True)
        logger.info(f"Backup restored: {backup_path}")
    else:
        logger.error(f"Backup file {backup_path} does not exist.")


# Function to show a simple menu
def show_menu():
    while True:
        print("\n--- Custom Manager ---")
        print("1. Integrity Check")
        print("2. Service Manager")
        print("3. Key Search")
        print("4. Backup Handler")
        print("5. Exit")
        choice = input("Select an option: ")

        if choice == "1":
            # Start IntegrityCheck in background
            integrity_thread = threading.Thread(target=check_and_update_immutability, daemon=True)
            integrity_thread.start()
        elif choice == "2":
            # Start ServiceManager in background
            service_thread = threading.Thread(target=check_and_restart_services, daemon=True)
            service_thread.start()
        elif choice == "3":
            search_malicious_keywords()
        elif choice == "4":
            backup_option = input("Select an option:\n1. Create Backup\n2. Restore Backup\n")
            if backup_option == "1":
                create_backup()
            elif backup_option == "2":
                restore_backup()
        elif choice == "5":
            break
        else:
            print("Invalid option, please try again.")


if __name__ == "__main__":
    show_menu()
