import os
import time
import json
import subprocess
import logging
from datetime import datetime
import shutil
import re
import threading

# Paths
CONFIG_PATH = './cm.config'
FS_FORMAT_PATH = './fs.format'
SERVICEUP_FORMAT_PATH = './serviceup.format'
MALICIOUSKEYS_FORMAT_PATH = './maliciouskeys.format'
MALICIOUSDIR_FORMAT_PATH = './maliciousdir.format'
BACKUP_FORMAT_PATH = './backup.format'
LOG_PATH = '/var/log/'
INTEGRITY_LOG = os.path.join(LOG_PATH, 'integrity_monitor.log')
SERVICE_LOG = os.path.join(LOG_PATH, 'service_interrupt.log')
MALICIOUS_LOG = os.path.join(LOG_PATH, 'malicious_keys.log')
# Setup custom loggers
def setup_loggers():
    # Integrity Logger
    integrity_logger = logging.getLogger('integrity')
    integrity_logger.setLevel(logging.INFO)
    integrity_handler = logging.FileHandler(INTEGRITY_LOG)
    integrity_handler.setFormatter(logging.Formatter('%(asctime)s - %(message)s'))
    integrity_logger.addHandler(integrity_handler)

    # Service Logger
    service_logger = logging.getLogger('service')
    service_logger.setLevel(logging.INFO)
    service_handler = logging.FileHandler(SERVICE_LOG)
    service_handler.setFormatter(logging.Formatter('%(asctime)s - %(message)s'))
    service_logger.addHandler(service_handler)

    # Malicious Keywords Logger
    malicious_logger = logging.getLogger('malicious')
    malicious_logger.setLevel(logging.INFO)
    malicious_handler = logging.FileHandler(MALICIOUS_LOG)
    malicious_handler.setFormatter(logging.Formatter('%(asctime)s - %(message)s'))
    malicious_logger.addHandler(malicious_handler)

    return integrity_logger, service_logger, malicious_logger


# Set up loggers at the start
integrity_logger, service_logger, malicious_logger = setup_loggers()


# Function to log integrity events
def log_integrity_event(message):
    integrity_logger.info(message)


# Function to log service events
def log_service_event(message):
    service_logger.info(message)


# Function to log malicious events
def log_malicious_event(message):
    malicious_logger.info(message)
