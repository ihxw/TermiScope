#!/usr/bin/env bash
# Repair TermiScope SQLite DB when network_monitor_results is bloated/corrupt.
# Uses sqlite3 ".recover" to build a new database, drops network_monitor_results,
# VACUUMs, then replaces the live file.
#
# Default paths match scripts/install.sh (/opt/termiscope).
#
# Usage:
#   sudo ./scripts/repair_database.sh
#   sudo ./scripts/repair_database.sh --data-dir /opt/termiscope/data
#   sudo ./scripts/repair_database.sh --no-restart
#
# Requires: sqlite3 >= 3.37 (.recover), systemctl (or stop/start TermiScope yourself)

set -euo pipefail

DATA_DIR="/opt/termiscope/data"
DB_NAME="termiscope.db"
SERVICE_NAME="termiscope"
NO_RESTART=false
DROP_MONITOR_TABLE=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[repair-db]${NC} $*"; }
warn() { echo -e "${YELLOW}[repair-db]${NC} $*"; }
err() { echo -e "${RED}[repair-db]${NC} $*" >&2; }

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Options:"
  echo "  --data-dir PATH    Directory containing termiscope.db (default: /opt/termiscope/data)"
  echo "  --no-restart       Do not stop/start systemd service"
  echo "  --keep-monitor     Do not DROP network_monitor_results after recover"
  echo "  -h, --help         Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-dir)
      DATA_DIR="${2:?missing path for --data-dir}"
      shift 2
      ;;
    --no-restart)
      NO_RESTART=true
      shift
      ;;
    --keep-monitor)
      DROP_MONITOR_TABLE=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

DB_PATH="${DATA_DIR}/${DB_NAME}"
RECOVERED_PATH="${DATA_DIR}/termiscope_recovered.db"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_PATH="${DATA_DIR}/${DB_NAME}.bak.${STAMP}"

version_ge() {
  # usage: version_ge "3.37.2" "3.37.0"
  printf '%s\n%s\n' "$2" "$1" | sort -V -C 2>/dev/null
}

require_sqlite() {
  if ! command -v sqlite3 >/dev/null 2>&1; then
    err "sqlite3 not found. Install: apt install sqlite3 / dnf install sqlite3"
    exit 1
  fi
  local ver
  ver="$(sqlite3 --version | awk '{print $1}')"
  log "sqlite3 version: ${ver}"
  if ! version_ge "$ver" "3.37.0"; then
    err "sqlite3 >= 3.37 required for .recover (you have ${ver})"
    exit 1
  fi
}

stop_service() {
  if [[ "$NO_RESTART" == true ]]; then
    warn "--no-restart: ensure TermiScope is stopped and no process uses ${DB_PATH}"
    return
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null; then
    if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
      log "Stopping ${SERVICE_NAME}..."
      systemctl stop "${SERVICE_NAME}"
    else
      log "Service ${SERVICE_NAME} is not active"
    fi
  else
    if [[ -t 0 ]]; then
      warn "systemctl unit ${SERVICE_NAME} not found; stop TermiScope manually before continuing."
      read -r -p "Press Enter when the database is not in use..."
    else
      err "systemctl unit ${SERVICE_NAME} not found (non-interactive). Stop TermiScope or use --no-restart."
      exit 1
    fi
  fi
}

start_service() {
  if [[ "$NO_RESTART" == true ]]; then
    warn "Skipped service start (--no-restart)"
    return
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null; then
    log "Starting ${SERVICE_NAME}..."
    systemctl start "${SERVICE_NAME}"
    systemctl --no-pager status "${SERVICE_NAME}" || true
  fi
}

backup_db() {
  log "Backing up to ${BACKUP_PATH}..."
  cp -a "${DB_PATH}" "${BACKUP_PATH}"
  for ext in -wal -shm; do
    if [[ -f "${DB_PATH}${ext}" ]]; then
      cp -a "${DB_PATH}${ext}" "${BACKUP_PATH}${ext}"
    fi
  done
}

# .recover emits CREATE/INSERT for sqlite_sequence; importing that into a new DB fails.
filter_recover_sql() {
  sed -E \
    -e '/^CREATE TABLE (IF NOT EXISTS )?sqlite_/Id' \
    -e '/^INSERT INTO sqlite_/Id' \
    -e '/^DELETE FROM sqlite_/Id'
}

