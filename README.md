# MariaDB LTS - Docker Setup

MariaDB LTS server berjalan di Docker, bind ke `127.0.0.1:3306` (localhost only).

## Struktur Folder

```
mariadb/
├── docker-compose.yml
├── .env                  # konfigurasi database (jangan di-commit)
├── .env.example          # template konfigurasi
├── config/               # custom MariaDB config (.cnf files)
├── sh/                   # utility scripts (backup, restore, connect, db-info)
├── docs/                 # dokumentasi lengkap backup & restore
├── data/                 # data MariaDB, mount ke /var/lib/mysql (auto-generated, gitignored)
├── logs/                 # log MariaDB (gitignored)
├── backup/               # hasil backup (gitignored)
└── database-backup/      # file SQL untuk batch restore (gitignored)
```

---

## Menjalankan Pertama Kali

### 1. Buat file `.env`

```bash
cp .env.example .env
```

Edit `.env` sesuai kebutuhan:

```env
MYSQL_ROOT_PASSWORD=passwordroot
MYSQL_DATABASE=app_database
MYSQL_USER=userkamu
MYSQL_PASSWORD=passwordkamu
```

### 2. Jalankan container

```bash
docker compose up -d
```

### 3. Cek apakah sudah berjalan

```bash
docker compose ps
```

Output yang diharapkan:

```
NAME             IMAGE        COMMAND                  SERVICE    STATUS
mariadb-server   mariadb:lts  "docker-entrypoint.s…"   mariadb    Up ... (healthy)
```

### 4. Cek log jika ada masalah

```bash
docker compose logs -f mariadb
```

---

## Operasi Sehari-hari

### Start / Stop / Restart

```bash
docker compose up -d        # start
docker compose down          # stop (data tetap aman di ./data)
docker compose restart       # restart
```

### Lihat Log

```bash
docker compose logs -f mariadb          # follow log
docker compose logs --tail 100 mariadb  # 100 baris terakhir
```

### Lihat Info Database

```bash
sh sh/db-info.sh
```

Menampilkan: daftar database, jumlah tabel, ukuran database, versi MariaDB, dan status container.

---

## Akses Terminal (mariadb client)

### Via script (dari host)

```bash
sh sh/connect.sh             # login sebagai MYSQL_USER
sh sh/connect.sh root        # login sebagai root
```

### Via docker exec (masuk ke dalam container)

```bash
# Masuk ke bash container
docker exec -it mariadb-server bash

# Atau langsung masuk mariadb client di dalam container
docker exec -it mariadb-server mariadb -u root -p
```

### Via mariadb client langsung (dari host)

Pastikan `mariadb-client` sudah terinstall di host:

```bash
# Install (Debian/Ubuntu)
sudo apt install mariadb-client

# Connect
mariadb -h 127.0.0.1 -P 3306 -u userkamu -p app_database
```

---

## Akses via DBeaver

1. Buka DBeaver → **Database** → **New Database Connection**
2. Pilih **MariaDB**
3. Isi connection:

| Field    | Value          |
|----------|----------------|
| Host     | `127.0.0.1`    |
| Port     | `3306`         |
| Database | `app_database` |
| Username | *(lihat .env)* |
| Password | *(lihat .env)* |

4. Klik **Test Connection** → pastikan "Connected"
5. Klik **Finish**

> Jika diminta download driver, klik **Download** dan tunggu selesai.

---

## Backup

### Backup satu database (via script)

```bash
sh sh/backup.sh              # output ke ./backup/
sh sh/backup.sh /tmp/mybackup  # output ke folder custom
```

Hasil: `backup_app_database_20260211_143000.sql.gz`

### Backup manual via docker exec

```bash
# Backup satu database
docker exec mariadb-server mariadb-dump -uroot -p${MYSQL_ROOT_PASSWORD} \
    app_database > backup/dump-app_database-$(date +%Y%m%d%H%M).sql

# Backup dengan kompresi
docker exec mariadb-server mariadb-dump -uroot -p${MYSQL_ROOT_PASSWORD} \
    app_database | gzip > backup/dump-app_database-$(date +%Y%m%d%H%M).sql.gz

# Backup semua database
docker exec mariadb-server mariadb-dump -uroot -p${MYSQL_ROOT_PASSWORD} \
    --all-databases > backup/dump-all-$(date +%Y%m%d%H%M).sql
```

### Interactive CLI (backup/restore via menu)

```bash
sh sh/mdb-docker-cli.sh
```

Menyediakan menu interaktif untuk backup/restore per database. Lihat `docs/backup-restore-guide.md` untuk panduan lengkap.

---

## Restore

### Restore satu file SQL (via script)

```bash
sh sh/restore.sh database-backup/mydump.sql
sh sh/restore.sh backup/backup_app_database_20260211_143000.sql.gz
```

Script mendukung file `.sql` dan `.sql.gz`.

