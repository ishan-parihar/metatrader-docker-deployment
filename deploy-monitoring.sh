#!/bin/bash
# ============================================================================
# deploy-monitoring.sh — One-command deployment of the MT5 monitoring stack
# ============================================================================
# Wrapper around monitoring/install.sh for convenience. Use this from the
# repo root after a fresh `./deploy-mt5.sh` to add health monitoring,
# alerting, and the Telegram bot.
#
# Usage:
#   ./deploy-monitoring.sh
#
# Prerequisites:
#   - MT5 stack already deployed (./deploy-mt5.sh)
#   - monitoring/config/alert.conf configured (copy from .example)
# ============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "${HERE}/monitoring" ]; then
    echo "ERROR: monitoring/ directory not found at ${HERE}/monitoring"
    exit 1
fi

echo "Deploying MT5 monitoring stack..."
bash "${HERE}/monitoring/install.sh"
