System Integrity and Service Management Script
Overview

This Python script provides system administrators with a suite of tools to monitor system integrity, manage services, create and restore backups, and detect malicious activity. It consists of several background tasks that ensure the system is running smoothly and securely. The script features:

    Integrity Check: Ensures specified paths are intact, non-empty, and immutable.
    Service Management: Monitors and restarts critical services.
    Backup & Restore: Creates backups of directories and restores them when needed.
    Malicious Keyword Search: Searches for known malicious keywords and patterns in system files and directories.
    Configuration Editing: Allows for easy editing of configuration files (not yet implemented).

This tool helps maintain the health and security of your system by continuously checking the integrity of files and services.
Features
1. Integrity Check

    Continuously monitors paths from a specified file (FS_FORMAT_PATH).
    Ensures paths exist and are immutable (set using chattr).
    Logs warnings when paths are empty or non-existent.
    Runs as a background task (every 10 seconds).

2. Service Manager

    Monitors services listed in a configuration file (SERVICEUP_FORMAT_PATH).
    Checks the status of each service using systemctl.
    Restarts any services that are down.
    Runs as a background task (every 10 seconds).

3. Backup & Restore

    Backup: Backs up files or directories to a specified destination, with a timestamp.
    Restore: Lists available backups and allows users to restore them from the backup file.
    Backup information is stored in BACKUP_FORMAT_PATH.

4. Malicious Keyword Search

    Searches for malicious keywords and suspicious patterns (e.g., exec(), subprocess.) in system files.
    Loads malicious keywords and directories from specified configuration files (MALICIOUSKEYS_FORMAT_PATH and MALICIOUSDIR_FORMAT_PATH).
    Logs any suspicious findings and prints them to the console.

5. Configuration Editing

    Placeholder for editing configuration files to update paths, services, keywords, etc. (not implemented yet).

Requirements

    Python 3.x
    Linux-based operating system (for systemctl and chattr commands)
    The following Python modules:
        os
        time
        re
        subprocess
        shutil
        threading
        logging
        datetime
