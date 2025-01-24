# PowerShell script for installing Splunk Universal Forwarder v9.1.1 on Windows Server 2019
# Ensure you run this script with Administrator privileges

# Variables
$SplunkVersion = "9.1.1"
$SplunkBuild = "64e843ea36b1"
$SplunkInstaller = "splunkforwarder-${SplunkVersion}-${SplunkBuild}-x64-release.msi"
$SplunkDownloadURL = "https://download.splunk.com/products/universalforwarder/releases/$SplunkVersion/windows/$SplunkInstaller"
$SplunkInstallDir = "C:\Program Files\SplunkUniversalForwarder"
$SplunkIndexerIP = "172.20.241.20"
$ReceiverPort = "9997"  # Default Splunk receiving port

# Download Splunk Universal Forwarder
Write-Host "Downloading Splunk Universal Forwarder installer..."
$InstallerPath = "${env:TEMP}\$SplunkInstaller"
Invoke-WebRequest -Uri $SplunkDownloadURL -OutFile $InstallerPath

# Install Splunk Universal Forwarder
Write-Host "Installing Splunk Universal Forwarder..."
Start-Process msiexec.exe -ArgumentList "/i $InstallerPath /quiet INSTALLDIR=\"$SplunkInstallDir\" AGREETOLICENSE=Yes" -Wait

# Configure Splunk Forwarder
Write-Host "Configuring Splunk Universal Forwarder..."
$SplunkBin = "${SplunkInstallDir}\bin\splunk.exe"

# Set up initial Splunk admin user if none exists
Write-Host "Checking for existing users..."
$SplunkUserSetup = "admin"
$SplunkPasswordSetup = "changeme"  # Replace with a secure password
Start-Process -FilePath $SplunkBin -ArgumentList "add user $SplunkUserSetup -password $SplunkPasswordSetup -role admin" -Wait

# Add the Splunk indexer as a forward server
Write-Host "Adding forward-server configuration..."
Start-Process -FilePath $SplunkBin -ArgumentList "add forward-server $SplunkIndexerIP:$ReceiverPort -auth $SplunkUserSetup:$SplunkPasswordSetup" -Wait

# Add basic monitors
Write-Host "Setting up basic monitors..."
Start-Process -FilePath $SplunkBin -ArgumentList "add monitor C:\\Windows\\System32\\LogFiles\\W3SVC1 -sourcetype iis" -Wait
Start-Process -FilePath $SplunkBin -ArgumentList "add monitor C:\\Windows\\Logs -sourcetype windows_log" -Wait
Start-Process -FilePath $SplunkBin -ArgumentList "add monitor C:\\ProgramData\\SplunkForwarder\\var\\log\\splunk -sourcetype splunkd_log" -Wait

# Enable Splunk service to start on boot
Write-Host "Enabling Splunk service to start on boot..."
Start-Process -FilePath $SplunkBin -ArgumentList "enable boot-start" -Wait

# Start Splunk Forwarder service
Write-Host "Starting Splunk Universal Forwarder service..."
Start-Service -Name SplunkForwarder

# Clean up installer
Write-Host "Cleaning up..."
Remove-Item -Path $InstallerPath -Force

Write-Host "Splunk Universal Forwarder v$SplunkVersion installation and configuration complete!"
