#!/bin/bash
# sync-mql.sh — Restart MT4/MT5 terminals to pick up new EA/Indicator/Script files
#
# Usage:
#   ./sync-mql.sh [mt4|mt5|all|status]
#
# When to run:
#   - After adding new .ex4/.ex5 files to MT4/mql4 or MT5/mql5
#   - After modifying existing EA/Indicator/Script files

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[sync]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
err() { echo -e "${RED}[error]${NC} $1" >&2; }

sync_terminal() {
    local name="$1"
    local container="$2"
    local dir="$3"

    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        warn "Container ${container} is not running. Starting..."
        cd "$BASE_DIR/$dir"
        docker compose up -d
        cd "$BASE_DIR"
        sleep 5
    fi

    log "Syncing ${name} MQL files (bind mount is live — no restart needed)..."
    echo "  Files in $BASE_DIR/$dir/mql* are bind-mounted into the container."
    echo "  For EA updates: copy .ex5 to MQL5/Experts/ then re-attach via noVNC."
    echo "  For indicator/script updates: refresh Navigator in MT5."
    echo "  ONLY restart container for config changes (servers.dat, common.ini)."
    # docker compose restart  # DISABLED per C4 — kills live EAs
    log "${name} terminal NOT restarted (bind mount picks up file changes)."
    log "Re-attach EAs manually via noVNC if you updated .ex5 files."
}

show_status() {
    echo ""
    echo "=== MQL Directory Status ==="
    echo ""

    echo "MQL4 (MT4):"
    if [ -d "$BASE_DIR/MT4/mql4/Experts" ]; then
        local count=$(find "$BASE_DIR/MT4/mql4/Experts" -name "*.ex4" 2>/dev/null | wc -l)
        echo "  Experts:  ${count} .ex4 files"
    fi
    if [ -d "$BASE_DIR/MT4/mql4/Indicators" ]; then
        local count=$(find "$BASE_DIR/MT4/mql4/Indicators" -name "*.ex4" 2>/dev/null | wc -l)
        echo "  Indicators: ${count} .ex4 files"
    fi
    if [ -d "$BASE_DIR/MT4/mql4/Scripts" ]; then
        local count=$(find "$BASE_DIR/MT4/mql4/Scripts" -name "*.ex4" 2>/dev/null | wc -l)
        echo "  Scripts:  ${count} .ex4 files"
    fi

    echo ""
    echo "MQL5 (MT5):"
    if [ -d "$BASE_DIR/MT5/mql5/Experts" ]; then
        local count=$(find "$BASE_DIR/MT5/mql5/Experts" -name "*.ex5" 2>/dev/null | wc -l)
        echo "  Experts:  ${count} .ex5 files"
    fi
    if [ -d "$BASE_DIR/MT5/mql5/Indicators" ]; then
        local count=$(find "$BASE_DIR/MT5/mql5/Indicators" -name "*.ex5" 2>/dev/null | wc -l)
        echo "  Indicators: ${count} .ex5 files"
    fi
    if [ -d "$BASE_DIR/MT5/mql5/Scripts" ]; then
        local count=$(find "$BASE_DIR/MT5/mql5/Scripts" -name "*.ex5" 2>/dev/null | wc -l)
        echo "  Scripts:  ${count} .ex5 files"
    fi

    echo ""
    echo "=== Container Status ==="
    echo ""
    docker ps --filter "name=mt4-terminal" --filter "name=mt5-terminal" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Main
TARGET="${1:-all}"

case "$TARGET" in
    mt4)
        sync_terminal "MT4" "mt4-terminal" "MT4"
        ;;
    mt5)
        sync_terminal "MT5" "mt5-terminal" "MT5"
        ;;
    all)
        sync_terminal "MT4" "mt4-terminal" "MT4"
        sync_terminal "MT5" "mt5-terminal" "MT5"
        ;;
    status)
        show_status
        exit 0
        ;;
    *)
        echo "Usage: $0 [mt4|mt5|all|status]"
        exit 1
        ;;
esac

show_status
