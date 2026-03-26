#!/bin/sh
#
# mdb-docker-cli.sh - Interactive MariaDB Docker backup/restore CLI
#
# Goals:
# - Interactive menu for backup/restore (one-by-one) via `docker exec` into container.
# - Username + password MUST be entered first before any DB operation runs.
# - Avoid exposing password in process args: password is passed via STDIN (first line),
#   then the remaining STDIN (if any) is used for SQL restore.
#
# Notes:
# - Default container name: mariadb-server
# - Uses bind-mounted host folder: ../backup  (container: /backup) as per docs
#
# Run:
#   sh mariadb/sh/mdb-docker-cli.sh
#   sh sh/mdb-docker-cli.sh   (if you're already in project root)
#

# -----------------------------
# Basic utilities
# -----------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_CONTAINER="mariadb-server"
BACKUP_DIR="$PROJECT_DIR/backup"
DATABASE_BACKUP_DIR="$PROJECT_DIR/database-backup"

# Restore file discovery will search both directories (host paths), including subfolders.
# It looks for *.sql and *.sql.gz anywhere under BACKUP_DIR or DATABASE_BACKUP_DIR.
RESTORE_SEARCH_DIRS="$BACKUP_DIR $DATABASE_BACKUP_DIR"

say() { printf "%s\n" "$*"; }
die() { printf "Error: %s\n" "$*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

relpath_from_project() {
    # Print a nice relative path for display when possible.
    p="$1"
    case "$p" in
        "$PROJECT_DIR"/*) echo "${p#$PROJECT_DIR/}" ;;
        *) echo "$p" ;;
    esac
}

dump_to_file_with_progress() {
    # Dump SQL from container to a file on host.
    # Uses `pv` for progress/throughput when available, while still preserving
    # the real exit status of the dump command (POSIX sh friendly).
    #
    # Usage:
    #   dump_to_file_with_progress "/path/out.sql" --databases mydb
    out="$1"
    shift

    outdir="$(dirname "$out")"
    mkdir -p "$outdir" 2>/dev/null || die "Failed to create output dir: $outdir"

    rm -f "$out" >/dev/null 2>&1 || true

    if has_cmd pv; then
        need_cmd mkfifo

        fifo="${out}.fifo.$$"
        rm -f "$fifo" >/dev/null 2>&1 || true

        mkfifo "$fifo" || die "Failed to create fifo: $fifo"

        # pv reads from fifo and writes to the final file (more informative progress display)
        ( pv -ptebar -N "dump" < "$fifo" > "$out" ) &
        pvpid=$!

        # dump writes into fifo; capture real exit status
        if printf '%s\n' "$DB_PASS" | docker_dump_exec "$@" > "$fifo"; then
            dump_status=0
        else
            dump_status=$?
        fi

        # Wait for pv to finish draining the fifo
        wait "$pvpid"
        pv_status=$?

        rm -f "$fifo" >/dev/null 2>&1 || true

        if [ "$dump_status" -eq 0 ] && [ "$pv_status" -eq 0 ]; then
            return 0
        fi

        rm -f "$out" >/dev/null 2>&1 || true
        return 1
    fi

    # Fallback: no progress bar
    if printf '%s\n' "$DB_PASS" | docker_dump_exec "$@" > "$out"; then
        return 0
    fi

    rm -f "$out" >/dev/null 2>&1 || true
    return 1
}

pick_backup_output_dir() {
    # Backups are saved ONLY under DATABASE_BACKUP_DIR.
    # Default is: database-backup/YYYYMMDD/file-backup/
    # Sets BACKUP_OUT_DIR (absolute path).
    BACKUP_OUT_DIR=""

    ensure_backup_dir

    default_day="$(date +%Y%m%d)"
    default_sub="$default_day/file-backup"

    say ""
    say "Default backup folder: database-backup/$default_sub/"
    prompt_default "Backup folder (relative to database-backup/)" "$default_sub"
    sub="$REPLY"

    [ -n "$sub" ] || die "Folder name is required."

    # Basic safety: disallow absolute paths, parent traversal, and odd path patterns
    case "$sub" in
        /*) die "Invalid folder: must be relative (do not start with /)." ;;
        *".."*) die "Invalid folder: must not contain '..'." ;;
        *"//"*) die "Invalid folder: must not contain '//'." ;;
        */) die "Invalid folder: must not end with '/'." ;;
        *\\*) die "Invalid folder: must not contain backslashes." ;;
    esac

    outdir="$DATABASE_BACKUP_DIR/$sub"
    mkdir -p "$outdir" || die "Failed to create folder: $outdir"
    BACKUP_OUT_DIR="$outdir"
    return 0
}

