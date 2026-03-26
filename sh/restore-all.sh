#!/bin/sh

# restore-all.sh - Restore all SQL files from database-backup folder
# Usage: sh restore-all.sh  OR  bash restore-all.sh  OR  ./restore-all.sh

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
# BACKUP_DIR="$SCRIPT_DIR/../database-backup"
BACKUP_DIR="$SCRIPT_DIR/../database-backup/valasmate"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

. "$ENV_FILE"

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# Find all SQL files and count them
SQL_FILES=$(find "$BACKUP_DIR" -type f \( -name "*.sql" -o -name "*.sql.gz" \) | sort)
FILE_COUNT=$(echo "$SQL_FILES" | grep -c .)

# Check if any SQL files found
if [ -z "$SQL_FILES" ] || [ "$FILE_COUNT" -eq 0 ]; then
    echo "Error: No SQL files found in $BACKUP_DIR"
    exit 1
fi

echo "================================================"
echo "MariaDB Batch Restore"
echo "================================================"
echo "Backup Directory: $BACKUP_DIR"
echo "Target Database: $MYSQL_DATABASE"
echo "Files Found: $FILE_COUNT"
echo "================================================"
echo ""
echo "Files to restore:"

# Display files with counter
counter=1
echo "$SQL_FILES" | while read -r file; do
    if [ -n "$file" ]; then
        FILE_NAME=$(basename "$file")
        FILE_SIZE=$(du -h "$file" | cut -f1)
        echo "  $counter. $FILE_NAME ($FILE_SIZE)"
        counter=$((counter + 1))
    fi
done

echo ""
echo "================================================"
echo ""
printf "This will restore all files. Continue? (y/n): "
read -r REPLY

if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    echo "Restore cancelled"
    exit 1
fi

echo ""
SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_FILES=""
CURRENT=0

# Process each file
echo "$SQL_FILES" | while read -r SQL_FILE; do
    if [ -z "$SQL_FILE" ]; then
        continue
    fi

    CURRENT=$((CURRENT + 1))
    FILE_NAME=$(basename "$SQL_FILE")

    echo "================================================"
    echo "[$CURRENT/$FILE_COUNT] Processing: $FILE_NAME"
    echo "================================================"

    # Check if file is gzipped
    case "$SQL_FILE" in
        *.gz)
            gunzip -c "$SQL_FILE" | mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" 2>/dev/null
            ;;
        *)
            mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$SQL_FILE" 2>/dev/null
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo "Success: $FILE_NAME"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "Failed: $FILE_NAME"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        if [ -z "$FAILED_FILES" ]; then
            FAILED_FILES="$FILE_NAME"
        else
            FAILED_FILES="$FAILED_FILES, $FILE_NAME"
        fi
    fi
    echo ""
done

echo "================================================"
echo "Restore Summary"
echo "================================================"
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAILED_COUNT"
echo "Total: $FILE_COUNT"

if [ $FAILED_COUNT -gt 0 ] && [ -n "$FAILED_FILES" ]; then
    echo ""
    echo "Failed files: $FAILED_FILES"
fi

echo "================================================"
