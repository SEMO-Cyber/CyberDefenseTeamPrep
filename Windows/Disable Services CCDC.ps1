# Disable Windows features using DISM

$featuresToDisable = @(
    "Printing-Server-Role",
    "IIS-WebServer",
    "IIS-FTPServer",
    "IIS-WebServerRole",
    "IIS-WebServerManagementTools",
    "IIS-ManagementScriptingTools",
    "IIS-IIS6ManagementCompatibility",
    "IIS-Metabase",
    "IIS-ManagementConsole",
    "RDS-RD-Server",
    "RDS-Licensing",
    "RDS-RD-Web-Access",
    "RDS-Connection-Broker",
    "RDS-Remote-Desktop",
    "RDS-Gateway",
    "RDS-RemoteApp-Server",
    "RDS-RemoteDesktopGateway",
    "RDS-RemoteDesktopSessionHost",
    "RDS-RD-Connection-Broker",
    "RDS-RD-Gateway",
    "RDS-RD-Licensing-Diagnosis-UI",
    "TelnetClient",
    "TelnetServer",
    "SMB1Protocol",
    "MSMQ-Server",
    "MSMQ-HTTP",
    "MSMQ-Triggers",
    "SimpleTCP",
    "SNMP",
    "SNMP-Service",
    "SNMP-WMI-Provider",
    "RemoteAssistance",
    "RemoteAssistance-Helper",
    "WindowsMediaPlayer",
    "WindowsMediaPlayer-OCX",
    "MediaPlayback",
    "MediaCenter",
    "MediaCenter-OCX",
    "Xps-Foundation-Xps-Viewer",
    "Xps-Viewer"
)

foreach ($feature in $featuresToDisable) {
    Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart
}

# Optional: Restart the computer if needed
# Restart-Computer -Force

Read-Host "Press Enter to exit..."