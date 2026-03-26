#!/bin/sh

# backup.sh - Backup MariaDB database
# Usage: sh backup.sh [output_directory]  OR  bash backup.sh  OR  ./backup.sh

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

. "$ENV_FILE"

# Default backup directory
if [ -n "$1" ]; then
    BACKUP_DIR="$1"
else
    BACKUP_DIR="$SCRIPT_DIR/../backup"
fi

# Create backup directory if not exists
mkdir -p "$BACKUP_DIR"

# Generate filename with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_${MYSQL_DATABASE}_${TIMESTAMP}.sql"
BACKUP_FILE_GZ="${BACKUP_FILE}.gz"

echo "================================================"
echo "MariaDB Database Backup"
echo "================================================"
echo "Database: $MYSQL_DATABASE"
echo "User: $MYSQL_USER"
echo "Output: $BACKUP_FILE_GZ"
echo "================================================"
echo ""

echo "Starting backup..."

# Backup database
mysqldump -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    "$MYSQL_DATABASE" > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "Backup completed"

    # Compress backup
    echo "Compressing backup..."
    gzip "$BACKUP_FILE"

    if [ $? -eq 0 ]; then
        FILE_SIZE=$(du -h "$BACKUP_FILE_GZ" | cut -f1)
        echo "Compression completed"
        echo ""
        echo "================================================"
        echo "Backup Summary"
        echo "================================================"
        echo "File: $(basename "$BACKUP_FILE_GZ")"
        echo "Size: $FILE_SIZE"
        echo "Location: $BACKUP_DIR"
        echo "================================================"
    else
        echo "Compression failed, keeping uncompressed backup"
        FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo "File: $(basename "$BACKUP_FILE")"
        echo "Size: $FILE_SIZE"
    fi
else
    echo "Backup failed!"
    exit 1
fi
