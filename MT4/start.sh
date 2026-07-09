#!/bin/bash
# Standalone MT4 Terminal — Headless Wine + Xvfb + noVNC
# Access via browser at http://localhost:6080
set -e

# ── Configuration ────────────────────────────────────────────────────────────
: "${DISPLAY:=:99}"
: "${WINEPREFIX:=/config/.wine}"
: "${MT4_BROKER_LOGIN:=}"
: "${MT4_BROKER_PASSWORD:=}"
: "${MT4_BROKER_SERVER:=MetaQuotes-Demo}"
: "${MT4_CMD_OPTIONS:=}"
: "${MT4_ENABLE_VNC:=}"
: "${MT4_ENABLE_NOVNC:=1}"
: "${MT4_NOVNC_PORT:=6080}"
: "${MT4_VNC_PORT:=5900}"

MT4_DIR="$WINEPREFIX/drive_c/Program Files (x86)/MetaTrader 4"
MT4_EXE="$MT4_DIR/terminal.exe"
MONO_URL="https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  MetaTrader 4 Terminal — Docker Container               ║"
echo "║  Broker:   $MT4_BROKER_SERVER                           "
echo "║  Login:    ${MT4_BROKER_LOGIN:-offline}                 "
echo "║  Password: ${MT4_BROKER_PASSWORD:-(not set)}            "
echo "║  Wine:     $(wine --version 2>/dev/null || echo '?')    "
echo "║  noVNC:    http://localhost:$MT4_NOVNC_PORT             "
echo "╚══════════════════════════════════════════════════════════╝"

# ── Step 1: Start Xvfb ─────────────────────────────────────────────────────
rm -f /tmp/.X*-lock /tmp/.X11-unix/X*
echo "[1] Starting Xvfb on $DISPLAY (1280x1024x16)..."
Xvfb "$DISPLAY" -screen 0 1280x1024x16 -nolisten tcp &
XVFB_PID=$!
sleep 2

# ── Step 2: Start fluxbox window manager ────────────────────────────────────
echo "[2] Starting fluxbox window manager..."
fluxbox 2>/dev/null &
sleep 1

# ── Step 3: Start x11vnc ───────────────────────────────────────────────────
echo "[3] Starting x11vnc on :$MT4_VNC_PORT..."
x11vnc -display "$DISPLAY" -forever -nopw -quiet -bg -rfbport "$MT4_VNC_PORT" -grabkbd 2>/dev/null || true

# ── Step 4: Start noVNC (web-based VNC client) ─────────────────────────────
if [ "$MT4_ENABLE_NOVNC" = "1" ]; then
    echo "[4] Starting noVNC on port $MT4_NOVNC_PORT..."
    websockify --web=/usr/share/novnc/ "$MT4_NOVNC_PORT" localhost:"$MT4_VNC_PORT" &
    NOVNC_PID=$!
    sleep 2
    echo "  ✅ noVNC accessible at http://localhost:$MT4_NOVNC_PORT"
fi

# ── Step 5: Initialize Wine prefix (first run only) ─────────────────────────
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "[5] Initializing Wine prefix (first run)..."
    WINEDLLOVERRIDES="mscoree,mshtml=" wine wineboot --init 2>/dev/null || true
    sleep 3
    echo "  ✅ Wine prefix initialized at $WINEPREFIX"
else
    echo "[5] Wine prefix already exists"
fi

# ── Step 6: Install Wine Mono ───────────────────────────────────────────────
if [ ! -d "$WINEPREFIX/drive_c/windows/mono" ]; then
    echo "[6] Installing Wine Mono..."
    curl -sL "$MONO_URL" -o /tmp/mono.msi
    WINEDLLOVERRIDES="mscoree=d" wine msiexec /i /tmp/mono.msi /qn 2>/dev/null || true
    rm -f /tmp/mono.msi
    echo "  ✅ Wine Mono installed"
else
    echo "[6] Wine Mono already installed"
fi

# ── Step 7: Install MT4 from pre-copied binaries ───────────────────────────
if [ -f "$MT4_EXE" ]; then
    echo "[7] MT4 already installed at $MT4_EXE"
