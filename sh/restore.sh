#!/bin/sh

# restore.sh - Restore single SQL file to MariaDB database
# Usage: sh restore.sh <sql_file>  OR  bash restore.sh <sql_file>  OR  ./restore.sh <sql_file>

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

. "$ENV_FILE"

# Check if SQL file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <sql_file>"
    echo "Example: $0 database-backup/mydatabase.sql"
    exit 1
fi

SQL_FILE="$1"

# Check if file exists
if [ ! -f "$SQL_FILE" ]; then
    echo "Error: SQL file not found: $SQL_FILE"
    exit 1
fi

# Get file info
FILE_SIZE=$(du -h "$SQL_FILE" | cut -f1)
FILE_NAME=$(basename "$SQL_FILE")

echo "================================================"
echo "MariaDB Database Restore"
echo "================================================"
echo "File: $FILE_NAME"
echo "Size: $FILE_SIZE"
echo "Database: $MYSQL_DATABASE"
echo "User: $MYSQL_USER"
echo "================================================"
echo ""

printf "Continue with restore? (y/n): "
read -r REPLY

if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    echo "Restore cancelled"
    exit 1
fi

echo "Restoring database..."

# Check if file is gzipped
case "$SQL_FILE" in
    *.gz)
        gunzip -c "$SQL_FILE" | mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"
        ;;
    *)
        mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$SQL_FILE"
        ;;
esac

if [ $? -eq 0 ]; then
    echo "Restore completed successfully!"
    echo "Database: $MYSQL_DATABASE"
else
    echo "Restore failed!"
    exit 1
fi