pick_backup_output_format() {
    # Choose output format for backup.
    # Sets BACKUP_FORMAT to: "sql" or "sql.gz"
    BACKUP_FORMAT=""

    say ""
    say "Backup output format:"
    say "  1) .sql.gz (compressed, recommended)"
    say "  2) .sql    (plain text)"
    say ""

    prompt_default "Select format" "1"
    choice="$REPLY"

    case "$choice" in
        1) BACKUP_FORMAT="sql.gz" ;;
        2) BACKUP_FORMAT="sql" ;;
        *) die "Invalid selection." ;;
    esac

    if [ "$BACKUP_FORMAT" = "sql.gz" ] && ! has_cmd gzip; then
        say "Info: 'gzip' not found; falling back to .sql output."
        say "Install: sudo apt-get update && sudo apt-get install -y gzip"
        BACKUP_FORMAT="sql"
    fi
}

stream_restore_sql() {
    # Stream SQL content to STDOUT for restore. Uses `pv` for a progress bar when available.
    # For .sql, we can reliably show a full progress bar using the file size.
    # For .gz, we try to use `gzip -l` to get the uncompressed size (best effort).
    file="$1"

    case "$file" in
        *.gz)
            need_cmd gunzip
            if has_cmd pv; then
                usize=""
                if has_cmd gzip; then
                    usize="$(gzip -l "$file" 2>/dev/null | awk 'NR==2 {print $2}' || true)"
                fi

                if echo "$usize" | grep -Eq '^[0-9]+$' && [ "$usize" -gt 0 ] 2>/dev/null; then
                    gunzip -c "$file" | pv -s "$usize"
                else
                    gunzip -c "$file" | pv
                fi
            else
                gunzip -c "$file"
            fi
            ;;
        *)
            if has_cmd pv; then
                bytes="$(wc -c < "$file" 2>/dev/null | tr -d ' ' || true)"
                if echo "$bytes" | grep -Eq '^[0-9]+$' && [ "$bytes" -gt 0 ] 2>/dev/null; then
                    pv -s "$bytes" "$file"
                else
                    pv "$file"
                fi
            else
                cat "$file"
            fi
            ;;
    esac
}

prompt() {
    # prompt "Message" -> prints and reads into REPLY
    #
    # Keep prompts interactive even when caller is running inside a pipeline
    # (e.g. `echo "$files" | while read ...; do prompt ...; done`).
    printf "%s" "$1"
    if [ -r /dev/tty ] && [ ! -t 0 ]; then
        IFS= read -r REPLY </dev/tty
    else
        IFS= read -r REPLY
    fi
}

prompt_default() {
    # prompt_default "Message" "default" -> sets REPLY
    msg="$1"
    def="$2"
    printf "%s [%s]: " "$msg" "$def"
    if [ -r /dev/tty ] && [ ! -t 0 ]; then
        IFS= read -r REPLY </dev/tty
    else
        IFS= read -r REPLY
    fi
    if [ -z "$REPLY" ]; then
        REPLY="$def"
    fi
}

prompt_yes_no() {
    # prompt_yes_no "Message" -> returns 0 if yes, 1 if no
    msg="$1"
    while :; do
        printf "%s (y/n): " "$msg"
        if [ -r /dev/tty ] && [ ! -t 0 ]; then
            IFS= read -r yn </dev/tty
        else
            IFS= read -r yn
        fi
        case "$yn" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) say "Please answer y or n." ;;
        esac
    done
}

prompt_secret() {
    # prompt_secret "Message" -> sets REPLY (tries to hide input if possible)
    msg="$1"

    # If stty exists and stdin is a TTY, hide input
    if command -v stty >/dev/null 2>&1 && [ -t 0 ]; then
        printf "%s" "$msg"
        old_stty="$(stty -g 2>/dev/null || true)"
        stty -echo 2>/dev/null || true
        IFS= read -r REPLY
        stty "$old_stty" 2>/dev/null || true
        printf "\n"
    else
        # Fallback (not hidden)
        prompt "$msg"
    fi
}

is_safe_db_name() {
    # allow only letters, numbers, underscore to avoid SQL injection/quoting issues
    # return 0 if safe
    echo "$1" | grep -Eq '^[A-Za-z0-9_]+$'
}

hr() { say "================================================"; }

# -----------------------------
# Docker + MariaDB helpers
# -----------------------------

CONTAINER=""
DB_USER=""
DB_PASS=""
DUMP_BIN=""