run_vacuum_into() {
  log "Trying VACUUM INTO (fast path when the DB is still readable)..."
  rm -f "${RECOVERED_PATH}"
  local esc_path="${RECOVERED_PATH//\'/\'\'}"
  if sqlite3 "${DB_PATH}" "VACUUM INTO '${esc_path}';" 2>/dev/null && [[ -f "${RECOVERED_PATH}" ]]; then
    log "VACUUM INTO succeeded"
    return 0
  fi
  rm -f "${RECOVERED_PATH}"
  warn "VACUUM INTO failed or unavailable, falling back to .recover..."
  return 1
}

run_recover() {
  log "Running .recover (large DBs: often 30–60+ minutes, ~2M rows)..."
  rm -f "${RECOVERED_PATH}"
  local recover_err="${DATA_DIR}/termiscope_recover_${STAMP}.err"
  rm -f "${recover_err}"

  if ! sqlite3 "${DB_PATH}" ".recover" 2>"${recover_err}" | filter_recover_sql | sqlite3 "${RECOVERED_PATH}" 2>>"${recover_err}"; then
    err ".recover failed (see ${recover_err})"
    tail -30 "${recover_err}" >&2 2>/dev/null || true
    exit 1
  fi

  if [[ ! -f "${RECOVERED_PATH}" ]]; then
    err ".recover produced no output database"
    exit 1
  fi
  log ".recover finished"
}

check_db() {
  local path="$1"
  local label="$2"
  log "integrity_check on ${label}..."
  local check
  check="$(sqlite3 "${path}" "PRAGMA integrity_check;" | head -n 1)"
  if [[ "${check}" != "ok" ]]; then
    warn "integrity_check: ${check}"
    return 1
  fi
  log "integrity_check: ok"
  return 0
}

prune_monitor_table() {
  local path="$1"
  if [[ "$DROP_MONITOR_TABLE" != true ]]; then
    return
  fi
  if sqlite3 "${path}" "SELECT name FROM sqlite_master WHERE type='table' AND name='network_monitor_results';" | grep -q network_monitor_results; then
    log "Dropping network_monitor_results (will be recreated empty on next TermiScope start)..."
    sqlite3 "${path}" "DROP TABLE IF EXISTS network_monitor_results;"
  else
    warn "network_monitor_results not present in recovered DB (ok)"
  fi
  log "VACUUM..."
  sqlite3 "${path}" "VACUUM;"
}

swap_db() {
  local corrupt_path="${DATA_DIR}/${DB_NAME}.corrupt.${STAMP}"
  log "Replacing live database..."
  mv "${DB_PATH}" "${corrupt_path}"
  mv "${RECOVERED_PATH}" "${DB_PATH}"
  rm -f "${DB_PATH}-wal" "${DB_PATH}-shm"
  log "Old file kept at: ${corrupt_path}"
  log "Backup copy at: ${BACKUP_PATH}"
}

print_counts() {
  local path="$1"
  log "Row counts:"
  local t c
  for t in ssh_hosts users network_monitor_tasks; do
    if sqlite3 "${path}" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='${t}';" | grep -q 1; then
      c="$(sqlite3 "${path}" "SELECT COUNT(*) FROM ${t};")"
      log "  ${t}: ${c}"
    fi
  done
  if sqlite3 "${path}" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='network_monitor_results';" | grep -q 1; then
    c="$(sqlite3 "${path}" "SELECT COUNT(*) FROM network_monitor_results;")"
    log "  network_monitor_results: ${c}"
  else
    log "  network_monitor_results: (not present — TermiScope will recreate on start)"
  fi
}

main() {
  if [[ ! -f "${DB_PATH}" ]]; then
    err "Database not found: ${DB_PATH}"
    exit 1
  fi

  if [[ "$(id -u)" -ne 0 ]] && [[ "$NO_RESTART" != true ]]; then
    warn "Not running as root; use sudo for service stop/start, or pass --no-restart"
  fi

  require_sqlite
  stop_service

  backup_db

  warn "Checking original DB (errors here are expected if corrupt)..."
  sqlite3 "${DB_PATH}" "SELECT COUNT(*) AS network_monitor_results FROM network_monitor_results;" 2>/dev/null || true

  if ! run_vacuum_into; then
    run_recover
  fi
  check_db "${RECOVERED_PATH}" "recovered" || warn "Recovered DB did not pass integrity_check; review before swapping"

  prune_monitor_table "${RECOVERED_PATH}"
  print_counts "${RECOVERED_PATH}"

  swap_db
  start_service

  log "Done. Test network monitor API or open the dashboard."
  log "On first start, migrations recreate network_monitor_results if it was dropped."
}

main "$@"
