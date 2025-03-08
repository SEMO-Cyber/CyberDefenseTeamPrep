import os
import time
import json
import subprocess
import logging
from datetime import datetime
import shutil
import re

# Config and Log paths
CONFIG_PATH = './cm.config'
LOG_PATH = '/var/log/'
INTEGRITY_LOG = os.path.join(LOG_PATH, 'integrity_monitor.log')
SERVICE_LOG = os.path.join(LOG_PATH, 'service_interrupt.log')
MALICIOUS_LOG = os.path.join(LOG_PATH, 'malicious_keys.log')

# Loading the config
def load_config():
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as config_file:
            return json.load(config_file)
    else:
        print("Config file does not exist!")
        exit(1)

# Setup basic logging configuration
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')

# Function to make file or directory immutable
def set_immutable(path):
    try:
        subprocess.run(['chattr', '+i', path], check=True)
        logging.info(f"Set immutable on {path}")
    except subprocess.CalledProcessError:
        logging.error(f"Failed to set immutable on {path}")

# Function to check for immutable files/directories
def integrity_check(config):
    fs_config = config.get('fs_config', [])
    while True:
        for path in fs_config:
            if os.path.exists(path):
                if os.path.isdir(path):
                    set_immutable(path)
                elif os.path.isfile(path):
                    set_immutable(path)
                else:
                    logging.warning(f"Path {path} does not exist or is unsupported.")
            else:
                logging.warning(f"Path {path} does not exist.")
        time.sleep(10)  # Check every 10 seconds

# Function to check and restart services
def service_manager(config):
    service_config = config.get('serviceup_config', [])
    while True:
        for service in service_config:
            try:
                result = subprocess.run(['systemctl', 'is-active', '--quiet', service])
                if result.returncode != 0:
                    logging.warning(f"Service {service} is down. Restarting...")
                    subprocess.run(['systemctl', 'restart', service], check=True)
                    logging.info(f"Service {service} was restarted.")
            except subprocess.CalledProcessError:
                logging.error(f"Failed to restart service {service}.")
        time.sleep(10)  # Check every 10 seconds

# Function to create backups
def create_backup(config):
    backup_config = config.get('backup_config', [])
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    for entry in backup_config:
        src_path, dest_path = entry['src'], entry['dest']
        if os.path.exists(src_path):
            backup_name = f"backup_{os.path.basename(src_path)}_{timestamp}.tar.gz"
            backup_file = os.path.join(dest_path, backup_name)
            try:
                shutil.make_archive(backup_file, 'gztar', src_path)
                logging.info(f"Backup created: {backup_file}")
            except Exception as e:
                logging.error(f"Failed to create backup for {src_path}: {e}")
        else:
            logging.warning(f"Source path {src_path} does not exist.")

# Function to restore a backup
def restore_backup(backup_file, restore_path):
    if os.path.exists(backup_file):
        try:
            shutil.unpack_archive(backup_file, restore_path)
            logging.info(f"Backup restored from {backup_file} to {restore_path}")
        except Exception as e:
            logging.error(f"Failed to restore backup: {e}")
    else:
        logging.warning(f"Backup file {backup_file} does not exist.")

# Function to modify config files
def edit_config(config, section, new_data):
    if section in config:
        config[section] = new_data
        with open(CONFIG_PATH, 'w') as config_file:
            json.dump(config, config_file, indent=4)
        logging.info(f"Updated {section} in config.")
    else:
        logging.warning(f"Section {section} not found in config.")

# Function to add a service to the service config
def add_service(config, service_name):
    if 'serviceup_config' not in config:
        config['serviceup_config'] = []
    if service_name not in config['serviceup_config']:
        config['serviceup_config'].append(service_name)
        with open(CONFIG_PATH, 'w') as config_file:
            json.dump(config, config_file, indent=4)
        logging.info(f"Added service {service_name} to serviceup_config.")

# Function to search for malicious keywords in the files
def key_search(config):
    malicious_keys = config.get('malicious_keys', {})
    malicious_dirs = config.get('malicious_dirs', [])
    
    found_keywords = {}

    for dir_path in malicious_dirs:
        if os.path.exists(dir_path):
            for root, dirs, files in os.walk(dir_path):
                for file in files:
                    file_path = os.path.join(root, file)
                    try:
                        with open(file_path, 'r') as f:
                            content = f.read()
                            for language, keywords in malicious_keys.items():
                                for keyword in keywords:
                                    if re.search(r'\b' + re.escape(keyword) + r'\b', content):
                                        if file_path not in found_keywords:
                                            found_keywords[file_path] = []
                                        found_keywords[file_path].append(f"Keyword: {keyword}, Language: {language}")
                    except Exception as e:
                        logging.error(f"Error reading file {file_path}: {e}")

    if found_keywords:
        for file, info in found_keywords.items():
            for entry in info:
                logging.warning(f"Malicious keyword detected in {file}: {entry}")
        with open(MALICIOUS_LOG, 'a') as log_file:
            for file, info in found_keywords.items():
                for entry in info:
                    log_file.write(f"{datetime.now()} - {file} - {entry}\n")
        logging.info(f"Found {len(found_keywords)} malicious keyword entries.")
    else:
        logging.info("No malicious keywords found.")

# Main function
def main():
    config = load_config()

    # Start IntegrityCheck, ServiceManager and KeySearch in background
    import threading

    integrity_thread = threading.Thread(target=integrity_check, args=(config,))
    service_thread = threading.Thread(target=service_manager, args=(config,))
    keysearch_thread = threading.Thread(target=key_search, args=(config,))

    integrity_thread.daemon = True
    service_thread.daemon = True
    keysearch_thread.daemon = True

    integrity_thread.start()
    service_thread.start()
    keysearch_thread.start()

    # Optionally handle backup creation and restoration
    create_backup(config)
    # For restore, provide the backup filename and restore path
    # restore_backup('/path/to/backup.tar.gz', '/restore/path')

    # Example of editing config
    # edit_config(config, 'serviceup_config', ['nginx', 'apache2'])

    # Allow threads to run
    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
