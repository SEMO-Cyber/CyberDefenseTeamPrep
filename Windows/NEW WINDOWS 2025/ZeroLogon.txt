# Zerologon Mitigation - Harden Netlogon

# Function to log messages
function Write-Log {
    param (
        [string]$Message
    )
    $LogFile = "$env:SystemRoot\Logs\ZerologonFix.log"
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFile
}

# Harden Netlogon function
function Harden-Netlogon {
    $RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
    $ValueName = "FullSecureChannelProtection"
    $NewValue = 1

    if (-not (Test-Path $RegistryPath)) {
        Write-Log "Registry path does not exist: $RegistryPath"
        return
    }

    Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $NewValue -Force
    Write-Log "Successfully hardened Netlogon (Zerologon fix applied)"
}

# Execute the function
Harden-Netlogon
