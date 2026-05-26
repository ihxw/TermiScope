#!/usr/bin/env bash
# Integration test for repair_database.sh (no systemd, temp data dir).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPAIR="${ROOT}/scripts/repair_database.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

pass() { echo "[test] PASS: $*"; }
fail() { echo "[test] FAIL: $*" >&2; exit 1; }

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "[test] SKIP: sqlite3 not installed (apt install sqlite3)"
  exit 0
fi

setup_fixture_db_in() {
  local dir="$1"
  sqlite3 "${dir}/termiscope.db" <<'SQL'
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT NOT NULL);
CREATE TABLE ssh_hosts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, host TEXT);
CREATE TABLE network_monitor_tasks (id INTEGER PRIMARY KEY, host_id INTEGER, type TEXT, target TEXT);
CREATE TABLE network_monitor_results (
  id INTEGER PRIMARY KEY,
  task_id INTEGER NOT NULL,
  latency REAL,
  packet_loss REAL,
  success INTEGER,
  created_at TEXT
);
INSERT INTO users (id, username) VALUES (1, 'admin');
INSERT INTO ssh_hosts (id, name, host) VALUES (1, 'test-host', '127.0.0.1');
INSERT INTO network_monitor_tasks (id, host_id, type, target) VALUES (160, 1, 'ping', '8.8.8.8');
INSERT INTO network_monitor_results (task_id, latency, packet_loss, success, created_at)
  VALUES (160, 12.5, 0, 1, datetime('now', '-2 hours')),
         (160, 20.0, 0, 1, datetime('now', '-1 hour'));
SQL
}

setup_fixture_db() {
  setup_fixture_db_in "${TEST_DIR}"
}

echo "[test] Using temp dir: ${TEST_DIR}"

bash "${REPAIR}" --help >/dev/null && pass "--help exits 0"

if bash "${REPAIR}" --bad-flag 2>/dev/null; then
  fail "unknown flag should exit non-zero"
else
  pass "unknown flag rejected"
fi

if REPAIR_OUT="$(bash "${REPAIR}" --data-dir "${TEST_DIR}/empty" --no-restart 2>&1)"; then
  fail "missing db should exit non-zero"
else
  echo "${REPAIR_OUT}" | grep -q "Database not found" && pass "missing db reported"
fi

setup_fixture_db
[[ -f "${TEST_DIR}/termiscope.db" ]] || fail "fixture db not created"

BEFORE_USERS="$(sqlite3 "${TEST_DIR}/termiscope.db" "SELECT COUNT(*) FROM users;")"
BEFORE_HOSTS="$(sqlite3 "${TEST_DIR}/termiscope.db" "SELECT COUNT(*) FROM ssh_hosts;")"
BEFORE_RESULTS="$(sqlite3 "${TEST_DIR}/termiscope.db" "SELECT COUNT(*) FROM network_monitor_results;")"
[[ "${BEFORE_USERS}" -eq 1 && "${BEFORE_HOSTS}" -eq 1 && "${BEFORE_RESULTS}" -eq 2 ]] || fail "fixture counts wrong"

echo "[test] Running repair_database.sh..."
bash "${REPAIR}" --data-dir "${TEST_DIR}" --no-restart

[[ -f "${TEST_DIR}/termiscope.db" ]] || fail "termiscope.db missing after repair"
[[ ! -f "${TEST_DIR}/termiscope_recovered.db" ]] || fail "recovered temp file should be swapped away"

INTEGRITY="$(sqlite3 "${TEST_DIR}/termiscope.db" "PRAGMA integrity_check;" | head -n1)"
[[ "${INTEGRITY}" == "ok" ]] || fail "integrity_check not ok: ${INTEGRITY}"
pass "integrity_check ok"

AFTER_USERS="$(sqlite3 "${TEST_DIR}/termiscope.db" "SELECT COUNT(*) FROM users;")"
AFTER_HOSTS="$(sqlite3 "${TEST_DIR}/termiscope.db" "SELECT COUNT(*) FROM ssh_hosts;")"
[[ "${AFTER_USERS}" -eq 1 && "${AFTER_HOSTS}" -eq 1 ]] || fail "users/hosts lost after repair"

if sqlite3 "${TEST_DIR}/termiscope.db" "SELECT 1 FROM sqlite_master WHERE name='network_monitor_results';" | grep -q 1; then
  fail "network_monitor_results should be dropped"
fi
pass "network_monitor_results dropped"

BACKUPS="$(find "${TEST_DIR}" -maxdepth 1 -name 'termiscope.db.bak.*' | wc -l)"
[[ "${BACKUPS}" -ge 1 ]] || fail "no backup file created"
pass "backup file created"

CORRUPT="$(find "${TEST_DIR}" -maxdepth 1 -name 'termiscope.db.corrupt.*' | wc -l)"
[[ "${CORRUPT}" -ge 1 ]] || fail "no corrupt archive created"
pass "corrupt archive created"

# --keep-monitor: table should remain (fresh db in new temp dir)
KEEP_DIR="$(mktemp -d)"
setup_fixture_db_in "${KEEP_DIR}"
bash "${REPAIR}" --data-dir "${KEEP_DIR}" --no-restart --keep-monitor
if sqlite3 "${KEEP_DIR}/termiscope.db" "SELECT 1 FROM sqlite_master WHERE name='network_monitor_results';" | grep -q 1; then
  COUNT="$(sqlite3 "${KEEP_DIR}/termiscope.db" "SELECT COUNT(*) FROM network_monitor_results;")"
  [[ "${COUNT}" -ge 1 ]] && pass "--keep-monitor preserves network_monitor_results (${COUNT} rows)"
else
  fail "--keep-monitor should keep table"
fi
rm -rf "${KEEP_DIR}"

# Large table smoke test (~5000 rows, recover + drop)
LARGE_DIR="$(mktemp -d)"
setup_fixture_db_in "${LARGE_DIR}"
sqlite3 "${LARGE_DIR}/termiscope.db" "WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM c WHERE n<5000) INSERT INTO network_monitor_results (task_id, latency, packet_loss, success, created_at) SELECT 160, 1.0, 0, 1, datetime('now', '-' || (n % 48) || ' hours') FROM c;"
LARGE_BEFORE="$(sqlite3 "${LARGE_DIR}/termiscope.db" "SELECT COUNT(*) FROM network_monitor_results;")"
[[ "${LARGE_BEFORE}" -eq 5002 ]] || fail "large fixture expected 5002 rows, got ${LARGE_BEFORE}"
bash "${REPAIR}" --data-dir "${LARGE_DIR}" --no-restart
LARGE_INTEGRITY="$(sqlite3 "${LARGE_DIR}/termiscope.db" "PRAGMA integrity_check;" | head -n1)"
[[ "${LARGE_INTEGRITY}" == "ok" ]] || fail "large db integrity: ${LARGE_INTEGRITY}"
pass "large dataset recover (${LARGE_BEFORE} rows before drop)"
rm -rf "${LARGE_DIR}"

echo "[test] All repair_database.sh tests passed."
