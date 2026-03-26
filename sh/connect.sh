#!/bin/sh

# connect.sh - Quick connect to MariaDB database
# Usage: sh connect.sh [user]  OR  bash connect.sh  OR  ./connect.sh

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

. "$ENV_FILE"

# Determine user (default to MYSQL_USER, or use parameter)
if [ -n "$1" ]; then
    USER="$1"
else
    USER="$MYSQL_USER"
fi

if [ "$USER" = "root" ]; then
    PASSWORD="$MYSQL_ROOT_PASSWORD"
else
    PASSWORD="$MYSQL_PASSWORD"
fi

echo "================================================"
echo "Connecting to MariaDB"
echo "================================================"
echo "Database: $MYSQL_DATABASE"
echo "User: $USER"
echo "Host: 127.0.0.1:3306"
echo "================================================"
echo ""

# Connect to database
mysql -h 127.0.0.1 -P 3306 -u "$USER" -p"$PASSWORD" "$MYSQL_DATABASE"
