#!/bin/sh

# restore-all-databases.sh - Restore all SQL files as separate databases
# Usage: sh restore-all-databases.sh

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
BACKUP_DIR="$SCRIPT_DIR/../database-backup"

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

echo "================================================"
echo "MariaDB Batch Restore (Separate Databases)"
echo "================================================"
echo "Backup Directory: $BACKUP_DIR"
echo "User: $MYSQL_USER"
echo "================================================"
echo ""

printf "This will create and restore all databases. Continue? (y/n): "
read -r REPLY

if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    echo "Restore cancelled"
    exit 1
fi

echo ""
SUCCESS_COUNT=0
FAILED_COUNT=0
TOTAL_COUNT=0

# Process each SQL file
for SQL_FILE in "$BACKUP_DIR"/*.sql "$BACKUP_DIR"/*.sql.gz; do
    # Skip if no files found
    if [ ! -f "$SQL_FILE" ]; then
        continue
    fi

    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    FILE_NAME=$(basename "$SQL_FILE")

    # Extract database name from filename
    # Format: dump-dbname-timestamp.sql -> dbname
    DB_NAME=$(echo "$FILE_NAME" | sed 's/^dump-//' | sed 's/-[0-9]*\.sql.*$//')

    echo "================================================"
    echo "[$TOTAL_COUNT] Processing: $FILE_NAME"
    echo "Database: $DB_NAME"
    echo "================================================"

    # Create database if not exists
    echo "Creating database: $DB_NAME"
    mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1

    if [ $? -ne 0 ]; then
        echo "FAILED: Could not create database $DB_NAME"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        echo ""
        continue
    fi

    # Restore dump to the database
    echo "Restoring data..."
    case "$SQL_FILE" in
        *.gz)
            gunzip -c "$SQL_FILE" | mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$DB_NAME"
            RESTORE_RESULT=$?
            ;;
        *)
            mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$DB_NAME" < "$SQL_FILE"
            RESTORE_RESULT=$?
            ;;
    esac

    if [ $RESTORE_RESULT -eq 0 ]; then
        echo "SUCCESS: Database '$DB_NAME' restored"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "FAILED: Database '$DB_NAME' restore failed (exit code: $RESTORE_RESULT)"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    echo ""
done

echo "================================================"
echo "Restore Summary"
echo "================================================"
echo "Total processed: $TOTAL_COUNT"
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAILED_COUNT"
echo "================================================"
echo ""

# Show all databases
echo "All databases:"
mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database" | grep -v "information_schema" | grep -v "performance_schema" | sed 's/^/  - /'

echo ""
echo "Done!"