### Restore manual

```bash
# Buat database dulu jika belum ada
docker exec -i mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD} \
    -e "CREATE DATABASE IF NOT EXISTS app_database CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Restore file .sql
docker exec -i mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD} \
    app_database < backup/dump-app_database.sql

# Restore file .sql.gz
gunzip < backup/dump-app_database.sql.gz | \
    docker exec -i mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD} app_database
```

### Batch restore (semua file ke satu database)

Taruh file SQL di `database-backup/`, lalu:

```bash
sh sh/restore-all.sh
```

### Batch restore (setiap file jadi database terpisah)

Taruh file SQL dengan format nama `dump-<nama_db>-<timestamp>.sql` di `database-backup/`, lalu:

```bash
sh sh/restore-all-databases.sh
```

---

## Membuat Database Baru untuk Project

### Quick Command

```bash
docker exec -it mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD}
```

Lalu jalankan SQL berikut (ganti nama database & user sesuai project):

```sql
-- 1. Buat database
CREATE DATABASE nama_project CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 2. (Opsional) Buat user khusus untuk project
CREATE USER 'nama_project_user'@'%' IDENTIFIED BY 'passwordnya';

-- 3. Berikan akses penuh ke database tersebut
GRANT ALL PRIVILEGES ON nama_project.* TO 'nama_project_user'@'%';

FLUSH PRIVILEGES;
```

> Bisa juga pakai MYSQL_USER untuk semua project (tanpa step 2-3), tapi user terpisah lebih aman — setiap project hanya bisa akses database-nya sendiri.

---

### Contoh per Framework

#### Laravel

```bash
# Buat database
docker exec -i mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD} \
    -e "CREATE DATABASE myapp_laravel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

`.env` di project Laravel:

```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=myapp_laravel
DB_USERNAME=userkamu
DB_PASSWORD=passwordkamu
```

Lalu jalankan migration:

```bash
php artisan migrate
```

---

#### Golang

```bash
# Buat database
docker exec -i mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD} \
    -e "CREATE DATABASE myapp_go CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

Connection string di project Golang:

```go
// database/sql + go-sql-driver/mysql
dsn := "userkamu:passwordkamu@tcp(127.0.0.1:3306)/myapp_go?charset=utf8mb4&parseTime=True&loc=Local"

// GORM
dsn := "userkamu:passwordkamu@tcp(127.0.0.1:3306)/myapp_go?charset=utf8mb4&parseTime=True&loc=Local"
db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})
```

`.env` di project Golang:

```env
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=userkamu
DB_PASSWORD=passwordkamu
DB_NAME=myapp_go
```

---

#### NestJS (TypeORM / Prisma)

```bash
# Buat database
docker exec -i mariadb-server mariadb -uroot -p${MYSQL_ROOT_PASSWORD} \
    -e "CREATE DATABASE myapp_nestjs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

**TypeORM** — `.env` di project NestJS:

```env
DB_TYPE=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USERNAME=userkamu
DB_PASSWORD=passwordkamu
DB_DATABASE=myapp_nestjs
```

**Prisma** — `DATABASE_URL` di `.env`:

```env
DATABASE_URL="mysql://userkamu:passwordkamu@127.0.0.1:3306/myapp_nestjs"
```

Lalu jalankan migration:

```bash
# TypeORM
npx typeorm migration:run

# Prisma
npx prisma migrate dev
```

---

### Tips

- **Naming convention**: gunakan prefix/suffix project, misal `myapp_go`, `myapp_laravel`, `myapp_nestjs`
- **Cek daftar database**: `sh sh/db-info.sh` atau `SHOW DATABASES;` di dalam mariadb client
- **Hapus database**: `DROP DATABASE nama_project;` (hati-hati, tidak bisa di-undo)
- **Jika project pakai Docker juga** (misal Laravel Sail), gunakan `host.docker.internal` sebagai host, bukan `127.0.0.1`, atau hubungkan ke network `mariadb-network`

---

## Catatan Penting

- Port hanya bind ke `127.0.0.1` — tidak bisa diakses dari luar server. Jika butuh akses remote, ubah ke `0.0.0.0:3306:3306` (pastikan firewall dikonfigurasi).
- Data tersimpan di `./data/`. Selama folder ini tidak dihapus, `docker compose down` dan `docker compose up -d` tidak akan menghapus data.
- Character set dikonfigurasi ke `utf8mb4` dengan collation `utf8mb4_unicode_ci` — mendukung emoji dan karakter Asia.
- Binary logging diaktifkan (`--log-bin=mysql-bin`, format ROW) — expire otomatis setelah 7 hari.
- Slow query log aktif untuk query > 2 detik, disimpan di `./logs/slow.log`.
- `mariadb-dump` adalah nama baru dari `mysqldump` di MariaDB — keduanya bisa digunakan dan menghasilkan output yang sama.
