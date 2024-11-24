#
# Powershell install script for Pace CCDC Team Windows Splunk Universal Forwarder
# Version 1.0.0
# Written by Daniel Barr
# 
# ---------------------------------------------------------------------
# Free to use by all teams. Please realize you are using this script
# at your own risk. The author holds no liability and will not be held
# responsible for any damages done to systems or system configurations.
# ---------------------------------------------------------------------
# This script will install the SPLUNK UNIVERSAL FORWARDER. 
# In addition it will download the predetermined configuration files.
# ---------------------------------------------------------------------
# Take note these configurations may need to be adjusted by the user as
# needed. Every environment is different and should be treated as such.
# ---------------------------------------------------------------------
# The goal of this install script is to efficiently deploy the necessary
# tool-sets for effective system monitoring during the Collegiate Cyber
# Defense Competition. This tool-set represents a larger overall strategy
# and should be tailored to your specific team.


$splunklocation = 'C:\Program Files\*' 															 # directory to check for splunk installation
$instdir = 'C:\Program Files\SplunkUniversalForwarder\'
$indexer = Read-Host -Prompt 'What is the IP Address:Port of your Indexer'          			 # hostname or ip : port of indexer
$depserv = Read-Host -Prompt 'What is the IP Address:Port of your Deployment Server'			 # hostname or ip : port of deploymentServer
$teamnum = Read-Host -Prompt 'What is your Team Number'											 # team number
$spad = 'ccdcadmin' + $teamnum 										 							

# path to inputs.conf
$localinputs = 'C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf'

# variables to add to inputs.conf for powershell log forwarding
$fdmo = "`r`n[WinEventLog://Microsoft-Windows-PowerShell-DesiredStateConfiguration-FileDownloadManager/Operational]`r`ndisabled = 0`r`n"
$mwpo = "`r`n[WinEventLog://Microsoft-Windows-PowerShell/Operational]`r`ndisabled = 0`r`n"

# variable to restart splunkd
$restart = 'C:\Program Files\SplunkUniversalForwarder\bin\splunk.exe restart'

# variable used to delete script after its run and installed correctly
# $self = $path + '\splunk-script-v1.1.ps1'


Write-Host "* Checking for previous installations of Splunk Universal Forwarder..." -ForegroundColor Magenta

# Checks to see if a splunk folder already exists in Program Files
# Skips installation if it finds a splunk folder

if (Test-Path -Path $splunklocation -Include "*splunk*")
{
    Write-Host "[!] a copy of SPLUNK UNIVERSAL FORWARDER is already installed!" -ForgroundColor Red
    exit 0
}else{
    Write-Host '* Downloading Splunk Universal Forwarder...' -ForegroundColor Magenta
	wget -O splunkforwarder-8.msi 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=windows&version=8.0.0&product=universalforwarder&filename=splunkforwarder-8.0.0-1357bef0a7f6-x64-release.msi&wget=true'
	Start-Sleep -seconds 1
    Write-Host '* Installing Splunk Universal Forwarder...' -ForegroundColor Magenta
    
    # uses msi to install splunk forwarder, file names need to match and be co-located
    # /quiet suppresses gui, otherwise the script will fail
    # additional switches would be needed for an enterprise installation
    # testing on whether local user can collect log files (i believe no)
    # might need to be installed as a domain user or local admin?
    # see: <http://docs.splunk.com/Documentation/Forwarder/6.5.1/Forwarder/InstallaWindowsuniversalforwarderfromthecommandline>
    # for supported switches and installation instructions
    Start-Process -FilePath msiexec.exe -ArgumentList "/i '~\splunkforwarder-8.msi INSTALLDIR=$instdir	DEPLOYMENT_SERVER=$depserv RECEIVING_INDEXER=$indexer WINEVENTLOG_APP_ENABLE=1 WINEVENTLOG_SEC_ENABLE=1 WINEVENTLOG_SYS_ENABLE=1 SPLUNKUSERNAME=$spad SPLUNKPASSWORD=$uperCCDC2019 LAUNCHSPLUNK=1 AGREETOLICENSE=Yes /quiet" -Wait
    
    # added to be sure the splunk app has time to boot properly before checking in the function below
    # the -Wait option above, might have fixed problem with script quitting before splunk had time to boot
    # try elminating the sleep, or reducing the time to speed up installation
    Sleep 10
}


# checks to see if splunkd is running which indicates good install
# then adds the necessary lines to input.conf to retrieve powershell logs

function Check-Splunk-Status {
# Check if the status of the service is equal to 'Running'.
  if ($splService.Status -eq 'Running'){
	Write-Host '* Splunk Forwarder is Running' -ForegroundColor Green
	Return # If the service is running break out of the function and continue.
	} else { 
	# Tell the user there was a problem and offer some troubleshooting guidance.
	Write-Host '[!] Splunk Forwarder is Not Running!' -ForegroundColor Red
	Write-Host '[!] Try manually restarting.' -ForegroundColor Yellow
	Write-Host '[!] Then re-run the script...exiting.' -ForegroundColor Yellow
	exit # If the service is not running terminate the script.
	}
}

if ($splService.Status -eq 'Running'){  # checks for running splunkd process
{
    Write-Host '* Editing Configuration Files...' -ForegroundColor Magenta
    # writes lines to inputs.conf
    # had to add encoding switch to fix issues when installing on windows 8.1
    Out-File -Encoding utf8 -Append -FilePath $localinputs -InputObject $mwpo, $fdmo
    Write-Host '* Restarting Splunk to apply changes...' -ForegroundColor Magenta
    
    Invoke-Expression $restart  # restarts splunkd so changes take effect
    Start-Sleep -seconds 5
	
    if ($splService.Status -eq 'Running'){  # confirms if it restarted successfully
        Write-Host '* Splunk Forwarder restarted successfully' -ForegroundColor Green
		Write-Host '* Running clean up.' -ForegroundColor Green   
        Remove-Item $instfile
        Write-Host '* Clean up complete. Exiting...' -ForegroundColor Green
        # uncomment line below to have the script delete itself when the installation is complete
        # Remove-Item $self
        exit 0
    }else{
        Write-Host '[!] Splunk Forwarder is did not restart successfully!' -ForegroundColor Red
		Write-Host '[!] Try manually restarting.' -ForegroundColor Yellow
		Write-Host '[!] Then re-run the script...exiting.' -ForegroundColor Yellow
        exit 0
    }
}