check_container_running() {
    # Ensure docker is available and container exists/running
    need_cmd docker

    # If container not found or not running, show useful error
    if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
        die "Container not found: $CONTAINER"
    fi

    running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)"
    if [ "$running" != "true" ]; then
        die "Container is not running: $CONTAINER"
    fi
}

detect_dump_binary() {
    # Prefer mariadb-dump if present; fallback to mysqldump
    # This does NOT require DB creds.
    if docker exec "$CONTAINER" sh -c 'command -v mariadb-dump >/dev/null 2>&1' >/dev/null 2>&1; then
        DUMP_BIN="mariadb-dump"
    else
        DUMP_BIN="mysqldump"
    fi
}

docker_mariadb_exec() {
    # Run mariadb client inside container using password from stdin (first line).
    #
    # Contract:
    # - First line of STDIN is the password (required).
    # - Remaining STDIN (if any) is passed through to `mariadb` (for restores).
    # - If a database name is provided, it is appended AFTER all options/args.
    #
    # Usage:
    #   printf '%s\n' "$DB_PASS" | docker_mariadb_exec "" -e "SHOW DATABASES;"
    #   (printf '%s\n' "$DB_PASS"; cat file.sql) | docker_mariadb_exec "mydb"
    #
    db="$1"
    shift

    if [ -n "$db" ]; then
        docker exec -i "$CONTAINER" sh -c '
            read -r P
            export MYSQL_PWD="$P"
            USER="$1"
            DB="$2"
            shift 2
            exec mariadb -u "$USER" "$@" "$DB"
        ' sh "$DB_USER" "$db" "$@"
    else
        docker exec -i "$CONTAINER" sh -c '
            read -r P
            export MYSQL_PWD="$P"
            USER="$1"
            shift
            exec mariadb -u "$USER" "$@"
        ' sh "$DB_USER" "$@"
    fi
}

docker_dump_exec() {
    # Run dump binary inside container using password from stdin (first line)
    # Usage:
    #   printf '%s\n' "$DB_PASS" | docker_dump_exec --databases mydb
    #
    docker exec -i "$CONTAINER" sh -c '
        read -r P
        export MYSQL_PWD="$P"
        DUMP_BIN="$1"
        USER="$2"
        shift 2
        exec "$DUMP_BIN" -u "$USER" "$@"
    ' sh "$DUMP_BIN" "$DB_USER" "$@"
}

test_credentials() {
    # Quick sanity check: run SELECT 1
    # Return 0 if OK, else 1.
    out="$(printf '%s\n' "$DB_PASS" | docker_mariadb_exec "" -N -s -e "SELECT 1;" 2>/dev/null || true)"
    [ "$out" = "1" ]
}

list_databases() {
    # Print non-system databases, one per line
    # Uses SQL instead of grep for better correctness.
    printf '%s\n' "$DB_PASS" | docker_mariadb_exec "" -N -s -e "
        SELECT schema_name
        FROM information_schema.schemata
        WHERE schema_name NOT IN ('information_schema','performance_schema','mysql','sys')
        ORDER BY schema_name;
    "
}

ensure_backup_dir() {
    # Backups are stored only under DATABASE_BACKUP_DIR (not BACKUP_DIR).
    mkdir -p "$DATABASE_BACKUP_DIR" || die "Failed to create backup dir: $DATABASE_BACKUP_DIR"
}

timestamp() {
    date +%Y%m%d%H%M%S
}

# -----------------------------
# UI / Actions
# -----------------------------

action_list_databases() {
    hr
    say "List Databases (excluding system schemas)"
    hr

    if ! test_credentials; then
        die "Access denied or unable to connect with provided credentials."
    fi

    dbs="$(list_databases 2>/dev/null || true)"
    if [ -z "$dbs" ]; then
        say "(No user databases found, or you don't have privileges to list them.)"
        return 0
    fi

    echo "$dbs" | awk '{printf " - %s\n", $0}'
}

