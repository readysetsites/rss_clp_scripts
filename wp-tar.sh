#!/bin/bash

# Get the current user's username
USERNAME=$(whoami)

# Get the current date and time
DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%H-%M-%S")

# Set the backup folder name and file name
BACKUP_FOLDER="$DATE"_"$TIME"

# If no filename is specified, use the username as the filename
if [ -z "$1" ]; then
  BACKUP_FILE="$USER"_"$DATE"_"$TIME".tar.gz
else
  BACKUP_FILE="$1".tar.gz
fi

# Find the WordPress install directory within the current folder
WP_DIRS=$(find . -name 'wp-config.php' -printf '%h\n' | sort -u)

# If no WordPress install directories are found, exit the script
if [ -z "$WP_DIRS" ]; then
  echo "Error: No WordPress install found within the current directory."
  exit 1
fi

# If there are multiple WordPress install directories, exit the script
if [ $(echo "$WP_DIRS" | wc -l) -gt 1 ]; then
  echo "Error: Multiple WordPress installs found within the current directory. Use the cd command to find the right one."
  exit 1
fi

# Change to the WordPress install directory
cd "$WP_DIRS"

# Export the database to db.sql
wp db export db.sql

# Create a backup folder and copy db.sql and wp-content into it
mkdir -p "$HOME/backups/$BACKUP_FOLDER"
cp -r wp-content db.sql "$HOME/backups/$BACKUP_FOLDER"

# Remove db.sql
rm db.sql

# Create a backup of the backup folder
tar -czf "$HOME/backups/$BACKUP_FILE" -C "$HOME/backups" "$BACKUP_FOLDER"

# Remove the backup folder
rm -rf "$HOME/backups/$BACKUP_FOLDER"

echo "The backup ($BACKUP_FILE) has been created and was placed in the ~/backups folder."