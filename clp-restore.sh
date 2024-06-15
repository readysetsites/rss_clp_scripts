#!/bin/bash

# Check if backup file argument is provided
if [ -z "$1" ]; then
  echo "Error: Backup file argument not provided"
  exit 1
fi

# Get the current timestamp
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Create backups directory if it doesn't exist
BACKUPS_DIR=~/backups
mkdir -p "$BACKUPS_DIR"

# Determine if the argument is a URL or a file path
if [[ "$1" =~ ^https?:// ]]; then
  # If it's a URL, download the backup file to the backups directory
  BACKUP_FILE=$BACKUPS_DIR/backup_download_$TIMESTAMP.tar
  wget -O "$BACKUP_FILE" "$1"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to download the backup file"
    exit 1
  fi
else
  # If it's a file path, use the provided argument
  BACKUP_FILE=$(readlink -f "$1")
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file not found"
  exit 1
fi

# Check if wp-config.php exists and is unique
WP_CONFIG=$(find ~/htdocs -name "wp-config.php" | wc -l)
if [ $WP_CONFIG -eq 0 ]; then
  echo "Error: No WordPress installation found"
  exit 1
elif [ $WP_CONFIG -gt 1 ]; then
  echo "Error: Multiple WordPress installations found"
  exit 1
fi

# Get the path of the WordPress installation
WP_DIR=$(find ~/htdocs -name "wp-config.php" -exec dirname {} \;)

# Get the site URL
SITE_URL=$(wp --path="$WP_DIR" option get siteurl --skip-plugins --skip-themes)
echo "Current Site URL: $SITE_URL"

# Create a temporary restore directory
RESTORE_DIR=~/tmp/restore-$TIMESTAMP
mkdir -p "$RESTORE_DIR"

# Copy the backup file to the restore directory
cp "$BACKUP_FILE" "$RESTORE_DIR"

echo "Uncompressing backup..."
# Uncompress the backup file
cd "$RESTORE_DIR" || exit
if [[ "$BACKUP_FILE" == *".zip" ]]; then
  unzip "$BACKUP_FILE"
elif [[ "$BACKUP_FILE" == *".tar.gz" ]]; then
  tar -xzf "$BACKUP_FILE"
elif [[ "$BACKUP_FILE" == *".tar" ]]; then
  tar -xf "$BACKUP_FILE"
else
  echo "Error: Backup file must be a .zip, .tar.gz, or .tar file"
  exit 1
fi

# Find the wp-content directory
WP_CONTENT=$(find "$RESTORE_DIR" -name "wp-content" -type d)
if [ -z "$WP_CONTENT" ]; then
  echo "Error: No wp-content directory found"
  exit 1
elif [ $(echo "$WP_CONTENT" | wc -l) -gt 1 ]; then
  echo "Error: Multiple wp-content directories found"
  exit 1
fi

echo "Enabling maintenance mode..."
# Activate maintenance mode
wp --path="$WP_DIR" maintenance-mode activate --skip-plugins --skip-themes

echo "Deleting existing wp-content..."
# Delete the existing wp-content directory
rm -rf "$WP_DIR/wp-content"

echo "Importing SQL files..."
# Loop through all .sql files in the directory and its subdirectories
SQL_FILES=$(find "$RESTORE_DIR" -type f -name "*.sql")
if [ -z "$SQL_FILES" ]; then
  echo "No .sql files found. Searching for .sql.gz files..."
  # Find the newest .sql.gz file
  NEWEST_SQL_GZ=$(find "$RESTORE_DIR" -type f -name "*.sql.gz" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2)
  if [ -z "$NEWEST_SQL_GZ" ]; then
    echo "Error: No .sql or .sql.gz files found"
    exit 1
  else
    echo "Found .sql.gz file: $NEWEST_SQL_GZ"
    gunzip "$NEWEST_SQL_GZ"
    SQL_FILES="${NEWEST_SQL_GZ%.gz}"
  fi
fi

for file in $SQL_FILES; do
  # Import the database
  wp --path="$WP_DIR" db import "$file" --skip-plugins --skip-themes
done

echo "Moving wp-content folder..."
# Move the uploads directory
mv "$WP_CONTENT" "$WP_DIR"

# Verify plugin checksums and reinstall if they fail
echo "Verifying plugin checksums..."
PLUGINS_TO_REINSTALL=()
for plugin in $(wp --path="$WP_DIR" plugin list --field=name --skip-plugins --skip-themes); do
  if ! wp --path="$WP_DIR" plugin verify-checksums "$plugin" --skip-plugins --skip-themes; then
    PLUGINS_TO_REINSTALL+=("$plugin")
  fi
done

if [ ${#PLUGINS_TO_REINSTALL[@]} -gt 0 ]; then
  echo "Reinstalling plugins that failed checksum verification..."
  for plugin in "${PLUGINS_TO_REINSTALL[@]}"; do
    wp --path="$WP_DIR" plugin install "$plugin" --force --skip-plugins --skip-themes
  done
fi

echo "Flushing caches..."
wp --path="$WP_DIR" cache flush --skip-plugins --skip-themes
clpctl varnish-cache:purge --purge=all

echo "Running search/replace..."
# Update URLs in the database
OLD_SITE_URL=$(wp --path="$WP_DIR" option get siteurl --skip-plugins --skip-themes)
wp --path="$WP_DIR" search-replace "$OLD_SITE_URL" "$SITE_URL" --skip-plugins --skip-themes
echo "Searched for $OLD_SITE_URL and replaced with $SITE_URL."

# Check if Elementor is installed and active
if wp --path="$WP_DIR" plugin is-installed elementor --skip-plugins --skip-themes && wp --path="$WP_DIR" plugin is-active elementor --skip-plugins --skip-themes; then
  # Flush object cache again
  wp --path="$WP_DIR" cache flush --skip-plugins --skip-themes
  # Elementor is installed and active, run the replace-urls command
  wp --path="$WP_DIR" elementor replace-urls "$OLD_SITE_URL" "$SITE_URL" --force
  wp --path="$WP_DIR" elementor flush-css
else
  # Elementor is not installed or active, do nothing
  echo "Elementor is not installed or active. Skipping Elementor commands."
fi

# Deactivate maintenance mode
wp --path="$WP_DIR" maintenance-mode deactivate --skip-plugins --skip-themes

echo "Flushing caches..."
wp --path="$WP_DIR" cache flush --skip-plugins --skip-themes
clpctl varnish-cache:purge --purge=all

# Clean up
rm -rf "$RESTORE_DIR"

echo "Un-tar / un-zip complete!"
