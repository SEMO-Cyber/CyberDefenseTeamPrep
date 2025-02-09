#!/bin/bash\
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