action_backup_single_db() {
    hr
    say "Backup: Single Database"
    hr

    if ! test_credentials; then
        die "Access denied or unable to connect with provided credentials."
    fi

    ensure_backup_dir

    if ! has_cmd pv; then
        say "Info: Install 'pv' for progress bar during backup:"
        say "  sudo apt-get update && sudo apt-get install -y pv"
        say ""
    fi
    if ! has_cmd gzip; then
        say "Info: Install 'gzip' to save compressed backups (.sql.gz):"
        say "  sudo apt-get update && sudo apt-get install -y gzip"
        say ""
    fi

    say "Available databases:"
    dbs="$(list_databases 2>/dev/null || true)"
    if [ -z "$dbs" ]; then
        die "No databases found (or insufficient privileges to list)."
    fi

    echo "$dbs" | awk '{printf "  %d) %s\n", NR, $0}'
    say ""

    prompt "Select database number: "
    choice="$REPLY"
    echo "$choice" | grep -Eq '^[0-9]+$' || die "Invalid selection."

    db="$(echo "$dbs" | awk -v n="$choice" 'NR==n {print; exit}')"
    [ -n "$db" ] || die "Selection out of range."

    if ! is_safe_db_name "$db"; then
        die "Unsupported database name. Use only letters, numbers, and underscore."
    fi

    pick_backup_output_dir
    out_dir="$BACKUP_OUT_DIR"

    pick_backup_output_format
    fmt="$BACKUP_FORMAT"

    out_base="$out_dir/dump-${db}-$(timestamp).sql"
    out="$out_base"
    out_gz="${out_base}.gz"

    if [ "$fmt" = "sql.gz" ]; then
        out_final="$out_gz"
    else
        out_final="$out"
    fi

    say ""
    say "Dump binary : $DUMP_BIN"
    say "Save folder : $(relpath_from_project "$out_dir")/"
    say "Output file : $(relpath_from_project "$out_final")"
    say ""

    if ! prompt_yes_no "Proceed with backup?"; then
        say "Cancelled."
        return 0
    fi

    # Dump to .sql first to reliably capture exit status, while showing progress if pv exists.
    if dump_to_file_with_progress "$out" --single-transaction --routines --triggers --events --databases "$db"; then
        if [ "$fmt" = "sql.gz" ]; then
            if gzip -f "$out"; then
                size="$(du -h "$out_gz" 2>/dev/null | awk '{print $1}')"
                say "Backup completed: $(relpath_from_project "$out_gz") (${size:-unknown})"
            else
                size="$(du -h "$out" 2>/dev/null | awk '{print $1}')"
                say "Backup completed (compression failed): $(relpath_from_project "$out") (${size:-unknown})"
            fi
        else
            size="$(du -h "$out" 2>/dev/null | awk '{print $1}')"
            say "Backup completed: $(relpath_from_project "$out") (${size:-unknown})"
        fi
    else
        rm -f "$out" >/dev/null 2>&1 || true
        die "Backup failed."
    fi
}

action_backup_all_databases_single_file() {
    hr
    say "Backup: All Databases (single file)"
    hr

    if ! test_credentials; then
        die "Access denied or unable to connect with provided credentials."
    fi

    ensure_backup_dir

    if ! has_cmd pv; then
        say "Info: Install 'pv' for progress bar during backup:"
        say "  sudo apt-get update && sudo apt-get install -y pv"
        say ""
    fi
    if ! has_cmd gzip; then
        say "Info: Install 'gzip' to save compressed backups (.sql.gz):"
        say "  sudo apt-get update && sudo apt-get install -y gzip"
        say ""
    fi

    pick_backup_output_dir
    out_dir="$BACKUP_OUT_DIR"

    pick_backup_output_format
    fmt="$BACKUP_FORMAT"

    out_base="$out_dir/dump-all-databases-$(timestamp).sql"
    out="$out_base"
    out_gz="${out_base}.gz"

    if [ "$fmt" = "sql.gz" ]; then
        out_final="$out_gz"
    else
        out_final="$out"
    fi

    say "Dump binary : $DUMP_BIN"
    say "Save folder : $(relpath_from_project "$out_dir")/"
    say "Output file : $(relpath_from_project "$out_final")"
    say ""

    if ! prompt_yes_no "Proceed with backup of ALL databases?"; then
        say "Cancelled."
        return 0
    fi

    if dump_to_file_with_progress "$out" --single-transaction --routines --triggers --events --all-databases; then
        if [ "$fmt" = "sql.gz" ]; then
            if gzip -f "$out"; then
                size="$(du -h "$out_gz" 2>/dev/null | awk '{print $1}')"
                say "Backup completed: $(relpath_from_project "$out_gz") (${size:-unknown})"
            else
                size="$(du -h "$out" 2>/dev/null | awk '{print $1}')"
                say "Backup completed (compression failed): $(relpath_from_project "$out") (${size:-unknown})"
            fi
        else
            size="$(du -h "$out" 2>/dev/null | awk '{print $1}')"
            say "Backup completed: $(relpath_from_project "$out") (${size:-unknown})"
        fi
    else
        rm -f "$out" >/dev/null 2>&1 || true
        die "Backup failed."
    fi
}

