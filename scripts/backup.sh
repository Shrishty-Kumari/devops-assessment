#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DB_SERVICE="${DB_SERVICE:-postgres}"
DB_NAME="${DB_NAME:-hotel_booking}"
DB_USER="${DB_USER:-app_user}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"

if ! docker compose ps --services --filter status=running | grep -qx "$DB_SERVICE"; then
    echo "ERROR: compose service '${DB_SERVICE}' is not running." >&2
    echo "Start it first:  docker compose up -d" >&2
    exit 1
fi

if ! docker compose exec -T "$DB_SERVICE" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    echo "ERROR: database '${DB_NAME}' is not accepting connections yet." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date -u +"%Y%m%d_%H%M%S")"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump"
META_FILE="${BACKUP_FILE}.meta"

cleanup_partial() {
    if [[ -n "${BACKUP_OK:-}" ]]; then
        return
    fi
    echo "Backup failed - removing partial file ${BACKUP_FILE}" >&2
    rm -f "$BACKUP_FILE" "$META_FILE"
}
trap cleanup_partial EXIT

echo "Backing up database '${DB_NAME}'"
echo "  -> ${BACKUP_FILE}"

read_count() {
    docker compose exec -T "$DB_SERVICE" \
        psql -U "$DB_USER" -d "$DB_NAME" -At -c "SELECT count(*) FROM $1;"
}

SRC_BOOKINGS="$(read_count hotel_bookings)"
SRC_EVENTS="$(read_count booking_events)"

docker compose exec -T "$DB_SERVICE" \
    pg_dump \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -Fc \
    --no-owner \
    --no-privileges \
    >"$BACKUP_FILE"

if [[ ! -s "$BACKUP_FILE" ]]; then
    echo "ERROR: dump file is empty." >&2
    exit 1
fi

CHECKSUM="$(shasum -a 256 "$BACKUP_FILE" | awk '{print $1}')"

cat >"$META_FILE" <<EOF
# Source database state at backup time - used by scripts/restore.sh
backup_file=$(basename "$BACKUP_FILE")
created_at_utc=${TIMESTAMP}
database=${DB_NAME}
hotel_bookings=${SRC_BOOKINGS}
booking_events=${SRC_EVENTS}
sha256=${CHECKSUM}
EOF

BACKUP_OK=1

echo
echo "Backup completed."
echo "  rows      : hotel_bookings=${SRC_BOOKINGS} booking_events=${SRC_EVENTS}"
echo "  size      : $(du -h "$BACKUP_FILE" | awk '{print $1}')"
echo "  sha256    : ${CHECKSUM}"
echo
ls -lh "$BACKUP_FILE" "$META_FILE"