keywords1 = {
    "Python": [
        "exec", "eval", "os.system", "subprocess", "popen", "open('__import__')", 
        "os.popen", "eval('import')", "os.system('')", "sys.modules", "os.environ", 
        "imp.find_module", "subprocess.Popen"
    ],
    "PHP": [
        "eval", "exec", "passthru", "shell_exec", "system('')", "exec('')", "curl('')", 
        "fopen('')", "file_get_contents('')", "exec(base64_decode)", "system(base64_decode)", 
        "pcntl_exec", "eval(base64_decode)", "system(base64)", "proc_open"
    ],
    "Java": [
        "Runtime.getRuntime", "exec", "System.getProperty", 
        "exec(Class.forName('java.lang.Runtime').getRuntime().exec)", 
        "ProcessBuilder", "ProcessBuilder.start", "Runtime.getRuntime().exec"
    ],
    "JavaScript": [
        "eval", "execFunction", "setInterval", "setTimeout", "function()", "window.location", 
        "XMLHttpRequest", "eval('new Function')", "Function", "eval('return')", "setTimeout('')", 
        "location.replace"
    ],
    "Ruby": [
        "system", "exec", "IO.popen", "eval", "open('|')", "Process.spawn", "system('')", 
        "`backticks`", "IO.popen('')", "Thread.new", "`command`"
    ],
    "C": [
        "system", "popen", "execve", "system()", "fork()", "ptrace()", "freopen()", "execvp()", 
        "execv()", "execle()", "mmap()", "setuid()", "setgid()", "ptrace()", "fcntl()", "socket()"
    ],
    "C++": [
        "system", "popen", "execve", "system()", "fork()", "ptrace()", "execvp()", "execv()", 
        "execle()", "mmap()", "setuid()", "setgid()", "ptrace()", "fcntl()", "socket()", "virtual()"
    ],
    "Perl": [
        "eval", "exec", "system", "fork", "open('‘|’')", "backticks", "system(qx)", "exec(qx)", 
        "open('')", "spawn"
    ],
    "Bash": [
        "eval", "exec", "system()", "$(())", "`command`", "/bin/bash", "/bin/sh", "/usr/bin/python", 
        "/usr/bin/perl", "/usr/bin/ruby", "trap()"
    ],
    "PowerShell": [
        "Invoke-Expression", "iex", "System.Diagnostics.ProcessStartInfo", "System.IO.StreamReader", 
        "Add-Type", "System.IO.FileSystemWatcher"
    ],
    "SQL": [
        "UNION", "SELECT", "SELECT", "FROM", "WHERE", "LIKE", "OR", "INSERT INTO", "DROP", "DELETE", 
        "UPDATE", "CREATE", "TRUNCATE", "HAVING", "COUNT", "INFORMATION_SCHEMA", "REPLACE INTO", 
        "JOIN", "WITH"
    ],
    "XML": [
        "<!ENTITY % xxe SYSTEM 'file:///etc/passwd'>", "<!DOCTYPE foo [", "<!ELEMENT foo ANY>", 
        "<!ENTITY % dtd SYSTEM 'file:///etc/passwd'>", "%dtd;", "]>", "<![CDATA[", "<![INCLUDE]]>"
    ],
    "SSH": [
        "ssh -R", "ssh -L", "ssh -D", "/usr/bin/ssh", "/usr/bin/sshd", "ssh_keygen -t rsa", "ssh-agent", 
        "ssh-add"
    ],
    "FTP": [
        "USER", "PASS", "STOR", "RETR", "LIST", "CWD", "TYPE", "PASV", "PORT", "QUIT", "SITE", "AUTH", 
        "FTP://"
    ],
    "WebShell": [
        "webshell", "php", "shell.php", "c99.php", "r57.php", "cmd.php", "exec.php", "hacker.php", 
        "wso.php", "shell.ashx"
    ],
    "Wget": [
        "curl", "wget", "exec('curl')", "exec('wget')", "file_get_contents('http://')", "fopen('http://')", 
        "file_get_contents('ftp://')", "fsockopen()"
    ],
    "HTTP": [
        "nc -e /bin/bash", "curl -X POST", "curl -X GET", "curl -X PUT", "curl -X DELETE", 
        "curl -I", "curl -d", "wget --no-check-certificate"
    ],
    "Linux": [
        "chmod 777 /etc/passwd", "chmod 777 /etc/shadow", "chmod 777 /root/.bashrc", 
        "chmod +x /usr/local/bin/evil", "chmod 777 /bin/bash"
    ],
    "Apache": [
        "mod_cgi", "mod_php", "mod_rewrite", "/etc/httpd.conf", "/etc/apache2/httpd.conf", ".htaccess", 
        "/var/www/html/.htaccess", ".htpasswd"
    ],
    "Nginx": [
        "nginx.conf", "php-fpm.conf", "fastcgi_pass", "/usr/share/nginx/html/", "/etc/nginx/nginx.conf", 
        "server_name"
    ],
    "MySQL": [
        "SELECT", "FROM", "INFORMATION_SCHEMA", "user", "password", "database", "SHOW TABLES", 
        "SHOW COLUMNS FROM", "ALTER TABLE", "DROP COLUMN", "CREATE DATABASE", "GRANT", "REVOKE"
    ],
    "MongoDB": [
        "db.eval", "db.eval('db.system.js.find()')", "db.getCollectionNames()", "db.auth", 
        "db.createCollection", "db.dropCollection"
    ],
    "Redis": [
        "CONFIG SET", "CONFIG REWRITE", "FLUSHALL", "FLUSHDB", "CONFIG GET", "CONFIG SET", "CONFIG REWRITE", 
        "KEYS *", "SYSTEM", "eval"
    ],
    "Windows": [
        "net user", "net localgroup", "netstat", "cmd.exe", "powershell.exe", "netsh", "netcat", 
        "net user admin /add", "net localgroup administrators"
    ],
    "Rootkit": [
        "kdump", "chroot", "ftrace", "udev", "script", "kidnap", "rootkit.linux", "rootkit.bash", 
        "rootkit.python", "rootkit.cpp"
    ],
    "Backdoor": [
        "reverse", "shell", "backdoor", "trojan", "RAT", "shell", "access", "ssh", "access"
    ],
    "Shellcode": [
        "0x90", "shellcode", "execve", "syscall", "ptrace", "mmap()", "ftrace()", "setuid()", "setgid()", 
        "sendfile()"
    ],
    "Base64": [
        "base64_decode", "system(base64_decode)", "base64", "shell_exec", "base64_decode", 
        "base64_decode(base64)", "sys.exit()", "base64 --decode"
    ],
    "XSS": [
        "<script>alert(1)</script>", "<img src='javascript:alert('XSS')'>", "<script>evil()</script>", 
        "onerror='alert('xss')'", "src='javascript:alert(1)'"
    ],
    "RCE": [
        "RCE", "reverse", "shell", "command", "injection", "system('curl')", "system('wget')", "system('bash')", 
        "php://filter/convert.base64-encode/resource"
    ],
    "LFI": [
        "include()", "require()", "include_once()", "require_once()", "file_get_contents()", "fopen()", "file()", 
        "readfile()", "readfile('php://input')"
    ],
    "RFI": [
        "include()", "require()", "file_get_contents('http://')", "fopen('http://')", "file_get_contents('ftp://')", 
        "include('php://input')", "include('http://')"
    ],
    "Privilege Escalation": [
        "chmod +s", "sudoers", "sudo visudo", "/etc/sudoers", "visudo", "root", "password", "escalation", "setuid", 
        "setgid", "/etc/passwd", "/etc/shadow"
    ],
    "File Inclusion": [
        "include()", "require()", "include_once()", "require_once()", "file_get_contents()", "fopen()", "file()", 
        "readfile()", "php://filter/convert.base64"
    ],
    "Command Injection": [
        "system()", "exec()", "popen()", "execve()", "backticks", "subprocess.Popen()"
    ],
    "Buffer Overflow": [
        "malloc()", "strcpy()", "strcat()", "gets()", "memcpy()", "system()", "execve()", "vulnerable", "buffer", 
        "printf()", "setbuf()", "fcntl()"
    ],
    "Deserialization": [
        "unserialize()", "unserialize()", "json_decode()", "eval()", "exec()", "proc_open()", "base64_decode()"
    ]
}


