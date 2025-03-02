# Install Docker and Docker Compose on Windows

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as an administrator"
    exit 1
}

# Detect operating system type
$os = Get-WmiObject Win32_OperatingSystem
if ($os.Caption -like "*Server*") {
    # Install Docker Engine for Windows Server
    if (-not (Get-WindowsFeature -Name Containers).Installed) {
        Write-Host "Installing Containers feature..."
        Install-WindowsFeature -Name Containers
        Write-Host "Containers feature installed. Please reboot the server and run this script again."
        exit 0
    }
    # Install Docker provider and package
    Install-Module -Name DockerMsftProvider -Force -SkipPublisherCheck
    Install-Package -Name Docker -ProviderName DockerMsftProvider -Force
    # Start Docker service
    Start-Service docker

    # Install Docker Compose if not already installed
    $composePath = "C:\Program Files\Docker\docker-compose.exe"
    if (-not (Test-Path $composePath)) {
        Write-Host "Installing Docker Compose..."
        $composeVersion = (Invoke-RestMethod -Uri "https://api.github.com/repos/docker/compose/releases/latest").tag_name
        if (-not $composeVersion) {
            Write-Host "Failed to fetch latest Docker Compose version. Using default version 2.20.0"
            $composeVersion = "2.20.0"
        }
        $composeUrl = "https://github.com/docker/compose/releases/download/${composeVersion}/docker-compose-Windows-x86_64.exe"
        Invoke-WebRequest -Uri $composeUrl -OutFile $composePath
        # Ensure C:\Program Files\Docker is in PATH
        $dockerDir = "C:\Program Files\Docker"
        if (-not ($env:Path -split ';' -contains $dockerDir)) {
            $newPath = $env:Path + ";$dockerDir"
            [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::Machine)
            Write-Host "Added $dockerDir to system PATH"
        }
        Write-Host "Docker Compose installed successfully"
    } else {
        Write-Host "Docker Compose is already installed"
    }
} else {
    # Install Docker Desktop for Windows 10
    $installerUrl = "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
    $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
    Write-Host "Downloading Docker Desktop installer..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
    Write-Host "Installing Docker Desktop..."
    Start-Process -FilePath $installerPath -ArgumentList "/quiet" -Wait
    Write-Host "Docker Desktop installed successfully (includes Docker Compose)"
}

# Verify installations
Write-Host "Verifying installations..."
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "Docker is installed: $(docker --version)"
} else {
    Write-Host "Docker is not installed or not in PATH"
}
if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    Write-Host "Docker Compose is installed: $(docker-compose --version)"
} else {
    Write-Host "Docker Compose is not installed or not in PATH"
}
