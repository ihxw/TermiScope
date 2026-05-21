#!/usr/bin/env bash
# Simulates repair on /opt/termiscope/data layout under /tmp (WSL).
set -euo pipefail

REPAIR="$(cd "$(dirname "$0")" && pwd)/repair_database.sh"
DEPLOY="/tmp/opt/termiscope/data"

rm -rf /tmp/opt/termiscope
mkdir -p "${DEPLOY}"

sqlite3 "${DEPLOY}/termiscope.db" <<'SQL'
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT NOT NULL);
CREATE TABLE ssh_hosts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, host TEXT);
CREATE TABLE network_monitor_tasks (id INTEGER PRIMARY KEY, host_id INTEGER, type TEXT, target TEXT);
CREATE TABLE network_monitor_results (
  id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL,
  latency REAL, packet_loss REAL, success INTEGER, created_at TEXT
);
INSERT INTO users VALUES (1, 'admin');
INSERT INTO ssh_hosts VALUES (1, 'prod-like', '10.0.0.1');
INSERT INTO network_monitor_tasks VALUES (160, 1, 'ping', '8.8.8.8');
WITH RECURSIVE c(n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM c WHERE n < 1000
)
INSERT INTO network_monitor_results (task_id, latency, packet_loss, success, created_at)
SELECT 160, 1.0, 0, 1, datetime('now', '-' || (n % 24) || ' hours') FROM c;
SQL

echo "[deploy-test] Before: $(sqlite3 "${DEPLOY}/termiscope.db" 'SELECT COUNT(*) FROM network_monitor_results;') monitor rows"
bash "${REPAIR}" --data-dir "${DEPLOY}" --no-restart
echo "[deploy-test] After hosts: $(sqlite3 "${DEPLOY}/termiscope.db" 'SELECT COUNT(*) FROM ssh_hosts;')"
echo "[deploy-test] integrity: $(sqlite3 "${DEPLOY}/termiscope.db" 'PRAGMA integrity_check;' | head -n1)"
echo "[deploy-test] OK — layout matches /opt/termiscope/data"
