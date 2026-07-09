#!/bin/bash
# sync-mql.sh - Refresh MT4/MT5 terminals to pick up new EA/Indicator/Script files
#
# Usage:
#   ./sync-mql.sh [mt4|mt5|all]
#
# When to run:
#   - After adding new .ex4/.ex5 files to mql4mt5/MQL4 or mql4mt5/MQL5
#   - After modifying existing EA/Indicator/Script files
#   - After changing config files in mql4mt5/config/

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
MQL_DIR="$BASE_DIR/mql4mt5"

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

    log "Restarting ${name} terminal to pick up changes..."
    cd "$BASE_DIR/$dir"
    docker compose restart
    cd "$BASE_DIR"

    # Wait for terminal to be ready
    sleep 10

    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log "${name} terminal restarted successfully"
    else
        err "${name} terminal failed to start"
        return 1
    fi
}

show_status() {
    echo ""
    echo "=== MQL Directory Status ==="
    echo ""

    echo "MQL4 (MT4):"
    if [ -d "$MQL_DIR/MQL4/Experts" ]; then
        local count=$(find "$MQL_DIR/MQL4/Experts" -name "*.ex4" 2>/dev/null | wc -l)
        echo "  Experts:  ${count} .ex4 files"
    fi
    if [ -d "$MQL_DIR/MQL4/Indicators" ]; then
        local count=$(find "$MQL_DIR/MQL4/Indicators" -name "*.ex4" 2>/dev/null | wc -l)
        echo "  Indicators: ${count} .ex4 files"
    fi
    if [ -d "$MQL_DIR/MQL4/Scripts" ]; then
        local count=$(find "$MQL_DIR/MQL4/Scripts" -name "*.ex4" 2>/dev/null | wc -l)
        echo "  Scripts:  ${count} .ex4 files"
    fi

    echo ""
    echo "MQL5 (MT5):"
    if [ -d "$MQL_DIR/MQL5/Experts" ]; then
        local count=$(find "$MQL_DIR/MQL5/Experts" -name "*.ex5" 2>/dev/null | wc -l)
        echo "  Experts:  ${count} .ex5 files"
    fi
    if [ -d "$MQL_DIR/MQL5/Indicators" ]; then
        local count=$(find "$MQL_DIR/MQL5/Indicators" -name "*.ex5" 2>/dev/null | wc -l)
        echo "  Indicators: ${count} .ex5 files"
    fi
    if [ -d "$MQL_DIR/MQL5/Scripts" ]; then
        local count=$(find "$MQL_DIR/MQL5/Scripts" -name "*.ex5" 2>/dev/null | wc -l)
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
        sync_terminal "MT4" "mt4-terminal" "MT4-docker-general"
        ;;
    mt5)
        sync_terminal "MT5" "mt5-terminal" "MT5-docker-general"
        ;;
    all)
        sync_terminal "MT4" "mt4-terminal" "MT4-docker-general"
        sync_terminal "MT5" "mt5-terminal" "MT5-docker-general"
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
