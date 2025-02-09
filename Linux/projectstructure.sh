{\rtf1\ansi\ansicpg1252\cocoartf2761
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\margl1440\margr1440\vieww51000\viewh28800\viewkind0
\pard\tx720\tx1440\tx2160\tx2880\tx3600\tx4320\tx5040\tx5760\tx6480\tx7200\tx7920\tx8640\pardirnatural\partightenfactor0

\f0\fs24 \cf0 #!/bin/bash\
\
# Check if the user provided a directory path\
if [ -z "$1" ]; then\
    echo "Error: No directory path provided. Usage: $0 /path/to/project"\
    exit 1\
fi\
\
# Define the path to the project directory\
PROJECT_DIR="$1"\
\
# Check if the directory exists\
if [ ! -d "$PROJECT_DIR" ]; then\
    echo "Error: Directory $PROJECT_DIR does not exist."\
    exit 1\
fi\
\
# Display the project structure using the tree command and format as a table\
echo "Generating project structure for $PROJECT_DIR..."\
echo "--------------------------------------------"\
echo -e "Directory Structure:\\n"\
echo "| Directory/Files |"\
echo "|-----------------|"\
\
# Using 'tree' command to print the structure\
# The '-L 2' option limits the depth to 2 levels (change as needed)\
tree -L 2 "$PROJECT_DIR" | while read -r line; do\
    # Format each line in a simple table structure\
    echo "| $line |"\
done\
\
echo "--------------------------------------------"\
}