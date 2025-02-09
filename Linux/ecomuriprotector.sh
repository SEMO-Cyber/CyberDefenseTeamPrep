#!/bin/bash\
\
# Check if the user provided a directory path\
if [ -z "$1" ]; then\
    echo "Error: No directory path provided. Usage: $0 /path/to/webapp"\
    exit 1\
fi\
\
# Define the path to your web app directory\
WEB_APP_DIR="$1"\
\
# Check if the directory exists\
if [ ! -d "$WEB_APP_DIR" ]; then\
    echo "Error: Directory $WEB_APP_DIR does not exist."\
    exit 1\
fi\
\
# Define the location of the .htaccess file\
HTACCESS_FILE="$WEB_APP_DIR/.htaccess"\
\
# Check if the .htaccess file exists\
if [ ! -f "$HTACCESS_FILE" ]; then\
    echo "Error: .htaccess file does not exist. Creating a new one."\
    touch "$HTACCESS_FILE"\
fi\
\
# Add security configurations to the .htaccess file\
\
echo "Securing .htaccess file..."\
\
# Prevent directory listing\
echo -e "\\n# Prevent directory listing" >> "$HTACCESS_FILE"\
echo "Options -Indexes" >> "$HTACCESS_FILE"\
\
# Block access to sensitive files\
echo -e "\\n# Block access to sensitive files (settings.inc.php, .env, etc.)" >> "$HTACCESS_FILE"\
echo "<FilesMatch \\"\\.(settings.inc\\.php|\\.env)\\">" >> "$HTACCESS_FILE"\
echo "    Order Deny,Allow" >> "$HTACCESS_FILE"\
echo "    Deny from all" >> "$HTACCESS_FILE"\
echo "</FilesMatch>" >> "$HTACCESS_FILE"\
\
# Block access to install folder\
echo -e "\\n# Block access to the install directory" >> "$HTACCESS_FILE"\
echo "<Directory \\"$WEB_APP_DIR/install\\">" >> "$HTACCESS_FILE"\
echo "    Order Deny,Allow" >> "$HTACCESS_FILE"\
echo "    Deny from all" >> "$HTACCESS_FILE"\
echo "</Directory>" >> "$HTACCESS_FILE"\
\
# Restrict access to the admin folder by IP (change to your IP address)\
# If you want to allow access only from a specific IP, uncomment the next lines and replace "your_ip_address"\
ALLOWED_IP="your_ip_address"\
echo -e "\\n# Restrict access to the Admin panel by IP" >> "$HTACCESS_FILE"\
echo "<Directory \\"$WEB_APP_DIR/admin\\">" >> "$HTACCESS_FILE"\
echo "    Order Deny,Allow" >> "$HTACCESS_FILE"\
echo "    Deny from all" >> "$HTACCESS_FILE"\
echo "    Allow from $ALLOWED_IP" >> "$HTACCESS_FILE"\
echo "</Directory>" >> "$HTACCESS_FILE"\
\
# Block common attack methods like DELETE, TRACE, and OPTIONS\
echo -e "\\n# Block dangerous HTTP methods (DELETE, TRACE, OPTIONS)" >> "$HTACCESS_FILE"\
echo "<Limit DELETE TRACE OPTIONS>" >> "$HTACCESS_FILE"\
echo "    Deny from all" >> "$HTACCESS_FILE"\
echo "</Limit>" >> "$HTACCESS_FILE"\
\
# Secure file upload types (You can modify these based on your needs)\
echo -e "\\n# Restrict file uploads (Allow only specific MIME types)" >> "$HTACCESS_FILE"\
echo "<IfModule mod_mime.c>" >> "$HTACCESS_FILE"\
echo "    AddType application/x-httpd-php .php .php3 .php4 .php5 .php7 .phtml" >> "$HTACCESS_FILE"\
echo "    AddType application/x-httpd-php .html .htm" >> "$HTACCESS_FILE"\
echo "    AddType application/x-httpd-php .css .js" >> "$HTACCESS_FILE"\
echo "</IfModule>" >> "$HTACCESS_FILE"\
\
# Restrict upload file size (adjust the size limit as per your requirement)\
echo -e "\\n# Restrict file upload size" >> "$HTACCESS_FILE"\
echo "php_value upload_max_filesize 2M" >> "$HTACCESS_FILE"\
echo "php_value post_max_size 2M" >> "$HTACCESS_FILE"\
echo "php_value max_execution_time 60" >> "$HTACCESS_FILE"\
echo "php_value max_input_time 60" >> "$HTACCESS_FILE"\
\
# Set correct permissions to the .htaccess file\
chmod 644 "$HTACCESS_FILE"\
\
# Print success message\
echo ".htaccess file has been secured for $WEB_APP_DIR!"\
}