# Setup basic logging configuration
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')

# Ensure format and log files exist
def check_and_create_files():
    # Check format files
    for file_path in [FS_FORMAT_PATH, SERVICEUP_FORMAT_PATH, MALICIOUSKEYS_FORMAT_PATH, MALICIOUSDIR_FORMAT_PATH, BACKUP_FORMAT_PATH]:
        if not os.path.exists(file_path):
            with open(file_path, 'w') as f:
                logging.info(f"Created missing format file: {file_path}")
        else:
            logging.info(f"Format file {file_path} already exists.")

    # Check log files
    for log_file in [INTEGRITY_LOG, SERVICE_LOG, MALICIOUS_LOG]:
        if not os.path.exists(log_file):
            with open(log_file, 'w') as f:
                logging.info(f"Created missing log file: {log_file}")
        else:
            logging.info(f"Log file {log_file} already exists.")

# Function to restart the background tasks
def restart_background_tasks():
    logging.info("Restarting background tasks...")
    threading.Thread(target=integrity_check, daemon=True).start()
    threading.Thread(target=service_manager, daemon=True).start()

# Function to edit configurations
def edit_configurations():
    while True:
        print("\n---- Edit Configurations ----")
        print("1. Edit fs.format")
        print("2. Edit serviceup.format")
        print("3. Edit maliciouskeys.format")
        print("4. Edit maliciousdir.format")
        print("5. Edit backup.format")
        print("6. Return to Main Menu")

        choice = input("Enter your choice: ")
        
        if choice == '1':
            file_to_edit = FS_FORMAT_PATH
        elif choice == '2':
            file_to_edit = SERVICEUP_FORMAT_PATH
        elif choice == '3':
            file_to_edit = MALICIOUSKEYS_FORMAT_PATH
        elif choice == '4':
            file_to_edit = MALICIOUSDIR_FORMAT_PATH
        elif choice == '5':
            file_to_edit = BACKUP_FORMAT_PATH
        elif choice == '6':
            return  # Go back to the main menu
        else:
            print("Invalid choice! Please try again.")
            continue

        if os.path.exists(file_to_edit):
            print(f"Editing {file_to_edit}")
            with open(file_to_edit, 'r') as f:
                content = f.readlines()
                if content:
                    print("Current Content:")
                    for idx, line in enumerate(content, 1):
                        print(f"{idx}. {line.strip()}")
                else:
                    print("No content in the file.")

            # Provide the user with the options to add or delete entries
            print("\nOptions:")
            print("a. Add new entry")
            print("d. Delete specific entry")
            print("e. Edit existing entry")
            print("r. Return to previous menu")

            option = input("Enter your choice: ").strip().lower()

            if option == 'a':
                new_content = input("Enter the new content to add: ").strip()
                if new_content not in content:
                    with open(file_to_edit, 'a') as f:
                        f.write(new_content + '\n')  # Ensure a new line is added
                        logging.info(f"Added new entry to {file_to_edit}: {new_content}")
                    print(f"Added new entry: {new_content}")
                    restart_background_tasks()  # Restart background tasks after modification
                else:
                    print(f"Entry '{new_content}' already exists in {file_to_edit}.")

            elif option == 'd':
                try:
                    del_index = int(input(f"Enter the line number to delete (1-{len(content)}): "))
                    if 1 <= del_index <= len(content):
                        deleted_line = content.pop(del_index - 1)
                        with open(file_to_edit, 'w') as f:
                            f.writelines(content)
                        logging.info(f"Deleted entry from {file_to_edit}: {deleted_line.strip()}")
                        print(f"Deleted entry: {deleted_line.strip()}")
                        restart_background_tasks()  # Restart background tasks after modification
                    else:
                        print(f"Invalid line number! Please enter a valid number between 1 and {len(content)}.")
                except ValueError:
                    print("Invalid input. Please enter a valid line number.")

            elif option == 'e':
                try:
                    edit_index = int(input(f"Enter the line number to edit (1-{len(content)}): "))
                    if 1 <= edit_index <= len(content):
                        print(f"Current content at line {edit_index}: {content[edit_index - 1].strip()}")
                        new_entry = input("Enter the new content: ").strip()
                        content[edit_index - 1] = new_entry + '\n'
                        with open(file_to_edit, 'w') as f:
                            f.writelines(content)
                        logging.info(f"Updated entry in {file_to_edit}: {new_entry}")
                        print(f"Updated entry: {new_entry}")
                        restart_background_tasks()  # Restart background tasks after modification
                    else:
                        print(f"Invalid line number! Please enter a valid number between 1 and {len(content)}.")
                except ValueError:
                    print("Invalid input. Please enter a valid line number.")

            elif option == 'r':
                continue  # Return to the menu
            else:
                print("Invalid choice! Please try again.")
        else:
            print(f"{file_to_edit} does not exist.")