else
    echo "[7] Installing MT4 from binaries..."
    wine winecfg -v win10 2>/dev/null || true
    mkdir -p "$MT4_DIR"
    if [ -d "/opt/mt4/mt4" ]; then
        cp -r /opt/mt4/mt4/* "$MT4_DIR/"
        echo "  ✅ MT4 binaries copied ($(du -sh "$MT4_DIR" | cut -f1))"
    else
        echo "  ❌ ERROR: No MT4 binaries at /opt/mt4/mt4"
        echo "  Place terminal.exe and Config/ in mt4-bin/ directory"
    fi
fi

# ── Step 7b: Auto-import EAs and Indicators ────────────────────────────────
MT4_MQL4="$MT4_DIR/MQL4"
echo "[7b] Importing EAs and Indicators..."

# Copy EA .ex4 files from /opt/mt4/ea/Experts/ to MT4 Experts folder
if [ -d "/opt/mt4/ea/Experts" ] && [ "$(ls -A /opt/mt4/ea/Experts/ 2>/dev/null)" ]; then
    mkdir -p "$MT4_MQL4/Experts/Files"
    cp -v /opt/mt4/ea/Experts/*.ex4 "$MT4_MQL4/Experts/" 2>/dev/null || true
    cp -v /opt/mt4/ea/Experts/*.set "$MT4_MQL4/Presets/" 2>/dev/null || true
    echo "  ✅ EAs copied to MT4 Experts folder"
else
    echo "  ℹ️  No EAs found in ea/Experts/ (optional)"
fi

# Copy Indicator .ex4 files
if [ -d "/opt/mt4/ea/Indicators" ] && [ "$(ls -A /opt/mt4/ea/Indicators/ 2>/dev/null)" ]; then
    mkdir -p "$MT4_MQL4/Indicators"
    cp -v /opt/mt4/ea/Indicators/*.ex4 "$MT4_MQL4/Indicators/" 2>/dev/null || true
    echo "  ✅ Indicators copied to MT4 Indicators folder"
else
    echo "  ℹ️  No Indicators found in ea/Indicators/ (optional)"
fi

# Copy Scripts
if [ -d "/opt/mt4/ea/Scripts" ] && [ "$(ls -A /opt/mt4/ea/Scripts/ 2>/dev/null)" ]; then
    mkdir -p "$MT4_MQL4/Scripts"
    cp -v /opt/mt4/ea/Scripts/*.ex4 "$MT4_MQL4/Scripts/" 2>/dev/null || true
    echo "  ✅ Scripts copied to MT4 Scripts folder"
else
    echo "  ℹ️  No Scripts found in ea/Scripts/ (optional)"
fi

# Copy config files (profiles, templates, presets)
if [ -d "/opt/mt4/config/profiles" ] && [ "$(ls -A /opt/mt4/config/profiles/ 2>/dev/null)" ]; then
    mkdir -p "$MT4_DIR/profiles"
    cp -rv /opt/mt4/config/profiles/* "$MT4_DIR/profiles/" 2>/dev/null || true
    echo "  ✅ Profiles copied"
fi

if [ -d "/opt/mt4/config/templates" ] && [ "$(ls -A /opt/mt4/config/templates/ 2>/dev/null)" ]; then
    mkdir -p "$MT4_DIR/templates"
    cp -rv /opt/mt4/config/templates/* "$MT4_DIR/templates/" 2>/dev/null || true
    echo "  ✅ Templates copied"
fi

if [ -d "/opt/mt4/config/presets" ] && [ "$(ls -A /opt/mt4/config/presets/ 2>/dev/null)" ]; then
    mkdir -p "$MT4_MQL4/Presets"
    cp -rv /opt/mt4/config/presets/* "$MT4_MQL4/Presets/" 2>/dev/null || true
    echo "  ✅ Presets copied"
fi

echo "  ✅ Import complete"

# ── Step 7c: Patch MT4 config with broker credentials ──────────────────────
# MT4 stores config in config.ini (not common.ini)
CONFIG_INI="$MT4_DIR/config.ini"
if [ -n "$MT4_BROKER_LOGIN" ] && [ -n "$MT4_BROKER_SERVER" ]; then
    echo "[7c] Patching config.ini with broker credentials..."
    # Create or update config.ini
    cat > "$CONFIG_INI" <<CFGEOF
[Connection]
Login=$MT4_BROKER_LOGIN
Password=$MT4_BROKER_PASSWORD
Server=$MT4_BROKER_SERVER
CFGEOF
    echo "  ✅ config.ini patched"
else
    echo "[7c] No credentials set, skipping config patch"
fi

# ── Step 8: Start MT4 terminal ─────────────────────────────────────────────
echo "[8] Launching MT4 Terminal..."
cd "$MT4_DIR"

# Write .bat to /tmp to avoid Wine path issues with spaces
cat > /tmp/start_mt4.bat <<'BATEOF'
@echo off
"C:\Program Files (x86)\MetaTrader 4\terminal.exe" /portable
BATEOF

LAUNCHER="/tmp/start_mt4.bat"

wine cmd.exe /c "$LAUNCHER" 2>&1 &
MT4_PID=$!
echo "  PID: $MT4_PID"

# ── Step 9: Clean up unnecessary Wine processes ─────────────────────────────
echo "[9] Cleaning up unnecessary Wine processes..."
for pid in $(pgrep -f "explorer.exe" 2>/dev/null); do
    kill "$pid" 2>/dev/null || true
done
for pid in $(pgrep -f "wineconsole" 2>/dev/null); do
    kill "$pid" 2>/dev/null || true
done

# ── Step 10: Status ────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  MT4 Terminal Running                                    ║"
echo "║  PID:      $MT4_PID                                      "
echo "║  Broker:   ${MT4_BROKER_LOGIN:-offline}@${MT4_BROKER_SERVER}  "
echo "║  Wine:     $(wine --version 2>/dev/null || echo '?')     "
echo "║                                                          "
echo "║  Access via:                                             "
echo "║    noVNC:  http://localhost:$MT4_NOVNC_PORT              "
if [ "$MT4_ENABLE_VNC" = "1" ]; then
echo "║    VNC:    localhost:$MT4_VNC_PORT                        "
fi
echo "╚══════════════════════════════════════════════════════════╝"

# ── Cleanup handler ─────────────────────────────────────────────────────────
cleanup() {
    echo "Shutting down..."
    kill $MT4_PID 2>/dev/null || true
    kill $XVFB_PID 2>/dev/null || true
    kill $NOVNC_PID 2>/dev/null || true
    wait 2>/dev/null || true
    echo "Stopped."
}
trap cleanup SIGTERM SIGINT

# ── Monitor loop (restart MT4 + services if they crash) ───────────────────
RESTART_COUNT=0
ensure_x11vnc() {
    if ! pgrep -x x11vnc >/dev/null 2>&1; then
        echo "  x11vnc died, restarting..."
        x11vnc -display "$DISPLAY" -forever -nopw -quiet -bg -rfbport "$MT4_VNC_PORT" -grabkbd 2>/dev/null || true
        sleep 2
    fi
}
ensure_websockify() {
    if [ "$MT4_ENABLE_NOVNC" = "1" ] && ! kill -0 $NOVNC_PID 2>/dev/null; then
        echo "  websockify died, restarting..."
        websockify --web=/usr/share/novnc/ "$MT4_NOVNC_PORT" localhost:"$MT4_VNC_PORT" &
        NOVNC_PID=$!
        sleep 2
    fi
}
while true; do
    ensure_x11vnc
    ensure_websockify
    if ! kill -0 $MT4_PID 2>/dev/null; then
        RESTART_COUNT=$((RESTART_COUNT + 1))
        echo "WARNING: MT4 process died. Restarting (#$RESTART_COUNT)..."
        ensure_x11vnc
        cd "$MT4_DIR"
        wine cmd.exe /c "$LAUNCHER" 2>&1 &
        MT4_PID=$!
        echo "  New PID: $MT4_PID"
        sleep 15
    fi
    sleep 10
done
