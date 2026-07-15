#!/bin/bash
# ============================================================================
# deploy-ea-bundle.sh — install a self-contained EA bundle into the MT5 stack
# ============================================================================
# A bundle is a directory containing (see QuantFin-R&D sets/v10-cent for the
# reference layout): <EA>.ex5, *.set presets, SHA256SUMS, optional src/ +
# manifest/ (audit-only).
#
# Copies runtime files into the bind-mounted MQL5 tree (mql4mt5/MQL5) so the
# running container picks them up, verifying integrity first. Re-run at every
# monthly retrain (the bundle is the redeployable unit: ex5 + sets refit
# together).
#
# Usage: ./deploy-ea-bundle.sh /path/to/bundle [--restart]
# ============================================================================
set -euo pipefail
BUNDLE="${1:?usage: deploy-ea-bundle.sh <bundle-dir> [--restart]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MQL5="$HERE/MT5/mql5"

[ -d "$BUNDLE" ] || { echo "no such bundle dir: $BUNDLE"; exit 1; }

if [ -f "$BUNDLE/SHA256SUMS" ]; then
    echo "[1/3] Verifying bundle integrity..."
    (cd "$BUNDLE" && sha256sum -c SHA256SUMS --quiet) && echo "  integrity OK"
else
    echo "[1/3] WARNING: no SHA256SUMS in bundle — skipping verification"
fi

echo "[2/3] Installing runtime files..."
mkdir -p "$MQL5/Experts" "$MQL5/Presets"
cnt_ex5=0; cnt_set=0
for f in "$BUNDLE"/*.ex5; do [ -e "$f" ] && cp -f "$f" "$MQL5/Experts/" && cnt_ex5=$((cnt_ex5+1)); done
for f in "$BUNDLE"/*.set; do [ -e "$f" ] && cp -f "$f" "$MQL5/Presets/" && cnt_set=$((cnt_set+1)); done
echo "  $cnt_ex5 ex5 -> MQL5/Experts/ ; $cnt_set set -> MQL5/Presets/"
[ "$cnt_ex5" -gt 0 ] || { echo "  ERROR: bundle contained no .ex5"; exit 1; }

echo "[3/3] Container pickup..."
if [ "${2:-}" = "--restart" ]; then
    echo "  WARNING: --restart flag used. This kills live EAs on charts!"
    echo "  Per project constraint C4: NEVER restart container for EA updates."
    echo "  Use manual re-attach via noVNC instead:"
    echo "    1. Right-click chart → Expert Advisors → Remove"
    echo "    2. Drag AccountSnapshot from Navigator → Experts onto chart"
    echo "    3. Confirm '[AccountSnapshot] v4.02 attached' in Experts log"
    # docker restart mt5-terminal  # DISABLED per C4
    echo "  (docker restart skipped — re-attach EA manually via noVNC)"
else
    echo "  Files are live via the bind mount."
    echo "  To activate new EA: re-attach manually via noVNC (see above)"
fi
echo "DONE. Verify in each chart's Experts journal that the EA banner shows"
echo "the expected model (e.g. 'MetaSystemV9 (141 trees)') before trusting."
