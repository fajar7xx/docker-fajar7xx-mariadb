# MariaDB Helper Scripts

Collection of portable shell scripts to manage MariaDB database backup, restore, and administration.

**✅ Portable & Compatible:**
- Works on any system (Linux, macOS, WSL, servers)
- POSIX-compliant - works with sh, bash, zsh, dash
- Multiple ways to run: `sh script.sh`, `bash script.sh`, or `./script.sh`
- No `chmod +x` required if using `sh` or `bash` prefix
- Portable across different machines and servers

## 📁 Directory Structure

```
mariadb/
├── sh/                    # Helper scripts
│   ├── backup.sh         # Backup database
│   ├── restore.sh        # Restore single SQL file
│   ├── restore-all.sh    # Restore all SQL files
│   ├── mdb-docker-cli.sh # Interactive Docker-based backup/restore CLI
│   ├── connect.sh        # Connect to database
│   └── db-info.sh        # Display database information
├── database-backup/       # Place your SQL files here for restore
├── backup/               # Backup output directory
├── data/                 # MariaDB data (persistent)
├── logs/                 # MariaDB logs
└── .env                  # Environment variables

```

## 🚀 Available Scripts

### 1. backup.sh - Database Backup

Backup database with compression and timestamp.

**Usage:**
```bash
bash sh/backup.sh [output_directory]
```

**Examples:**
```bash
# Backup to default directory (./backup)
bash sh/backup.sh

# Backup to custom directory
bash sh/backup.sh /path/to/custom/backup
```

**Output:**
- Creates compressed backup: `backup_[database]_[timestamp].sql.gz`
- Includes routines, triggers, and events

---

### 2. restore.sh - Restore Single SQL File

Restore a single SQL file to the database.

**Usage:**
```bash
bash sh/restore.sh <sql_file>
```

**Examples:**
```bash
# Restore from database-backup folder
bash sh/restore.sh database-backup/mydatabase.sql

# Restore compressed file
bash sh/restore.sh database-backup/mydatabase.sql.gz

# Restore from backup folder
bash sh/restore.sh backup/backup_app_database_20251026.sql.gz
```

**Features:**
- Supports both `.sql` and `.sql.gz` files
- Shows file size before restore
- Confirmation prompt before restore
- Error handling

---

### 3. restore-all.sh - Batch Restore

Restore all SQL files from `database-backup` folder.

**Usage:**
```bash
bash sh/restore-all.sh
```

**Features:**
- Automatically finds all `.sql` and `.sql.gz` files in `database-backup/`
- Shows list of files before restore
- Processes files in alphabetical order
- Summary report (success/failed count)
- Confirmation prompt

**Example Output:**
```
================================================
🔄 MariaDB Batch Restore
================================================
📁 Backup Directory: ../database-backup
🗄️  Target Database: app_database
📊 Files Found: 3
================================================

Files to restore:
  1. database1.sql (2.5M)
  2. database2.sql.gz (1.2M)
  3. database3.sql (890K)

================================================

⚠️  This will restore all files. Continue? (y/n):
```

---

### 4. connect.sh - Quick Database Connection

Connect to MariaDB database instantly.

**Usage:**
```bash
./sh/connect.sh [user]
```

**Examples:**
```bash
# Connect as default user (from .env)
./sh/connect.sh

# Connect as root
./sh/connect.sh root
```

**Tips:**
- Type `exit` or press `Ctrl+D` to disconnect
- Use SQL commands directly after connection

---

### 5. db-info.sh - Database Information

Display comprehensive database information.

**Usage:**
```bash
./sh/db-info.sh
```

**Shows:**
- Connection information
- Container status
- List of databases
- Tables in current database
- Database size
- MariaDB version
- Volume directory sizes

**Example Output:**
```
================================================
📊 MariaDB Database Information
================================================

🔌 Connection Information:
  Host: 127.0.0.1
  Port: 3306
  Database: app_database
  User: fajarsiagian

🐳 Container Status:
  Name: mariadb-server
  Status: Up 2 hours (healthy)
  Image: mariadb:lts

🗄️  Databases:
  - app_database
  - information_schema

📋 Tables in app_database:
  Total tables: 15

💾 Database Size:
  app_database  45.23 MB

🔖 MariaDB Version:
  11.8.3-MariaDB
```

---

### 6. mdb-docker-cli.sh - Interactive Docker Backup/Restore CLI

Interactive menu untuk backup/restore **via `docker exec` ke container** (sesuai panduan di `docs/backup-restore-guide.md`).

**Wajib:** sebelum menu muncul, kamu harus memasukkan:
- Nama container (default: `mariadb-server`)
- Username MariaDB
- Password MariaDB

Password tidak disimpan di file dan tidak diambil dari `.env` — harus diinput agar operasi dapat berjalan.

**Usage:**
```bash
sh sh/mdb-docker-cli.sh
```

**Fitur Menu:**
- List databases (exclude system schemas)
- Backup single database (output ke `./backup/` + gzip)
- Backup all databases (single file)
- Backup setiap database terpisah
- Restore single file (`.sql` / `.sql.gz`) ke database tertentu (auto `CREATE DATABASE IF NOT EXISTS`)
- Restore banyak file dengan konfirmasi satu per satu

**Catatan:**
- File backup disimpan di folder `backup/` (host) sesuai bind mount `/backup` di container.
- Nama database yang didukung untuk input aman: huruf/angka/underscore.

---

## 🎯 Quick Start

### Initial Setup

1. Ensure MariaDB container is running:
```bash
docker ps | grep mariadb
```

2. Place SQL files in `database-backup/` folder:
```bash
cp /path/to/your/dump.sql database-backup/
```

### Common Tasks

**3 ways to run scripts:**
```bash
# Method 1: Using sh (recommended - most portable)
sh sh/restore-all.sh

# Method 2: Using bash
bash sh/restore-all.sh

# Method 3: Direct execution (requires chmod +x first)
chmod +x sh/*.sh  # Only needed once
./sh/restore-all.sh
```

**Restore all SQL files:**
```bash
cd /home/fajarsiagian/docker-apps/mariadb
sh sh/restore-all.sh
```

**Restore single file:**
```bash
sh sh/restore.sh database-backup/mydatabase.sql
```

**Create backup:**
```bash
sh sh/backup.sh
```

**Check database:**
```bash
sh sh/db-info.sh
```

**Connect to database:**
```bash
sh sh/connect.sh
```

---

## 📝 Notes

- All scripts read credentials from `.env` file
- Backup files are automatically compressed with gzip
- Restore scripts support both compressed and uncompressed SQL files
- All scripts have error handling and confirmation prompts
- Scripts can be run from any directory (they auto-detect paths)

---

## 🔒 Security

- Never commit `.env` file to git
- Keep database passwords secure
- Use strong passwords (16+ characters)
- Port is bound to localhost only (127.0.0.1:3306)

---

## 🐛 Troubleshooting

**"Connection refused"**
- Check if container is running: `docker ps`
- Check port binding: `docker port mariadb-server`

**"Permission denied"**
- Ensure scripts are executable: `chmod +x sh/*.sh`

**"File not found"**
- Check file path
- Use absolute or relative paths correctly

**"Access denied"**
- Verify credentials in `.env` file
- Try with root user: `./sh/connect.sh root`

---

## 📖 References

- [MariaDB Documentation](https://mariadb.org/documentation/)
- [MySQL Command-Line Tools](https://dev.mysql.com/doc/refman/8.0/en/programs-client.html)

---

Created: 2025-10-26