# Function to perform integrity check
def integrity_check():
    while True:
        with open(FS_FORMAT_PATH, 'r') as f:
            for line in f:
                path = line.strip()
                
                if path:
                    if os.path.exists(path):
                        if is_empty_path(path):
                            logging.warning(f"Path {path} is empty.")
                        elif os.path.isdir(path):
                            
                            if not check_immutable(path,'dir'):
                                set_immutable(path)
                                log_integrity_event(f"Integrity check: The path {path} is not immutable.")
                        elif os.path.isfile(path):
                            if not check_immutable(path,'file'):
                                log_integrity_event(f"Integrity check: The path {path} is not immutable.")
                                set_immutable(path)
                    else:
                        logging.warning(f"Path {path} does not exist.")
        time.sleep(10)  # Check every 10 seconds

# Function to check and restart services
def service_manager():
    while True:
        with open(SERVICEUP_FORMAT_PATH, 'r') as f:
            for line in f:
                service = line.strip()
                if service:
                    try:
                        result = subprocess.run(['systemctl', 'is-active', '--quiet', service])
                        if result.returncode != 0:  # If service is down
                            logging.warning(f"Service {service} is down. Restarting...")
                            subprocess.run(['systemctl', 'restart', service], check=True)
                            log_service_event(f"Service {service} is down. Restarting...")
                            logging.info(f"Service {service} was restarted.")
                    except subprocess.CalledProcessError:
                        logging.error(f"Failed to check or restart service {service}.")
        time.sleep(10)  # Check every 10 seconds

