#  This is the second half of the SplunkHarden.sh script. 
#  This exists so that I can reset much of Splunk's config quicky, if need be. Runnning the entirety
#  of SplunkHarden.sh is too time consuming.
#  I don't recommend running this unless you have already ran SplunkHarden.sh. You will at best waste time
#  and at worst miss out on a lot of automated hardening.
#
#  Samuel Brucker 2024-2025



echo "Hardening the Splunk configuration..."

# Set the banner for Splunk
cat > "$SPLUNK_HOME/etc/system/local/global-banner.conf" << EOF
[BANNER_MESSAGE_SINGLETON]
global_banner.visible = true
global_banner.message = WARNING: NO UNAUTHORIZED ACCESS. This is property of Team 10 LLC. Unauthorized users will be prosecuted and tried to the furthest extent of the law!
global_banner.background_color = red
EOF


# Set better permissions for important Splunk configurations
echo "Setting secure local file permissions..."
chmod -R 700 "$SPLUNK_HOME/etc/system/local"
chmod -R 700 "$SPLUNK_HOME/etc/system/default"
chown -R splunk:splunk "$SPLUNK_HOME/etc"


#echo "Changing Splunk admin password..."
while true; do
    echo "Enter new password for Splunk admin user: "
    stty -echo
    read splunkPass
    stty echo

    echo "Confirm new password: "
    stty -echo
    read confirmPass
    stty echo

    if [ "$splunkPass" = "$confirmPass" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

# Set consistent authentication variables
SPLUNK_USERNAME="admin"
SPLUNK_PASSWORD="$splunkPass"
OG_SPLUNK_PASSWORD="changeme"

# Change admin password with proper error handling
if ! $SPLUNK_HOME/bin/splunk edit user $SPLUNK_USERNAME -password "$SPLUNK_PASSWORD" -auth "$SPLUNK_USERNAME:$OG_SPLUNK_PASSWORD"; then
    echo "Error: Failed to change admin password"
    exit 1
fi

$SPLUNK_HOME/bin/splunk edit user SPLUNK_USERNAME -password $splunkPass -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"

#Remove all users except admin user. This is a little wordy in the output.
USERS=$($SPLUNK_HOME/bin/splunk list user -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}" | grep -v "$SPLUNK_USERNAME" | awk '{print $2}')

for USER in $USERS; do
    $SPLUNK_HOME/bin/splunk remove user $USER -auth "${SPLUNK_USERNAME}:${SPLUNK_PASSWORD}"
done

# Configure receivers
cat > "$SPLUNK_HOME/etc/system/local/inputs.conf" << EOF
#TCP input for Splunk forwarders (port 9997)
#Commented out as I prefer being able to see this listener in the webgui, so I use Splunk CLI to add this automatically
#[tcp://9997]
#index = main
#sourcetype = tcp:9997
#connection_host = dns
#disabled = false

[tcp://514]
sourcetype = pan:firewall
no_appending_timestamp = true
index = pan_logs
EOF

#Add the 9997 listener using splunk CLI
$SPLUNK_HOME/bin/splunk enable listen 9997 -auth "$SPLUNK_USERNAME:$SPLUNK_PASSWORD"

#Add the index for Palo logs
$SPLUNK_HOME/bin/splunk add index pan_logs

# Install Palo Alto Networks apps
echo "Installing Palo Alto Networks apps..."

# Clone the Palo Alto splunk app
git clone https://github.com/PaloAltoNetworks/SplunkforPaloAltoNetworks.git SplunkforPaloAltoNetworks
mv SplunkforPaloAltoNetworks "$SPLUNK_HOME/etc/apps/"

# Clone the Palo Alto splunk add-on
git clone https://github.com/PaloAltoNetworks/Splunk_TA_paloalto.git Splunk_TA_paloalto
mv Splunk_TA_paloalto "$SPLUNK_HOME/etc/apps/"

# Disable distributed search
echo "Disabling distributed search"
echo "[distributedSearch]" > $SPLUNK_HOME/etc/system/local/distsearch.conf
echo "disabled = true" >> $SPLUNK_HOME/etc/system/local/distsearch.conf

# Restart Splunk to apply changes
echo "Restarting Splunk to apply changes..."
$SPLUNK_HOME/bin/splunk restart

#Backup Splunk again now that changes have been made
echo "Backing up latest Splunk configurations..."
mkdir -p "$BACKUP_DIR/splunk"
cp -R "$SPLUNK_HOME" "$BACKUP_DIR/splunk"
echo "Verifying backup integrity..."
find "$BACKUP_DIR/splunk" -type f -size +0 -print0 | xargs -0 md5sum > "$BACKUP_DIR/splunk/md5sums.txt"
find "$BACKUP_DIR/splunk" -type f -size 0 -delete


############################
# WIP, not functioning yet #
############################

#Lock down who is able to log in
#make sure files exist
#touch "$SPLUNK_HOME/etc/system/local/authentication.conf"
#touch "$SPLUNK_HOME/etc/system/local/authorize.conf"

# Edit authentication.conf
#cat > $SPLUNK_HOME/etc/system/local/authentication.conf << EOF
#[authentication]
#authType = Splunk
#authSettings = Splunk

#[roleMap_Splunk]
#sysadmin = admin

#[authenticationResponse]
#attributemap = Splunk:role -> role
#EOF

# Edit authorize.conf
#cat > $SPLUNK_HOME/etc/system/local/authorize.conf << EOF
#[role_admin]
#importRoles = admin
#srchJobsQuota = 50
#rtSrchJobsQuota = 50
#srchDiskQuota = 10000
#srchFilter = *
#srchIndexesAllowed = *
#srchIndexesDefault = main
#srchMaxTime = 8640000
#rtSrchMaxTime = 30
#srchMaxTotalDiskQuota = 500000
#importRoles = user
#srchJobsQuota = 50
#rtSrchJobsQuota = 50
#srchDiskQuota = 10000
#srchFilter = *
#srchIndexesAllowed = *
#srchIndexesDefault = main
#srchMaxTime = 8640000
#rtSrchMaxTime = 30
#srchMaxTotalDiskQuota = 500000
#EOF


echo "\n\nMAKE SURE YOU ENUMERATE!!!"
echo "Check for cronjobs, services on timers, etc. Also do a manual search through Splunk. Once done, run sudo yum update -y and then restart the machine. Have fun!\n\n"
