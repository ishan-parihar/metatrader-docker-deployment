#!/usr/bin/env bash
# ============================================================================
# install.sh — One-shot installer for the MT5 monitoring stack
# ============================================================================
# Deploys:
#   ~/mt5-monitoring/
#     ├── bin/          (all scripts)
#     ├── state/        (logs)
#     └── reports/      (health check reports)
#   /etc/systemd/system/mt5-*.{service,timer}
#
# Run from the repo root:
#   ./monitoring/install.sh
#
# Or from anywhere:
#   bash monitoring/install.sh
#
# Prerequisites:
#   - Docker (for reading MT5 container logs)
#   - python3 (for the scripts)
#   - systemd (for the timers)
#   - alert.conf already configured at monitoring/config/alert.conf
#     (copy from alert.conf.example and fill in credentials)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_DIR="${HOME}/mt5-monitoring"
USER_NAME="$(whoami)"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  MT5 Monitoring Stack — Installer                       ║"
echo "║  Install dir: ${INSTALL_DIR}                           "
echo "║  User:        ${USER_NAME}                              "
echo "║  Repo:        ${REPO_DIR}                               "
echo "╚══════════════════════════════════════════════════════════╝"

# ── 1. Create install directory ────────────────────────────────────────────
echo ""
echo "[1/5] Creating install directory..."
mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/state" "${INSTALL_DIR}/reports"

# ── 2. Copy scripts ──────────────────────────────────────────────────────
echo "[2/5] Copying scripts..."
cp -f "${SCRIPT_DIR}/bin/"* "${INSTALL_DIR}/bin/"
chmod +x "${INSTALL_DIR}/bin/"*.sh "${INSTALL_DIR}/bin/mt5ctl" "${INSTALL_DIR}/bin/"*.py
echo "  $(ls "${INSTALL_DIR}/bin/" | wc -l) files copied"

# ── 3. Copy alert config ──────────────────────────────────────────────────
echo "[3/5] Setting up alert config..."
if [ -f "${SCRIPT_DIR}/config/alert.conf" ]; then
    # Real config exists in repo (shouldn't normally be committed)
    cp -f "${SCRIPT_DIR}/config/alert.conf" "${INSTALL_DIR}/config/alert.conf"
    chmod 600 "${INSTALL_DIR}/config/alert.conf"
    echo "  Using alert.conf from repo (chmod 600)"
elif [ -f "${INSTALL_DIR}/config/alert.conf" ]; then
    echo "  Using existing alert.conf at ${INSTALL_DIR}/config/alert.conf"
else
    cp -f "${SCRIPT_DIR}/config/alert.conf.example" "${INSTALL_DIR}/config/alert.conf"
    chmod 600 "${INSTALL_DIR}/config/alert.conf"
    echo "  ⚠️  Created alert.conf from template — EDIT IT before enabling alerts!"
    echo "     ${INSTALL_DIR}/config/alert.conf"
fi

# ── 4. Install systemd units ─────────────────────────────────────────────
echo "[4/5] Installing systemd units (requires sudo)..."

if ! command -v systemctl >/dev/null 2>&1; then
    echo "  ⚠️  systemctl not found — skipping systemd setup"
    echo "     Run the scripts manually or set up your own scheduler"
else
    sudo -n true 2>/dev/null || {
        echo "  ⚠️  sudo requires password — skipping systemd setup"
        echo "     Run with sudo, or install units manually:"
        echo "     sudo cp ${SCRIPT_DIR}/systemd/*.service ${SCRIPT_DIR}/systemd/*.timer /etc/systemd/system/"
        echo "     sudo systemctl daemon-reload"
        SUDO_OK=false
    }

    if [ "${SUDO_OK:-true}" != "false" ]; then
        for unit_file in "${SCRIPT_DIR}/systemd/"*.service "${SCRIPT_DIR}/systemd/"*.timer; do
            unit_name="$(basename "$unit_file")"
            # Substitute %USER and %HOME
            sed -e "s|%USER|${USER_NAME}|g" -e "s|%HOME|${HOME}|g" \
                "$unit_file" | sudo tee "/etc/systemd/system/${unit_name}" > /dev/null
            echo "  installed /etc/systemd/system/${unit_name}"
        done

        sudo systemctl daemon-reload
        sudo systemctl enable mt5-logcheck.timer \
                              mt5-summary-daily.timer \
                              mt5-summary-weekly.timer \
                              mt5-bot.service
        sudo systemctl start mt5-logcheck.timer \
                             mt5-summary-daily.timer \
                             mt5-summary-weekly.timer \
                             mt5-bot.service
        echo ""
        echo "  systemd timers:"
        sudo systemctl list-timers mt5-* --no-pager || true
    fi
fi

# ── 5. Verify ─────────────────────────────────────────────────────────────
echo ""
echo "[5/5] Verifying installation..."
echo "  Scripts:"
ls -la "${INSTALL_DIR}/bin/" | tail -n +2 | awk '{print "    " $9 " (" $5 " bytes)"}'
echo ""
echo "  Config:"
ls -la "${INSTALL_DIR}/config/" | tail -n +2 | awk '{print "    " $9 " (" $5 " bytes, " $1 ")"}'

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Installation complete!                                  ║"
echo "║                                                          ║"
echo "║  Quick start:                                           ║"
echo "║    export PATH=\"\$HOME/mt5-monitoring/bin:\$PATH\"        ║"
echo "║    mt5ctl status              # 1-line health           ║"
echo "║    mt5ctl dashboard           # full dashboard          ║"
echo "║    mt5ctl dashboard drawdown  # peak equity + drawdown  ║"
echo "║    mt5ctl health              # full health check       ║"
echo "║    mt5ctl charts              # chart attach status     ║"
echo "║    mt5ctl alert test          # test email + Telegram   ║"
echo "║                                                          ║"
echo "║  Telegram bot commands (after attaching the EA):        ║"
echo "║    /dashboard /positions /history /exposure /drawdown   ║"
echo "║    /risk /orders /equity /rolling                       ║"
echo "║    /status /health /charts /help                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
