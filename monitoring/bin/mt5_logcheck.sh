#!/usr/bin/env bash
# mt5_logcheck.sh — AD-12 MT5 weekly KPI/log check wrapper.
#
# Runs mt5_logcheck.py, writes reports to a configurable report dir,
# and prunes old reports. Designed for systemd timer invocation; safe
# to run by hand.
#
# Usage:
#   ./mt5_logcheck.sh                # default: 2-day scan
#   ./mt5_logcheck.sh --days 1       # today only
#   ./mt5_logcheck.sh --days 30      # full month
#
# Environment overrides:
#   REPORT_DIR  — where to write reports (default: $HOME/mt5-monitoring/reports)
#   STATE_DIR   — where to write logs (default: $HOME/mt5-monitoring/state)
#   RETENTION_DAYS — prune reports older than N days (default: 90)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-/usr/bin/python3}"
LOGCHECK_PY="${SCRIPT_DIR}/mt5_logcheck.py"
REPORT_DIR="${REPORT_DIR:-${HOME}/mt5-monitoring/reports}"
STATE_DIR="${STATE_DIR:-${HOME}/mt5-monitoring/state}"
LOG_FILE="${STATE_DIR}/logcheck.log"
RETENTION_DAYS="${RETENTION_DAYS:-90}"

mkdir -p "${REPORT_DIR}" "${STATE_DIR}"

echo "[$(date -Iseconds)] mt5_logcheck.sh starting" >> "${LOG_FILE}"

if "${PYTHON}" "${LOGCHECK_PY}" --report-dir "${REPORT_DIR}" "$@" 2>>"${LOG_FILE}"; then
    rc=0
else
    rc=$?
fi

find "${REPORT_DIR}" -name "logcheck_*.json" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
find "${REPORT_DIR}" -name "logcheck_*.txt"  -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true

echo "[$(date -Iseconds)] mt5_logcheck.sh done (rc=${rc})" >> "${LOG_FILE}"
exit ${rc}
