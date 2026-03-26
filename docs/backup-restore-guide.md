# Panduan Backup dan Restore Database MariaDB Docker

Dokumen ini berisi panduan lengkap untuk melakukan backup dan restore database MariaDB yang berjalan di Docker container.

## Informasi Docker Compose

Container MariaDB sudah dikonfigurasi dengan volume binding:
- `./backup` (host) → `/backup` (container)
- `./data` (host) → `/var/lib/mysql` (container)
- `./config` (host) → `/etc/mysql/conf.d` (container)
- `./logs` (host) → `/var/log/mysql` (container)

Container name: `mariadb-server`

## Kredensial Database

Lihat file `.env` untuk kredensial:
- Root Password: `${MYSQL_ROOT_PASSWORD}`
- User: `${MYSQL_USER}`
- Password: `${MYSQL_PASSWORD}`

---

## 📦 BACKUP DATABASE

### 1. Backup Satu Database

Dari **host machine**:

```bash
# Backup database tertentu
docker exec mariadb-server mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} nama_database > backup/dump-nama_database-$(date +%Y%m%d%H%M).sql

#jika pakai MariaDB
docker exec mariadb-server mariadb-dump -uroot -p${MYSQL_ROOT_PASSWORD} nama_database > backup/dump-nama_database-$(date +%Y%m%d%H%M).sql
```

Dari **dalam container**:

```bash
# Masuk ke container
docker exec -it mariadb-server bash

# Backup database
mysqldump -uroot -p nama_database > /backup/dump-nama_database-$(date +%Y%m%d%H%M).sql

#jika pakai MariaDB
mariadb-dump -uroot -p nama_database > /backup/dump-nama_database-$(date +%Y%m%d%H%M).sql
```

### 2. Backup Semua Database

Dari **host machine**:

```bash
# Backup semua database
docker exec mariadb-server mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} --all-databases > backup/dump-all-databases-$(date +%Y%m%d%H%M).sql

#jika pakai MariaDB
docker exec mariadb-server mariadb-dump -uroot -p${MYSQL_ROOT_PASSWORD} --all-databases > backup/dump-all-databases-$(date +%Y%m%d%H%M).sql
```

### 3. Backup Semua Database Secara Terpisah

Dari **host machine**:

```bash
# Backup setiap database ke file terpisah
docker exec mariadb-server mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)" | while read db; do
    echo "Backing up database: $db"
    docker exec mariadb-server mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} --databases $db > backup/dump-$db-$(date +%Y%m%d%H%M).sql
done
```

### 4. Backup dengan Kompresi (Hemat Space)

```bash
# Backup dan compress dengan gzip
docker exec mariadb-server mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} nama_database | gzip > backup/dump-nama_database-$(date +%Y%m%d%H%M).sql.gz
```

---

## 📥 RESTORE DATABASE

### 1. Restore Satu Database (Cara Mudah)

Dari **host machine**:

```bash
# Pastikan file backup ada di folder backup/
# Buat database dulu jika belum ada
docker exec -i mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS nama_database CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Restore database
docker exec -i mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD} nama_database < backup/dump-nama_database-202510250111.sql
```

### 2. Restore dari Dalam Container

```bash
# Masuk ke container
docker exec -it mariadb-server bash

# Navigasi ke folder backup
cd /backup

# Buat database
mariadb -uroot -p -e "CREATE DATABASE IF NOT EXISTS nama_database CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Restore database
mariadb -uroot -p nama_database < dump-nama_database-202510250111.sql

# Atau one-liner
mariadb -uroot -p -e "CREATE DATABASE IF NOT EXISTS nama_database;" && mariadb -uroot -p nama_database < dump-nama_database-202510250111.sql
```

### 3. Restore File yang Di-compress

```bash
# Dari host machine
gunzip < backup/dump-nama_database-202510250111.sql.gz | docker exec -i mariadb-server mysql -uroot -p${MYSQL_ROOT_PASSWORD} nama_database
```

### 4. Restore Semua Database Sekaligus

Jika Anda punya banyak file SQL di folder `database-backup`:

```bash
# Copy semua file ke folder backup yang sudah di-bind
cp database-backup/*.sql backup/

# Restore semua file
for file in backup/dump-*.sql; do
    # Extract nama database dari nama file
    # Contoh: dump-dolarindo-202510250111.sql -> dolarindo
    dbname=$(basename "$file" | sed 's/dump-//' | sed 's/-[0-9]*.sql//')
    
    echo "Restoring database: $dbname from $file"
    
    # Buat database
    docker exec -i mariadb-server mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS $dbname CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    # Restore
    docker exec -i mariadb-server mysql -uroot -p${MYSQL_ROOT_PASSWORD} $dbname < "$file"
done
```

