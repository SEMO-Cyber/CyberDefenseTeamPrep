# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Please run this script as Administrator"
  exit 1
}

# Check if Docker Desktop is already installed
if (Test-Path "C:\Program Files\Docker\Docker\Docker Desktop.exe") {
  Write-Host "Docker Desktop is already installed"
} else {
  # Define download URL and temporary file path
  $installerUrl = "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
  $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"

  # Download Docker Desktop installer
  Write-Host "Downloading Docker Desktop installer..."
  Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

  # Run the installer silently
  Write-Host "Installing Docker Desktop..."
  Start-Process -Wait -FilePath $installerPath -ArgumentList "install", "--quiet"

  # Clean up the installer file
  Remove-Item $installerPath

  Write-Host "Docker Desktop has been installed. You may need to restart your computer or start Docker Desktop manually."
}

Write-Host "Docker installation process completed."