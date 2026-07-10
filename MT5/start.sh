#!/bin/bash
# Standalone MT5 Terminal — Headless Wine + Xvfb + noVNC
# Access via browser at http://localhost:6080
set -e

# ── Configuration ────────────────────────────────────────────────────────────
: "${DISPLAY:=:99}"
: "${WINEPREFIX:=/config/.wine}"
: "${MT5_BROKER_LOGIN:=}"
: "${MT5_BROKER_PASSWORD:=}"
: "${MT5_BROKER_SERVER:=MetaQuotes-Demo}"
: "${MT5_CMD_OPTIONS:=}"
: "${MT5_ENABLE_VNC:=}"
: "${MT5_ENABLE_NOVNC:=1}"
: "${MT5_NOVNC_PORT:=6080}"
: "${MT5_VNC_PORT:=5900}"

MT5_DIR="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
MT5_EXE="$MT5_DIR/terminal64.exe"
MONO_URL="https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  MetaTrader 5 Terminal — Docker Container               ║"
echo "║  Broker:   $MT5_BROKER_SERVER                           "
echo "║  Login:    ${MT5_BROKER_LOGIN:-offline}                 "
echo "║  Password: ${MT5_BROKER_PASSWORD:-(not set)}            "
echo "║  Wine:     $(wine --version 2>/dev/null || echo '?')    "
echo "║  noVNC:    http://localhost:$MT5_NOVNC_PORT             "
echo "╚══════════════════════════════════════════════════════════╝"

# ── Step 1: Start Xvfb ─────────────────────────────────────────────────────
rm -f /tmp/.X*-lock /tmp/.X11-unix/X*
echo "[1] Starting Xvfb on $DISPLAY (1280x1024x16)..."
Xvfb "$DISPLAY" -screen 0 1280x1024x16 -nolisten tcp +extension GLX +extension RANDR +extension RENDER &
# ponytail: -xkbdb not supported by Xvfb 21.x; keyboard via setxkbmap below
XVFB_PID=$!
sleep 2

# ── Step 1b: Set keyboard layout ───────────────────────────────────────────
echo "[1b] Setting keyboard layout..."
setxkbmap -layout us 2>/dev/null || true

# ── Step 2: Start fluxbox window manager ────────────────────────────────────
echo "[2] Starting fluxbox window manager..."
fluxbox 2>/dev/null &
sleep 1

# ── Step 3: Start x11vnc ───────────────────────────────────────────────────
echo "[3] Starting x11vnc on :$MT5_VNC_PORT..."
x11vnc -display "$DISPLAY" -forever -nopw -quiet -bg -rfbport "$MT5_VNC_PORT" -grabkbd 2>/dev/null || true

# ── Step 4: Start noVNC (web-based VNC client) ─────────────────────────────
if [ "$MT5_ENABLE_NOVNC" = "1" ]; then
    echo "[4] Starting noVNC on port $MT5_NOVNC_PORT..."
    # websockify proxies VNC (5900) to WebSocket (6080)
    # noVNC web client is served from /usr/share/novnc/
    websockify --web=/usr/share/novnc/ "$MT5_NOVNC_PORT" localhost:"$MT5_VNC_PORT" &
    NOVNC_PID=$!
    sleep 2
    echo "  ✅ noVNC accessible at http://localhost:$MT5_NOVNC_PORT"
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

# ── Step 6: Install Wine Mono (required by MT5) ────────────────────────────
if [ ! -d "$WINEPREFIX/drive_c/windows/mono" ]; then
    echo "[6] Installing Wine Mono..."
    curl -sL "$MONO_URL" -o /tmp/mono.msi
    WINEDLLOVERRIDES="mscoree=d" wine msiexec /i /tmp/mono.msi /qn 2>/dev/null || true
    rm -f /tmp/mono.msi
    echo "  ✅ Wine Mono installed"
else
    echo "[6] Wine Mono already installed"
fi

# ── Step 7: Install MT5 from pre-copied binaries ───────────────────────────
if [ -f "$MT5_EXE" ]; then
    echo "[7] MT5 already installed at $MT5_EXE"
