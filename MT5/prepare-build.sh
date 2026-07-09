#!/bin/bash
# Prepare MT5 Docker build by copying binaries from local installation
# Usage: bash prepare-build.sh

set -e

# Find MT5 binary in standard locations
MT5_SOURCE=""
if [ -f "$HOME/.local/share/bottles/bottles/Apps/drive_c/Program Files/MetaTrader 5/terminal64.exe" ]; then
    MT5_SOURCE="$HOME/.local/share/bottles/bottles/Apps/drive_c/Program Files/MetaTrader 5"
elif [ -f "$HOME/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe" ]; then
    MT5_SOURCE="$HOME/.wine/drive_c/Program Files/MetaTrader 5"
elif [ -f "/mnt/c/Program Files/MetaTrader 5/terminal64.exe" ]; then
    MT5_SOURCE="/mnt/c/Program Files/MetaTrader 5"
elif [ -f "$HOME/.local/share/bottles/bottles/MT5/drive_c/Program Files/MetaTrader 5/terminal64.exe" ]; then
    MT5_SOURCE="$HOME/.local/share/bottles/bottles/MT5/drive_c/Program Files/MetaTrader 5"
else
    echo "ERROR: MT5 terminal64.exe not found."
    echo ""
    echo "Searched locations:"
    echo "  - ~/.local/share/bottles/bottles/Apps/drive_c/Program Files/MetaTrader 5/"
    echo "  - ~/.wine/drive_c/Program Files/MetaTrader 5/"
    echo "  - /mnt/c/Program Files/MetaTrader 5/"
    echo ""
    echo "Please copy terminal64.exe to ./mt5-bin/ manually."
    exit 1
fi

DEST="$(dirname "$0")/mt5-bin"
mkdir -p "$DEST"

echo "Copying MT5 binaries from:"
echo "  Source: $MT5_SOURCE"
echo "  Dest:   $DEST"

# Copy terminal executable
cp "$MT5_SOURCE/terminal64.exe" "$DEST/"
echo "  ✅ terminal64.exe ($(du -h "$MT5_SOURCE/terminal64.exe" | cut -f1))"

# Copy minimal config (optional)
if [ -d "$MT5_SOURCE/Config" ]; then
    mkdir -p "$DEST/Config"
    cp -r "$MT5_SOURCE/Config/"* "$DEST/Config/" 2>/dev/null || true
    echo "  ✅ Config/"
fi

echo ""
echo "Done. MT5 binaries ready for Docker build."
echo "Total: $(du -sh "$DEST" | cut -f1)"