action_backup_each_db_separately() {
    hr
    say "Backup: Each Database Separately"
    hr

    if ! test_credentials; then
        die "Access denied or unable to connect with provided credentials."
    fi

    ensure_backup_dir

    if ! has_cmd pv; then
        say "Info: Install 'pv' for progress bar during backup:"
        say "  sudo apt-get update && sudo apt-get install -y pv"
        say ""
    fi
    if ! has_cmd gzip; then
        say "Info: Install 'gzip' to save compressed backups (.sql.gz):"
        say "  sudo apt-get update && sudo apt-get install -y gzip"
        say ""
    fi

    pick_backup_output_dir
    out_dir="$BACKUP_OUT_DIR"

    pick_backup_output_format
    fmt="$BACKUP_FORMAT"

    say "Save folder: $(relpath_from_project "$out_dir")/"
    say "Format     : $fmt"
    say ""

    dbs="$(list_databases 2>/dev/null || true)"
    if [ -z "$dbs" ]; then
        die "No databases found (or insufficient privileges to list)."
    fi

    say "Available databases:"
    echo "$dbs" | awk '{printf "  %d) %s\n", NR, $0}'
    say ""

    prompt "Select databases by number (e.g. 1,3,5 or 1 3 5) or 'all': "
    sel="$REPLY"
    [ -n "$sel" ] || die "Selection is required."

    case "$sel" in
        all|ALL)
            selected_dbs="$dbs"
            ;;
        *)
            # Allow comma-separated selections by normalizing commas to spaces
            sel_norm="$(echo "$sel" | tr ',' ' ')"
            selected_dbs=""
            for n in $sel_norm; do
                echo "$n" | grep -Eq '^[0-9]+$' || die "Invalid selection: $n"
                name="$(echo "$dbs" | awk -v i="$n" 'NR==i {print; exit}')"
                [ -n "$name" ] || die "Selection out of range: $n"
                if [ -z "$selected_dbs" ]; then
                    selected_dbs="$name"
                else
                    selected_dbs="$selected_dbs
$name"
                fi
            done
            ;;
    esac

    say "Databases to backup:"
    echo "$selected_dbs" | awk '{printf " - %s\n", $0}'
    say ""

    if ! prompt_yes_no "Proceed with backup for each database above?"; then
        say "Cancelled."
        return 0
    fi

    ok=0
    fail=0
    failed_list=""

    echo "$selected_dbs" | while IFS= read -r db; do
        [ -n "$db" ] || continue

        out_base="$out_dir/dump-${db}-$(timestamp).sql"
        out="$out_base"
        out_gz="${out_base}.gz"

        if [ "$fmt" = "sql.gz" ]; then
            out_final="$out_gz"
        else
            out_final="$out"
        fi

        say "------------------------------------------------"
        say "Backing up: $db"
        say "Output     : $(relpath_from_project "$out_final")"
        say "------------------------------------------------"

        if dump_to_file_with_progress "$out" --single-transaction --routines --triggers --events --databases "$db"; then
            if [ "$fmt" = "sql.gz" ]; then
                if gzip -f "$out"; then
                    size="$(du -h "$out_gz" 2>/dev/null | awk '{print $1}')"
                    say "OK: $(relpath_from_project "$out_gz") (${size:-unknown})"
                else
                    size="$(du -h "$out" 2>/dev/null | awk '{print $1}')"
                    say "OK (compression failed): $(relpath_from_project "$out") (${size:-unknown})"
                fi
            else
                size="$(du -h "$out" 2>/dev/null | awk '{print $1}')"
                say "OK: $(relpath_from_project "$out") (${size:-unknown})"
            fi
        else
            rm -f "$out" >/dev/null 2>&1 || true
            say "FAILED: $db"
            # Since this is inside a pipe, we can't reliably update counters across shells in POSIX sh.
            # We'll just report per-db failures here.
        fi
        say ""
    done

    say "Done. Check the output above for any FAILED entries."
}

