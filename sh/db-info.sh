#!/bin/sh

# db-info.sh - Display MariaDB database information
# Usage: sh db-info.sh  OR  bash db-info.sh  OR  ./db-info.sh

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

. "$ENV_FILE"

echo "================================================"
echo "MariaDB Database Information"
echo "================================================"
echo ""

# Connection info
echo "Connection Information:"
echo "  Host: 127.0.0.1"
echo "  Port: 3306"
echo "  Database: $MYSQL_DATABASE"
echo "  User: $MYSQL_USER"
echo ""

# Container status
echo "Container Status:"
docker ps --filter name=mariadb-server --format "  Name: {{.Names}}\n  Status: {{.Status}}\n  Image: {{.Image}}"
echo ""

# Database list
echo "Databases:"
mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database" | sed 's/^/  - /'
echo ""

# Table count in current database
echo "Tables in $MYSQL_DATABASE:"
TABLE_COUNT=$(mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -D "$MYSQL_DATABASE" -e "SHOW TABLES;" 2>/dev/null | grep -v "Tables_in_" | wc -l)
echo "  Total tables: $TABLE_COUNT"
echo ""

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo "  Tables:"
    mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -D "$MYSQL_DATABASE" -e "SHOW TABLES;" 2>/dev/null | grep -v "Tables_in_" | sed 's/^/    - /'
    echo ""
fi

# Database size
echo "Database Size:"
mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "
    SELECT
        table_schema AS 'Database',
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables
    WHERE table_schema = '$MYSQL_DATABASE'
    GROUP BY table_schema;
" 2>/dev/null | tail -n +2 | sed 's/^/  /'
echo ""

# MariaDB version
echo "MariaDB Version:"
mysql -h 127.0.0.1 -P 3306 -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT VERSION();" 2>/dev/null | tail -n +2 | sed 's/^/  /'
echo ""

# Volume info
echo "Volume Directories:"
echo "  Data: $(du -sh ../data 2>/dev/null | cut -f1) (./data)"
echo "  Backup: $(du -sh ../backup 2>/dev/null | cut -f1) (./backup)"
echo "  Database-backup: $(du -sh ../database-backup 2>/dev/null | cut -f1) (./database-backup)"
echo "  Logs: $(du -sh ../logs 2>/dev/null | cut -f1) (./logs)"
echo ""

echo "================================================"
