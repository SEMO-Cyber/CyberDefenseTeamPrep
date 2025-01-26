# PowerShell script for installing Splunk Universal Forwarder v9.1.1 on Windows Server 2019
# Ensure you run this script with Administrator privileges

# Variables
$SplunkVersion = "9.1.1"
$SplunkBuild = "64e843ea36b1"
$SplunkInstaller = "splunkforwarder-${SplunkVersion}-${SplunkBuild}-x64-release.msi"
$SplunkDownloadURL = "https://download.splunk.com/products/universalforwarder/releases/$SplunkVersion/windows/$SplunkInstaller"
$InstallerPath = "$env:TEMP\$SplunkInstaller"
$SplunkInstallDir = "C:\Program Files\SplunkUniversalForwarder"
$SplunkBin = "$SplunkInstallDir\bin\splunk.exe"
$SplunkIndexerIP = "<INDEXER_IP>"  # Replace with the IP of your Splunk indexer
$ReceiverPort = "9997"  # Default Splunk receiving port
$SplunkUserSetup = "admin"
$SplunkPasswordSetup = "changeme"  # Replace with a secure password

# Download Splunk Universal Forwarder
Write-Host "Downloading Splunk Universal Forwarder installer..."
Invoke-WebRequest -Uri $SplunkDownloadURL -OutFile $InstallerPath -UseBasicParsing

# Install Splunk Universal Forwarder
Write-Host "Installing Splunk Universal Forwarder..."
Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$InstallerPath`" /quiet INSTALLDIR=`"$SplunkInstallDir`" AGREETOLICENSE=Yes" -Wait

# Verify installation path
if (!(Test-Path -Path $SplunkBin)) {
    Write-Host "Splunk Universal Forwarder installation failed. Exiting." -ForegroundColor Red
    Exit 1
}

# Configure Splunk Forwarder
Write-Host "Configuring Splunk Universal Forwarder..."
Start-Process -FilePath $SplunkBin -ArgumentList @("add", "user", $SplunkUserSetup, "-password", $SplunkPasswordSetup, "-role", "admin") -NoNewWindow -Wait
Start-Process -FilePath $SplunkBin -ArgumentList @("add", "forward-server", "$SplunkIndexerIP`:$ReceiverPort", "-auth", "$SplunkUserSetup`:$SplunkPasswordSetup") -NoNewWindow -Wait

# Add basic monitors
Write-Host "Setting up basic monitors..."
Start-Process -FilePath $SplunkBin -ArgumentList @("add", "monitor", "C:\\Windows\\System32\\LogFiles\\W3SVC1", "-sourcetype", "iis") -NoNewWindow -Wait
Start-Process -FilePath $SplunkBin -ArgumentList @("add", "monitor", "C:\\Windows\\Logs", "-sourcetype", "windows_log") -NoNewWindow -Wait
Start-Process -FilePath $SplunkBin -ArgumentList @("add", "monitor", "C:\\ProgramData\\SplunkForwarder\\var\\log\\splunk", "-sourcetype", "splunkd_log") -NoNewWindow -Wait

# Enable Splunk service to start on boot
Write-Host "Enabling Splunk service to start on boot..."
Start-Process -FilePath $SplunkBin -ArgumentList @("enable", "boot-start") -NoNewWindow -Wait

# Start Splunk Universal Forwarder service
Write-Host "Starting Splunk Universal Forwarder service..."
Start-Service -Name SplunkForwarder -ErrorAction Stop

# Clean up installer
Write-Host "Cleaning up..."
Remove-Item -Path $InstallerPath -Force

Write-Host "Splunk Universal Forwarder v$SplunkVersion installation and configuration complete!"
