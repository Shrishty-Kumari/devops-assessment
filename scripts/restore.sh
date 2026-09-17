#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DB_SERVICE="${DB_SERVICE:-postgres}"
DB_NAME="${DB_NAME:-hotel_booking}"
DB_USER="${DB_USER:-app_user}"
RESTORE_DB="${RESTORE_DB:-hotel_booking_restore}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"

if ! docker compose ps --services --filter status=running | grep -qx "$DB_SERVICE"; then
    echo "ERROR: compose service '${DB_SERVICE}' is not running." >&2
    echo "Start it first:  docker compose up -d" >&2
    exit 1
fi

if [[ $# -ge 1 ]]; then
    BACKUP_FILE="$1"
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "ERROR: backup file not found: ${BACKUP_FILE}" >&2
        exit 1
    fi
else
    BACKUP_FILE="$(find "$BACKUP_DIR" -type f -name '*.dump' 2>/dev/null | sort | tail -n 1)"
    if [[ -z "$BACKUP_FILE" ]]; then
        echo "ERROR: no *.dump found in ${BACKUP_DIR}" >&2
        echo "Create one first:  ./scripts/backup.sh" >&2
        exit 1
    fi
fi

echo "Restoring from : ${BACKUP_FILE}"
echo "Target database: ${RESTORE_DB} (recreated from scratch)"

psql_admin() {
    docker compose exec -T "$DB_SERVICE" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 "$@"
}

psql_restored() {
    docker compose exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$RESTORE_DB" -v ON_ERROR_STOP=1 "$@"
}

echo
echo "[1/4] Verifying dump integrity"
if [[ -f "${BACKUP_FILE}.meta" ]]; then
    EXPECTED_SHA="$(awk -F= '/^sha256=/ {print $2}' "${BACKUP_FILE}.meta")"
    ACTUAL_SHA="$(shasum -a 256 "$BACKUP_FILE" | awk '{print $1}')"
    if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
        echo "ERROR: checksum mismatch - the dump file has been modified or truncated." >&2
        echo "  expected ${EXPECTED_SHA}" >&2
        echo "  actual   ${ACTUAL_SHA}" >&2
        exit 1
    fi
    echo "      checksum OK (${ACTUAL_SHA:0:16}...)"
else
    echo "      no .meta sidecar found, skipping checksum check"
fi

echo
echo "[2/4] Creating fresh database"
psql_admin -c "DROP DATABASE IF EXISTS ${RESTORE_DB} WITH (FORCE);" >/dev/null
psql_admin -c "CREATE DATABASE ${RESTORE_DB};" >/dev/null
echo "      ${RESTORE_DB} created"

echo
echo "[3/4] Restoring dump"
docker compose exec -T "$DB_SERVICE" \
    pg_restore \
    -U "$DB_USER" \
    -d "$RESTORE_DB" \
    --no-owner \
    --no-privileges \
    --exit-on-error \
    <"$BACKUP_FILE"
echo "      pg_restore completed"

echo
echo "[4/4] Verifying restored data"

count_in_restore() {
    docker compose exec -T "$DB_SERVICE" \
        psql -U "$DB_USER" -d "$RESTORE_DB" -At -c "SELECT count(*) FROM $1;"
}

RESTORED_BOOKINGS="$(count_in_restore hotel_bookings)"
RESTORED_EVENTS="$(count_in_restore booking_events)"


if [[ -f "${BACKUP_FILE}.meta" ]]; then
    EXPECTED_BOOKINGS="$(awk -F= '/^hotel_bookings=/ {print $2}' "${BACKUP_FILE}.meta")"
    EXPECTED_EVENTS="$(awk -F= '/^booking_events=/ {print $2}' "${BACKUP_FILE}.meta")"
    EXPECTED_SOURCE="backup metadata"
else
    EXPECTED_BOOKINGS="$(docker compose exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$DB_NAME" -At -c 'SELECT count(*) FROM hotel_bookings;')"
    EXPECTED_EVENTS="$(docker compose exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$DB_NAME" -At -c 'SELECT count(*) FROM booking_events;')"
    EXPECTED_SOURCE="live ${DB_NAME} database"
fi

printf '      %-16s %-12s %-12s\n' "table" "expected" "restored"
printf '      %-16s %-12s %-12s\n' "hotel_bookings" "$EXPECTED_BOOKINGS" "$RESTORED_BOOKINGS"
printf '      %-16s %-12s %-12s\n' "booking_events" "$EXPECTED_EVENTS" "$RESTORED_EVENTS"
echo "      (expected values from: ${EXPECTED_SOURCE})"

FAILED=0
if [[ "$RESTORED_BOOKINGS" != "$EXPECTED_BOOKINGS" ]]; then
    echo "MISMATCH: hotel_bookings expected ${EXPECTED_BOOKINGS}, got ${RESTORED_BOOKINGS}" >&2
    FAILED=1
fi
if [[ "$RESTORED_EVENTS" != "$EXPECTED_EVENTS" ]]; then
    echo "MISMATCH: booking_events expected ${EXPECTED_EVENTS}, got ${RESTORED_EVENTS}" >&2
    FAILED=1
fi


echo
echo "      Indexes in restored database:"
psql_restored -c "SELECT tablename, indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename, indexname;"

RESTORED_INDEXES="$(docker compose exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$RESTORE_DB" -At -c "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public';")"
if [[ "$RESTORED_INDEXES" -lt 4 ]]; then
    echo "MISMATCH: expected at least 4 indexes, found ${RESTORED_INDEXES}" >&2
    FAILED=1
fi

RESTORED_FKS="$(docker compose exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$RESTORE_DB" -At -c "SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND conrelid = 'booking_events'::regclass;")"
if [[ "$RESTORED_FKS" -lt 1 ]]; then
    echo "MISMATCH: foreign key on booking_events was not restored" >&2
    FAILED=1
fi

echo
echo "      Sample data from restored database:"
psql_restored -c "SELECT city, count(*) AS bookings, round(sum(amount), 2) AS total_amount FROM hotel_bookings GROUP BY city ORDER BY city;"

if [[ "$FAILED" -ne 0 ]]; then
    echo
    echo "RESTORE VERIFICATION FAILED" >&2
    exit 1
fi

echo
echo "Restore verified successfully."
echo "  database : ${RESTORE_DB}"
echo "  rows     : hotel_bookings=${RESTORED_BOOKINGS} booking_events=${RESTORED_EVENTS}"
echo "  indexes  : ${RESTORED_INDEXES}"
echo
echo "Inspect it with:"
echo "  docker compose exec postgres psql -U ${DB_USER} -d ${RESTORE_DB}"