select_backup_file() {
    # Lists files in backup/ and database-backup/ and prompts user to select one.
    # Sets SELECTED_FILE (absolute path).
    SELECTED_FILE=""

    files=""
    for d in $RESTORE_SEARCH_DIRS; do
        [ -d "$d" ] || continue
        found="$(find "$d" -type f \( -name "*.sql" -o -name "*.sql.gz" \) 2>/dev/null | sort || true)"
        if [ -n "$found" ]; then
            if [ -z "$files" ]; then
                files="$found"
            else
                files="$files
$found"
            fi
        fi
    done

    if [ -z "$files" ]; then
        die "No .sql or .sql.gz files found in: $BACKUP_DIR or $DATABASE_BACKUP_DIR"
    fi

    say "Available SQL files:"
    i=1
    echo "$files" | while IFS= read -r f; do
        [ -n "$f" ] || continue
        size="$(du -h "$f" 2>/dev/null | awk '{print $1}')"

        # Show full relative file path (relative to project when possible)
        rel="$f"
        case "$f" in
            "$PROJECT_DIR"/*) rel="${f#$PROJECT_DIR/}" ;;
        esac

        printf "  %s) %s (%s)\n" "$i" "$rel" "${size:-unknown}"
        i=$((i + 1))
    done

    prompt "Select file number: "
    choice="$REPLY"

    echo "$choice" | grep -Eq '^[0-9]+$' || die "Invalid selection."

    # Extract nth line
    SELECTED_FILE="$(echo "$files" | awk -v n="$choice" 'NR==n {print; exit}')"
    [ -n "$SELECTED_FILE" ] || die "Selection out of range."
}

infer_db_from_filename() {
    # Try to infer db name from filenames.
    # Preferred convention:
    # - dump-<dbname>-<timestamp>.sql(.gz)
    # Backward-compatible (older backups):
    # - file-backup-<dbname>-<timestamp>.sql(.gz)
    # Echo inferred db, or empty.
    base="$1"
    b="$(basename "$base")"

    # Remove extensions
    b="$(echo "$b" | sed 's/\.sql\.gz$//; s/\.sql$//')"

    # Must start with dump- or file-backup-
    case "$b" in
        dump-*) rest="$(echo "$b" | sed 's/^dump-//')" ;;
        file-backup-*) rest="$(echo "$b" | sed 's/^file-backup-//')" ;;
        *) echo ""; return 0 ;;
    esac

    # If it is "all-databases-...." don't infer
    echo "$rest" | grep -q '^all-databases-' && { echo ""; return 0; }

    # Remove trailing -digits timestamp (best effort)
    db="$(echo "$rest" | sed 's/-[0-9][0-9]*$//')"

    if is_safe_db_name "$db"; then
        echo "$db"
    else
        echo ""
    fi
}

pick_target_database() {
    # Interactive picker: show existing DBs + option to create a new one.
    #
    # Args:
    #   $1 = inferred db name (optional)
    #   $2 = required flag (1 required, 0 optional; default: 1)
    #
    # Output:
    #   Sets SELECTED_DB (empty only when optional and user skips)
    inferred="$1"
    required="${2:-1}"
    SELECTED_DB=""

    dbs="$(list_databases 2>/dev/null || true)"

    while :; do
        say ""
        say "Existing databases:"
        if [ -n "$dbs" ]; then
            echo "$dbs" | awk '{printf "  %d) %s\n", NR, $0}'
        else
            say "  (none)"
        fi
        say "  0) Create new database"
        say ""

        if [ -n "$inferred" ]; then
            say "Inferred from filename: $inferred"
        fi

        if [ "$required" = "1" ]; then
            prompt "Select database number: "
        else
            prompt "Select database number (empty to skip): "
        fi
        choice="$REPLY"

        if [ -z "$choice" ]; then
            if [ "$required" = "1" ]; then
                say "Selection is required."
                continue
            fi
            SELECTED_DB=""
            return 0
        fi

        if ! echo "$choice" | grep -Eq '^[0-9]+$'; then
            say "Invalid selection."
            continue
        fi

        if [ "$choice" = "0" ]; then
            if [ -n "$inferred" ]; then
                prompt_default "New database name" "$inferred"
                db="$REPLY"
            else
                prompt "New database name: "
                db="$REPLY"
            fi

            if [ -z "$db" ]; then
                say "Database name is required."
                continue
            fi
            if ! is_safe_db_name "$db"; then
                say "Unsupported database name. Use only letters, numbers, and underscore."
                continue
            fi

            # Always create new databases with utf8mb4 + utf8mb4_unicode_ci
            if ! printf '%s\n' "$DB_PASS" | docker_mariadb_exec "" -e "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
                die "Failed to create database: $db"
            fi

            SELECTED_DB="$db"
            return 0
        fi

        selected="$(echo "$dbs" | awk -v n="$choice" 'NR==n {print; exit}')"
        if [ -z "$selected" ]; then
            say "Selection out of range."
            continue
        fi

        if ! is_safe_db_name "$selected"; then
            say "Unsupported database name. Use only letters, numbers, and underscore."
            continue
        fi

        SELECTED_DB="$selected"
        return 0
    done
}

action_restore_single() {
    hr
    say "Restore: Single File -> Single Database"
    hr

    if ! test_credentials; then
        die "Access denied or unable to connect with provided credentials."
    fi

    select_backup_file
    file="$SELECTED_FILE"

    size="$(du -h "$file" 2>/dev/null | awk '{print $1}')"

    # Show full relative file path (relative to project when possible)
    rel="$file"
    case "$file" in
        "$PROJECT_DIR"/*) rel="${file#$PROJECT_DIR/}" ;;
    esac

    say ""
    say "Selected file: $rel (${size:-unknown})"

    # Tool hints (host-side)
    if ! has_cmd pv; then
        say "Info: Install 'pv' for progress bar during restore:"
        say "  sudo apt-get update && sudo apt-get install -y pv"
    fi

    case "$file" in
        *.gz)
            if ! has_cmd gunzip; then
                die "Restoring .sql.gz requires 'gunzip' on the host. Install gzip package:\n  sudo apt-get update && sudo apt-get install -y gzip"
            fi
            ;;
    esac

    inferred="$(infer_db_from_filename "$file")"
    pick_target_database "$inferred" 1
    db="$SELECTED_DB"

    [ -n "$db" ] || die "Target database is required."
    if ! is_safe_db_name "$db"; then
        die "Unsupported database name. Use only letters, numbers, and underscore."
    fi

    say ""
    say "This will:"
    say " - Create database if not exists: $db"
    say " - Restore into: $db"
    say ""

    if ! prompt_yes_no "Proceed with restore?"; then
        say "Cancelled."
        return 0
    fi

    # Create DB first
    if ! printf '%s\n' "$DB_PASS" | docker_mariadb_exec "" -e "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        die "Failed to create database: $db"
    fi

    # Restore (password line + sql stream)
    # If `pv` exists, you'll see a progress bar / throughput while the restore runs.
    if ( printf '%s\n' "$DB_PASS"; stream_restore_sql "$file" ) | docker_mariadb_exec "$db"; then
        say "Restore completed: $db"
    else
        die "Restore failed: $db"
    fi
}

action_restore_multiple_one_by_one() {
    hr
    say "Restore: Multiple Files (one-by-one confirmation)"
    hr

    if ! test_credentials; then
        die "Access denied or unable to connect with provided credentials."
    fi

    files=""
    for d in $RESTORE_SEARCH_DIRS; do
        [ -d "$d" ] || continue
        found="$(find "$d" -type f \( -name "*.sql" -o -name "*.sql.gz" \) 2>/dev/null | sort || true)"
        if [ -n "$found" ]; then
            if [ -z "$files" ]; then
                files="$found"
            else
                files="$files
$found"
            fi
        fi
    done

    if [ -z "$files" ]; then
        die "No .sql or .sql.gz files found in: $BACKUP_DIR or $DATABASE_BACKUP_DIR"
    fi

    say "Files found:"
    echo "$files" | while IFS= read -r f; do
        [ -n "$f" ] || continue
        # Show full relative file path (relative to project when possible)
        rel="$f"
        case "$f" in
            "$PROJECT_DIR"/*) rel="${f#$PROJECT_DIR/}" ;;
        esac
        printf " - %s\n" "$rel"
    done
    say ""

    # Tool hints (host-side)
    if ! has_cmd pv; then
        say "Info: Install 'pv' for progress bar during restore:"
        say "  sudo apt-get update && sudo apt-get install -y pv"
    fi
    if ! has_cmd gunzip; then
        say "Info: Some files may be .sql.gz. To restore .gz files, install gzip (includes gunzip):"
        say "  sudo apt-get update && sudo apt-get install -y gzip"
    fi
    say ""

    if ! prompt_yes_no "Proceed and ask confirmation per file?"; then
        say "Cancelled."
        return 0
    fi

    echo "$files" | while IFS= read -r file; do
        [ -n "$file" ] || continue

        size="$(du -h "$file" 2>/dev/null | awk '{print $1}')"
        inferred="$(infer_db_from_filename "$file")"

        # Show full relative file path (relative to project when possible)
        rel="$file"
        case "$file" in
            "$PROJECT_DIR"/*) rel="${file#$PROJECT_DIR/}" ;;
        esac

        say "------------------------------------------------"
        say "File: $rel (${size:-unknown})"

        case "$file" in
            *.gz)
                if ! has_cmd gunzip; then
                    say "Skip: file is .sql.gz but 'gunzip' not found on host."
                    say "Install: sudo apt-get update && sudo apt-get install -y gzip"
                    continue
                fi
                ;;
        esac

        pick_target_database "$inferred" 0
        db="$SELECTED_DB"

        [ -n "$db" ] || { say "Skip (no db provided)."; continue; }
        if ! is_safe_db_name "$db"; then
            say "Skip (unsupported db name): $db"
            continue
        fi

        if ! prompt_yes_no "Restore this file into database '$db'?"; then
            say "Skipped."
            continue
        fi

        # Create DB then restore
        if ! printf '%s\n' "$DB_PASS" | docker_mariadb_exec "" -e "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
            say "FAILED (create db): $db"
            continue
        fi

        # Restore (password line + sql stream)
        # If `pv` exists, you'll see a progress bar / throughput while the restore runs.
        if ( printf '%s\n' "$DB_PASS"; stream_restore_sql "$file" ) | docker_mariadb_exec "$db"; then
            say "OK: Restored into $db"
        else
            say "FAILED: Restore into $db"
        fi
        say ""
    done

    say "Done."
}

show_config() {
    hr
    say "Current Session Configuration"
    hr
    say "Project dir         : $PROJECT_DIR"
    say "Backup base dir     : $DATABASE_BACKUP_DIR (all backups are saved here)"
    say "Legacy restore dir  : $BACKUP_DIR (restore search only)"
    say "Container           : $CONTAINER"
    say "DB user             : $DB_USER"
    say "Dump binary         : $DUMP_BIN"

    say ""
    say "Host tools status:"
    if has_cmd docker; then docker_s="OK"; else docker_s="MISSING"; fi
    if has_cmd pv; then pv_s="OK"; else pv_s="MISSING"; fi
    if has_cmd gzip; then gzip_s="OK"; else gzip_s="MISSING"; fi
    if has_cmd gunzip; then gunzip_s="OK"; else gunzip_s="MISSING"; fi

    say " - docker  : $docker_s (required)"
    say " - pv      : $pv_s (recommended: progress bar during backup/restore)"
    say " - gzip    : $gzip_s (recommended: compression support)"
    say " - gunzip  : $gunzip_s (required for restoring .gz files)"

    say ""
    say "Ubuntu/Debian install hints:"
    say " - Install recommended tools:"
    say "     sudo apt-get update && sudo apt-get install -y pv gzip"
    say ""
    say "Notes:"
    say " - Progress bar appears only if 'pv' is installed on the host."
    say " - Restore of .sql.gz requires 'gunzip' (provided by the 'gzip' package)."
}

main_menu() {
    while :; do
        hr
        say "MariaDB Docker Backup/Restore CLI"
        hr
        say "1) List databases"
        say "2) Backup single database"
        say "3) Backup all databases (single file)"
        say "4) Backup each database separately"
        say "5) Restore single file to single database"
        say "6) Restore multiple files (one-by-one)"
        say "7) Show session config"
        say "0) Exit"
        say ""

        prompt "Select option: "
        choice="$REPLY"

        case "$choice" in
            1) action_list_databases ;;
            2) action_backup_single_db ;;
            3) action_backup_all_databases_single_file ;;
            4) action_backup_each_db_separately ;;
            5) action_restore_single ;;
            6) action_restore_multiple_one_by_one ;;
            7) show_config ;;
            0) exit 0 ;;
            *) say "Invalid option." ;;
        esac

        say ""
        prompt "Press Enter to continue..."
    done
}

# -----------------------------
# Startup flow (credentials required first)
# -----------------------------

startup() {
    need_cmd docker

    hr
    say "MariaDB Docker Backup/Restore CLI"
    hr
    say "Requirement: You must enter MariaDB username & password before continuing."
    say ""

    prompt_default "Docker container name" "$DEFAULT_CONTAINER"
    CONTAINER="$REPLY"
    [ -n "$CONTAINER" ] || die "Container name is required."

    check_container_running
    detect_dump_binary

    prompt_default "MariaDB username" "root"
    DB_USER="$REPLY"
    [ -n "$DB_USER" ] || die "Username is required."

    # Password is mandatory (even if empty passwords are possible, you required it must be entered)
    prompt_secret "MariaDB password: "
    DB_PASS="$REPLY"

    # Confirm connection now so the rest of the menu doesn't fail later
    if test_credentials; then
        say "Connection test: OK"
    else
        die "Connection test failed. Check username/password and privileges."
    fi

    # Ensure backup dir exists early (nice UX)
    ensure_backup_dir

    main_menu
}

startup
