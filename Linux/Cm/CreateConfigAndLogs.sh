#!/bin/bash

# Define the config and log files for the project
CONFIG_FILES=(
    "./fs.config"
    "./serviceup.config"
    "./maliciouskeys.config"
    "./maliciousdir.config"
    "./backup.config"
)

LOG_FILES=(
    "/var/log/integrity_monitor.log"
    "/var/log/service_interrupt.log"
    "/var/log/malicious_keys.log"
)

# Define the sub-scripts that need to be made executable
SCRIPTS=(
    "./IntegrityCheck.sh"
    "./ServiceManager.sh"
    "./KeySearch.sh"
    "./BackupHandler.sh"
    "./ConfigManager.sh"
    "./CustomManager.sh"
)

# Malicious keywords content
MALICIOUS_KEYWORDS="php=fsockopen,stream_socket_client,curl,socket_create,shell_exec,exec,system,popen,backticks
python=socket,requests,ftplib,asyncio,os.system,subprocess.run,subprocess.call,subprocess.Popen
c=socket,send,recv,sendto,recvfrom,bind,listen,system,popen,execvp,fork
cpp=socket,send,recv,bind,listen,select,system,popen,exec,fork
java=Socket,ServerSocket,DatagramSocket,URLConnection,Runtime.getRuntime().exec,ProcessBuilder.start
javascript=net,http,dgram,tls,child_process.exec,child_process.spawn,child_process.fork
go=net.Dial,net.Listen,http.Get,http.Post,exec.Command,os/exec
ruby=Net::HTTP,Net::FTP,Socket,UDPSocket,system,exec,IO.popen
bash=nc,curl,wget,ss,telnet,nmap,\$(command),command,exec,sh,bash -c
perl=IO::Socket,LWP::UserAgent,Net::FTP,Net::HTTP,system,exec,backticks
swift=URLSession,NWConnection,NWListener,Process,NSTask
rust=TcpStream,UdpSocket,Reqwest,hyper,std::process::Command"

# Function to create an empty file if it doesn't exist
create_file() {
    FILE=$1
    if [ ! -f "$FILE" ]; then
        touch "$FILE"
        echo "$FILE has been created."
    else
        echo "$FILE already exists."
    fi
}

# Function to set executable permissions for scripts
set_executable_permissions() {
    SCRIPT=$1
    if [ -f "$SCRIPT" ]; then
        chmod +x "$SCRIPT"
        echo "Executable permissions set for $SCRIPT."
    else
        echo "$SCRIPT does not exist."
    fi
}

# Function to populate maliciouskeys.config
create_maliciouskeys_config() {
    MALICIOUS_KEYS_FILE="./maliciouskeys.config"
    if [ ! -f "$MALICIOUS_KEYS_FILE" ]; then
        echo "$MALICIOUS_KEYWORDS" > "$MALICIOUS_KEYS_FILE"
        echo "maliciouskeys.config has been created and populated with predefined keywords."
    else
        echo "maliciouskeys.config already exists."
    fi
}

# Create .config files
echo "Creating .config files..."
for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
    create_file "$CONFIG_FILE"
done

# Create .log files
echo "Creating .log files..."
for LOG_FILE in "${LOG_FILES[@]}"; do
    create_file "$LOG_FILE"
done

# Set executable permissions for the sub-scripts
echo "Setting executable permissions for sub-scripts..."
for SCRIPT in "${SCRIPTS[@]}"; do
    set_executable_permissions "$SCRIPT"
done

# Create and populate maliciouskeys.config with predefined keywords
create_maliciouskeys_config

echo "All necessary .config, .log files have been created, and executable permissions have been set for sub-scripts."