# Function to check if the file or directory is empty
def is_empty_path(path):
    return not os.path.exists(path) or (os.path.isdir(path) and len(os.listdir(path)) == 0)

# Function to make file or directory immutable
def set_immutable(path):
    try:
        subprocess.run(['chattr', '+i', path], check=True)
        logging.info(f"Set immutable on {path}")
    except subprocess.CalledProcessError:
        logging.error(f"Failed to set immutable on {path}")

# Function to check if the file or directory is immutable
def check_immutable(path,ty):
    try:
        if ty == 'dir':
            result = subprocess.run(['lsattr','-d', path], capture_output=True, text=True)
        else:
            result = subprocess.run(['lsattr', path], capture_output=True, text=True)
        #print(result)
        if 'i' in result.stdout:
            return True
        else:
            return False
    except subprocess.CalledProcessError:
        logging.error(f"Failed to check immutable attribute for {path}")
        return False

# Function to create backup
def create_backup():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    with open(BACKUP_FORMAT_PATH, 'a') as f:
        src_path = input("Enter the source path to backup: ")
        dest_path = input("Enter the destination path to store the backup: ")
        if os.path.exists(src_path):
            if is_empty_path(src_path):
                logging.warning(f"Source path {src_path} is empty.")
            else:
                backup_name = f"backup_{os.path.basename(src_path)}_{timestamp}.tar.gz"
                backup_file = os.path.join(dest_path, backup_name)
                try:
                    shutil.make_archive(backup_file, 'gztar', src_path)
                    f.write(f"{timestamp}|{src_path}|{backup_file}\n")
                    logging.info(f"Backup created: {backup_file}")
                except Exception as e:
                    logging.error(f"Failed to create backup for {src_path}: {e}")
        else:
            logging.warning(f"Source path {src_path} does not exist.")

# Function to restore backup
def restore_backup():
    with open(BACKUP_FORMAT_PATH, 'r') as f:
        backups = f.readlines()
    if backups:
        print("Available backups:")
        for idx, backup in enumerate(backups, 1):
            print(f"{idx}. {backup.strip()}")
        choice = input("Enter the backup number to restore: ")
        try:
            backup_entry = backups[int(choice) - 1].strip().split('|')
            backup_file = backup_entry[2]
            restore_path = backup_entry[1]
            if os.path.exists(backup_file):
                shutil.unpack_archive(backup_file, restore_path)
                logging.info(f"Backup restored from {backup_file} to {restore_path}")
            else:
                logging.warning(f"Backup file {backup_file} does not exist.")
        except (ValueError, IndexError):
            logging.error("Invalid choice.")
    else:
        logging.warning("No backups available.")