---

## 🔧 TROUBLESHOOTING

### Error: "No database selected"

**Penyebab**: File SQL tidak memiliki `USE database_name;` di dalamnya.

**Solusi**: Specify nama database saat restore:
```bash
mysql -uroot -p nama_database < backup_file.sql
```

### Error: "Access denied"

**Penyebab**: Password salah atau user tidak punya permission.

**Solusi**: 
- Gunakan root user: `-uroot -p${MYSQL_ROOT_PASSWORD}`
- Atau masuk interaktif dan input password manual: `-uroot -p`

### File Backup Terlalu Besar

**Solusi**: Gunakan kompresi dengan gzip atau split file:
```bash
# Backup dengan kompresi
docker exec mariadb-server mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} nama_database | gzip > backup/dump.sql.gz

# Split file besar
split -b 100M backup/dump-large.sql backup/dump-large-part-
```

---

## 📝 TIPS & BEST PRACTICES

1. **Gunakan Timestamp**: Selalu gunakan timestamp di nama file backup untuk tracking
   ```bash
   $(date +%Y%m%d%H%M)
   ```

2. **Automasi Backup**: Buat cron job untuk backup otomatis:
   ```bash
   # Edit crontab
   crontab -e
   
   # Backup setiap hari jam 2 pagi
   0 2 * * * docker exec mariadb-server mysqldump -uroot -pYOUR_PASSWORD --all-databases > /path/to/backup/dump-all-$(date +\%Y\%m\%d).sql
   ```

3. **Cleanup Old Backups**: Hapus backup lama untuk hemat space:
   ```bash
   # Hapus backup lebih dari 30 hari
   find backup/ -name "dump-*.sql" -mtime +30 -delete
   ```

4. **Verify Backup**: Selalu test restore di environment development sebelum production

5. **Character Set**: Gunakan utf8mb4 untuk support emoji dan karakter khusus:
   ```sql
   CREATE DATABASE nama_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   ```

---

## 🚀 QUICK REFERENCE

### Backup Single Database
```bash
docker exec mariadb-server mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} dbname > backup/dbname.sql
```

### Restore Single Database
```bash
docker exec -i mariadb-server mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS dbname;"
docker exec -i mariadb-server mysql -uroot -p${MYSQL_ROOT_PASSWORD} dbname < backup/dbname.sql
```

### List All Databases
```bash
docker exec -i mariadb-server mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;"
```

### Access MariaDB Shell
```bash
docker exec -it mariadb-server mysql -uroot -p${MYSQL_ROOT_PASSWORD}
```

---

## 🧰 INTERACTIVE CLI (Backup/Restore via Docker Container)

Jika kamu ingin proses **backup/restore yang interaktif** (pilih satu per satu) dan semua operasi dilakukan dengan **akses ke container** menggunakan `docker exec`, kamu bisa pakai script:

- Script: `sh/mdb-docker-cli.sh`
- Default container: `mariadb-server`
- Output backup: folder `backup/` (sesuai bind mount host → container)

### Cara Menjalankan

Dari root project `mariadb/`:

```bash
sh sh/mdb-docker-cli.sh
```

### Persyaratan Kredensial (WAJIB)

Sebelum menu muncul, kamu harus memasukkan:
1. Nama container (default: `mariadb-server`)
2. Username MariaDB
3. Password MariaDB

Tanpa input username & password, aplikasi tidak akan menjalankan operasi backup/restore.

### Fitur yang Tersedia di Menu

- List database (exclude system schemas)
- Backup single database (otomatis timestamp + gzip)
- Backup semua database (single file)
- Backup setiap database terpisah
- Restore single file (`.sql` / `.sql.gz`) ke database tertentu
  - otomatis `CREATE DATABASE IF NOT EXISTS ...`
- Restore banyak file dengan konfirmasi satu per satu

---

## 📂 Struktur Folder

```
mariadb/
├── backup/           # Folder untuk backup (bind ke /backup di container)
├── data/            # Data MariaDB
├── config/          # Konfigurasi MariaDB
├── logs/            # Log files
├── docs/            # Dokumentasi (file ini)
├── docker-compose.yml
└── .env             # Environment variables (kredensial)
```

---

**Dibuat**: $(date +%Y-%m-%d)  
**Container**: mariadb-server  
**Image**: mariadb:lts