else
    echo "[7] Installing MT5 from binaries..."
    wine winecfg -v win10 2>/dev/null || true
    mkdir -p "$MT5_DIR"
    if [ -d "/opt/mt5/mt5" ]; then
        cp -r /opt/mt5/mt5/* "$MT5_DIR/"
        echo "  ✅ MT5 binaries copied ($(du -sh "$MT5_DIR" | cut -f1))"
    else
        echo "  ❌ ERROR: No MT5 binaries at /opt/mt5/mt5"
        echo "  Place terminal64.exe and Config/ in mt5-bin/ directory"
    fi
fi

# ── Step 7b: Auto-import EAs and Indicators ────────────────────────────────
MT5_MQL5="$MT5_DIR/MQL5"
echo "[7b] Importing EAs and Indicators..."

# Copy EA .ex5 files from /opt/mt5/ea/Experts/ to MT5 Experts folder
if [ -d "/opt/mt5/ea/Experts" ] && [ "$(ls -A /opt/mt5/ea/Experts/ 2>/dev/null)" ]; then
    mkdir -p "$MT5_MQL5/Experts/Files"
    cp -v /opt/mt5/ea/Experts/*.ex5 "$MT5_MQL5/Experts/" 2>/dev/null || true
    echo "  ✅ EAs copied to MT5 Experts folder"
else
    echo "  ℹ️  No EAs found in ea/Experts/ (optional)"
fi

# Copy presets from ea/Presets/ (deploy-ea-bundle.sh puts them here)
if [ -d "/opt/mt5/ea/Presets" ] && [ "$(ls -A /opt/mt5/ea/Presets/ 2>/dev/null)" ]; then
    mkdir -p "$MT5_MQL5/Presets"
    cp -v /opt/mt5/ea/Presets/*.set "$MT5_MQL5/Presets/" 2>/dev/null || true
    echo "  ✅ Presets copied from ea/Presets/"
fi

# Copy Indicator .ex5 files
if [ -d "/opt/mt5/ea/Indicators" ] && [ "$(ls -A /opt/mt5/ea/Indicators/ 2>/dev/null)" ]; then
    mkdir -p "$MT5_MQL5/Indicators"
    cp -v /opt/mt5/ea/Indicators/*.ex5 "$MT5_MQL5/Indicators/" 2>/dev/null || true
    echo "  ✅ Indicators copied to MT5 Indicators folder"
else
    echo "  ℹ️  No Indicators found in ea/Indicators/ (optional)"
fi

# Copy Scripts
if [ -d "/opt/mt5/ea/Scripts" ] && [ "$(ls -A /opt/mt5/ea/Scripts/ 2>/dev/null)" ]; then
    mkdir -p "$MT5_MQL5/Scripts"
    cp -v /opt/mt5/ea/Scripts/*.ex5 "$MT5_MQL5/Scripts/" 2>/dev/null || true
    echo "  ✅ Scripts copied to MT5 Scripts folder"
else
    echo "  ℹ️  No Scripts found in ea/Scripts/ (optional)"
fi

# Copy config files (profiles, templates, presets)
if [ -d "/opt/mt5/config/profiles" ] && [ "$(ls -A /opt/mt5/config/profiles/ 2>/dev/null)" ]; then
    mkdir -p "$MT5_DIR/profiles"
    cp -rv /opt/mt5/config/profiles/* "$MT5_DIR/profiles/" 2>/dev/null || true
    echo "  ✅ Profiles copied"
fi

if [ -d "/opt/mt5/config/templates" ] && [ "$(ls -A /opt/mt5/config/templates/ 2>/dev/null)" ]; then
    mkdir -p "$MT5_DIR/templates"
    cp -rv /opt/mt5/config/templates/* "$MT5_DIR/templates/" 2>/dev/null || true
    echo "  ✅ Templates copied"
fi

if [ -d "/opt/mt5/config/presets" ] && [ "$(ls -A /opt/mt5/config/presets/ 2>/dev/null)" ]; then
    mkdir -p "$MT5_MQL5/Presets"
    cp -rv /opt/mt5/config/presets/* "$MT5_MQL5/Presets/" 2>/dev/null || true
    echo "  ✅ Presets copied"
fi

echo "  ✅ Import complete"

# ── Step 7c: Patch MT5 config with broker credentials ─────────────────────
COMMON_INI="$MT5_DIR/Config/common.ini"
patch_common_ini() {
    if [ -n "$MT5_BROKER_LOGIN" ] && [ -n "$MT5_BROKER_SERVER" ]; then
        echo "[7c] Writing common.ini with broker credentials..."
        # Always write a clean file. MT5 adds its own settings on top when it runs.
        # Avoids encoding corruption from trying to merge with MT5's UTF-16LE output.
        cat > "$COMMON_INI" <<'INIEOF'
[Common]
INIEOF
        echo "Login=$MT5_BROKER_LOGIN" >> "$COMMON_INI"
        echo "Server=$MT5_BROKER_SERVER" >> "$COMMON_INI"
        echo "Password=$MT5_BROKER_PASSWORD" >> "$COMMON_INI"
        echo "  ✅ common.ini written"
    else
        echo "[7c] No credentials set, skipping config patch"
    fi
}
patch_common_ini

# ── Step 8: Start MT5 terminal ─────────────────────────────────────────────
echo "[8] Launching MT5 Terminal..."
cd "$MT5_DIR"

# SECURITY: credentials go through MT5's startup-config ini, NEVER through
# /login:/password: command-line args (args are visible to every process on
# the HOST via ps — this leaked a real password once). The ini also bakes in
# production settings: algo trading enabled + the MaxBars RAM cap.
mkdir -p "$MT5_DIR/Config"
AUTOSTART_INI="$MT5_DIR/Config/autostart.ini"
{
    if [ -n "${MT5_BROKER_LOGIN}" ] && [ -n "${MT5_BROKER_PASSWORD}" ]; then
        echo "[Common]"
        echo "Login=${MT5_BROKER_LOGIN}"
        echo "Password=${MT5_BROKER_PASSWORD}"
        echo "Server=${MT5_BROKER_SERVER}"
        echo "KeepPrivate=1"
        echo "NewsEnable=0"
    fi
    echo "[Experts]"
    echo "AllowLiveTrading=1"
    echo "AllowDllImport=0"
    echo "Enabled=1"
    echo "[Charts]"
    echo "MaxBars=${MT5_MAX_BARS:-5000}"
} > "$AUTOSTART_INI"
chmod 600 "$AUTOSTART_INI"

# .bat launcher — cmd.exe treats @ as literal, avoiding start.exe misparse;
# only the ini PATH appears in the process list now.
LAUNCHER="$MT5_DIR/start_mt5.bat"
cat > "$LAUNCHER" <<BATEOF
@echo off
"C:\Program Files\MetaTrader 5\terminal64.exe" /portable "/config:C:\Program Files\MetaTrader 5\Config\autostart.ini"
BATEOF

wine cmd.exe /c "$LAUNCHER" 2>&1 &
MT5_PID=$!
echo "  PID: $MT5_PID"

# Remove the plaintext ini once the terminal has read it (credentials persist
# in the terminal's own encrypted accounts store after the first login).
( sleep 90 && (shred -u "$AUTOSTART_INI" 2>/dev/null || rm -f "$AUTOSTART_INI") ) &

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
echo "║  MT5 Terminal Running                                    ║"
echo "║  PID:      $MT5_PID                                      "
echo "║  Broker:   ${MT5_BROKER_LOGIN:-offline}@${MT5_BROKER_SERVER}  "
echo "║  Wine:     $(wine --version 2>/dev/null || echo '?')     "
echo "║                                                          "
echo "║  Access via:                                             "
echo "║    noVNC:  http://localhost:$MT5_NOVNC_PORT              "
if [ "$MT5_ENABLE_VNC" = "1" ]; then
echo "║    VNC:    localhost:$MT5_VNC_PORT                        "
fi
echo "╚══════════════════════════════════════════════════════════╝"

# ── Cleanup handler ─────────────────────────────────────────────────────────
cleanup() {
    echo "Shutting down..."
    kill $MT5_PID 2>/dev/null || true
    kill $XVFB_PID 2>/dev/null || true
    kill $NOVNC_PID 2>/dev/null || true
    wait 2>/dev/null || true
    echo "Stopped."
}
trap cleanup SIGTERM SIGINT

# ── Helper: restart x11vnc if it dies ──────────────────────────────────────
ensure_x11vnc() {
    if ! pgrep -f x11vnc >/dev/null 2>&1; then
        echo "  x11vnc died, restarting..."
        x11vnc -display "$DISPLAY" -forever -nopw -quiet -bg -rfbport "$MT5_VNC_PORT" -grabkbd 2>/dev/null || true
    fi
}

# ── Helper: restart websockify if it dies ───────────────────────────────────
ensure_websockify() {
    if ! pgrep -f websockify >/dev/null 2>&1; then
        echo "  websockify died, restarting..."
        websockify --web=/usr/share/novnc/ "$MT5_NOVNC_PORT" localhost:"$MT5_VNC_PORT" &
        sleep 1
    fi
}

# ── Monitor loop (restart MT5 + display stack if they crash) ───────────────
RESTART_COUNT=0
while true; do
    ensure_x11vnc
    ensure_websockify
    if ! kill -0 $MT5_PID 2>/dev/null; then
        RESTART_COUNT=$((RESTART_COUNT + 1))
        echo "WARNING: MT5 process died. Restarting (#$RESTART_COUNT)..."
        # Re-patch common.ini (MT5 may have overwritten it)
        patch_common_ini
        cd "$MT5_DIR"
        wine cmd.exe /c "$LAUNCHER" 2>&1 &
        MT5_PID=$!
        echo "  New PID: $MT5_PID"
        sleep 15
    fi
    sleep 10
done