# Function to search for malicious keywords in files
def key_search():
    malicious_keywords = keywords1
    malicious_dirs = load_malicious_dirs()
    found_keywords = {}
    
    for dir_path in malicious_dirs:
        if os.path.exists(dir_path):
            if os.path.isdir(dir_path):  # Check if it's a directory
                for root, _, files in os.walk(dir_path):
                    for file in files:
                        file_path = os.path.join(root, file)
                        search_in_file(file_path, malicious_keywords, found_keywords)
            elif os.path.isfile(dir_path):  # If it's a file
                search_in_file(dir_path, malicious_keywords, found_keywords)

    if found_keywords:
        print("Malicious keywords found in the following files:")
        for file, keywords in found_keywords.items():
            print(f"File: {file}, Keywords: {', '.join(keywords)}")
            log_malicious_event(f"File: {file}, Keywords: {', '.join(keywords)}")
    else:
        print("No malicious keywords found.")

# Function to search within a file for malicious keywords
def search_in_file(file_path, malicious_keywords, found_keywords):
    try:
        with open(file_path, 'r', errors='ignore') as f:
            content = f.read()
            for language, keywords in malicious_keywords.items():
                for keyword in keywords:
                    # Search for the exact word as a whole word in the content
                    if re.search(r'\b' + re.escape(keyword) + r'\b', content):
                        if file_path not in found_keywords:
                            found_keywords[file_path] = []
                        found_keywords[file_path].append(f"{language} keyword: {keyword}")
            
            # Additional checks for common malicious patterns
            if re.search(r'\bexec\(', content) or re.search(r'\bsubprocess\.', content):
                if file_path not in found_keywords:
                    found_keywords[file_path] = []
                found_keywords[file_path].append("Suspicious function calls detected")
            if re.search(r'\bimport\srequests\b', content):
                if file_path not in found_keywords:
                    found_keywords[file_path] = []
                found_keywords[file_path].append("Requests library usage detected")

    except Exception as e:
        logging.error(f"Failed to read {file_path}: {e}")

# Function to load malicious keywords
def load_malicious_keywords():
    try:
        with open(MALICIOUSKEYS_FORMAT_PATH, 'r') as f:
            return set(i.strip(' ') for i in [line.strip() for line in f.readlines() if line.strip()])
    except FileNotFoundError:
        return []

# Function to load malicious directories
def load_malicious_dirs():
    try:
        with open(MALICIOUSDIR_FORMAT_PATH, 'r') as f:
            return [line.strip() for line in f.readlines()]
    except FileNotFoundError:
        return []

# Main menu
def menu():
    check_and_create_files()

    while True:
        print("\n---- Main Menu ----")
        print("1. Run Integrity Check")
        print("2. Run Service Manager")
        print("3. Create Backup")
        print("4. Restore Backup")
        print("5. Edit Configurations")
        print("6. Search for Malicious Keywords")
        print("7. Exit")
        
        choice = input("Enter your choice: ")
        
        if choice == '1':
            print("Running Integrity Check in the background...")
            threading.Thread(target=integrity_check, daemon=True).start()
        
        elif choice == '2':
            print("Running Service Manager in the background...")
            threading.Thread(target=service_manager, daemon=True).start()
        
        elif choice == '3':
            print("Creating Backup...")
            create_backup()
        
        elif choice == '4':
            print("Restoring Backup...")
            restore_backup()
        
        elif choice == '5':
            print("Editing Configurations...")
            edit_configurations()  # Call the configuration editing function
        
        elif choice == '6':
            print("Searching for Malicious Keywords...")
            key_search()
        
        elif choice == '7':
            print("Exiting...")
            break
        
        else:
            print("Invalid choice! Please try again.")

# Main function
def main():
    menu()

if __name__ == "__main__":
    main()
