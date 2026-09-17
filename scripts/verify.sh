#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DB_SERVICE="${DB_SERVICE:-postgres}"
DB_NAME="${DB_NAME:-hotel_booking}"
DB_USER="${DB_USER:-app_user}"

if ! docker compose ps --services --filter status=running | grep -qx "$DB_SERVICE"; then
    echo "ERROR: compose service '${DB_SERVICE}' is not running." >&2
    echo "Start it first:  docker compose up -d" >&2
    exit 1
fi

run_sql() {
    docker compose exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "$1"
}

section() {
    echo
    echo "=================================================================="
    echo "$1"
    echo "=================================================================="
}

section "1. Tables"
run_sql '\dt'

section "2. Seed coverage"
run_sql "
SELECT
    (SELECT count(*) FROM hotel_bookings)            AS bookings,
    (SELECT count(*) FROM booking_events)            AS events,
    (SELECT count(DISTINCT city) FROM hotel_bookings)   AS cities,
    (SELECT count(DISTINCT org_id) FROM hotel_bookings) AS orgs,
    (SELECT count(DISTINCT status) FROM hotel_bookings) AS statuses;
"

section "3. Bookings per city"
run_sql "SELECT city, count(*) FROM hotel_bookings GROUP BY city ORDER BY city;"

section "4. Bookings per status"
run_sql "SELECT status, count(*) FROM hotel_bookings GROUP BY status ORDER BY status;"

section "5. Event types"
run_sql "SELECT event_type, count(*) FROM booking_events GROUP BY event_type ORDER BY event_type;"

section "6. Indexes"
run_sql "
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
"

section "7. Target query result"
run_sql "
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
"

section "8. Query plan WITH the index"
echo "Expect: 'Index Only Scan using idx_hotel_bookings_city_created_at'"
echo "        with 'Heap Fetches: 0'."
run_sql "
EXPLAIN (ANALYZE, BUFFERS)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
"

section "9. Query plan WITHOUT the index (baseline)"
echo "Index scans are disabled for this session only, to show what the query"
echo "would cost unindexed. Expect a Seq Scan with ~99k rows removed by filter."
run_sql "
SET enable_indexscan = off;
SET enable_indexonlyscan = off;
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
"

echo
echo "Verification completed."
