"""stream_defs.py — single source of truth for strategy definitions.

LIVE = the currently deployed book (generated from the EA bundle's *.set
files via gen_stream_defs.py — never hand-edit the LIVE block).
LEGACY_* = frozen reference for the superseded metals-8/101-tree system
(retired 2026-09-06). Kept so old logs/reports stay interpretable.

Consumers: mt5ctl, mt5_bot.py, mt5_logcheck.py. No third-party deps.

Era rule: magic numbers were recycled across deployments, so a magic only
means a v16 stream for trades closed at/after DEPLOYED_UTC. Use era_of() /
era_label() for ANY per-trade attribution — never label history by magic alone.

Model lineage (verified: pioneer-qf live-audit-2026-08, PROGRESS):
  legacy-p1  141-tree July book       (deposit to 2026-07-30, DD trough ~6.25k)
  legacy-p2  231-tree post-redeploy   (2026-07-30 to 2026-08-31, recovery)
  legacy-p3  101-tree book            (2026-08-31 to 2026-09-06; only closes are
                                       4 leftover positions, opened Sep 2-3,
                                       manually bulk-closed Sep 7 00:58:41)
  v16        300-tree current book    (2026-09-06T00:01:00Z onward)
There is no 242-tree artifact (the 231-tree retrain); the staged 152-tree
bundle was never deployed.
"""
from datetime import datetime as _dt

SNAP_TS_FMT = "%Y.%m.%d %H:%M:%S"  # AccountSnapshot time format (server clock ~= UTC)
# ── LIVE (generated 2026-09-06T00:01:00Z — DO NOT HAND-EDIT) ──
# Source: v16-accelerated-cent bundle (*.set). Regenerate with:
#   gen_stream_defs.py --bundle-dir <dir> --trees 300 --label v16-accelerated-cent --deployed-utc <ts>
DEPLOY_LABEL = "v16-accelerated-cent"
DEPLOYED_UTC = "2026-09-06T00:01:00Z"
MODEL_TREES = 300
LIVE_STREAMS = {
    992101: {"symbol": "BTCUSDc", "tf": "M15", "atom": "asia_orb", "tag": "asia", "label": "BTC M15 asia", "threshold": -0.0994617245085, "tp_r": 2.2, "sl_atr": 6.0, "risk_pct": 2.0, "atom_code": 0},
    992102: {"symbol": "BTCUSDc", "tf": "M15", "atom": "h1_pullback_bb", "tag": "pbbb", "label": "BTC M15 pbbb", "threshold": -0.00418955101002, "tp_r": 2.6, "sl_atr": 4.0, "risk_pct": 0.5, "atom_code": 8},
    992103: {"symbol": "GBPJPYc", "tf": "M15", "atom": "bb_squeeze_atr_spike", "tag": "sqbd", "label": "GBP M15 sqbd", "threshold": -0.0779323584245, "tp_r": 1.8, "sl_atr": 5.0, "risk_pct": 4.5, "atom_code": 2},
    992104: {"symbol": "GBPJPYc", "tf": "M15", "atom": "bb_squeeze_atr_spike_h1", "tag": "sqh1", "label": "GBP M15 sqh1", "threshold": -0.0696139428105, "tp_r": 1.2, "sl_atr": 8.0, "risk_pct": 4.0, "atom_code": 3},
    992105: {"symbol": "GBPJPYc", "tf": "M15", "atom": "ny_orb", "tag": "ny", "label": "GBP M15 ny", "threshold": -0.0876668104214, "tp_r": 1.2, "sl_atr": 8.0, "risk_pct": 4.0, "atom_code": 12},
    992106: {"symbol": "GBPJPYc", "tf": "M5", "atom": "asia_orb", "tag": "asia", "label": "GBP M5 asia", "threshold": -0.0704493059887, "tp_r": 3.6, "sl_atr": 4.0, "risk_pct": 0.5, "atom_code": 0},
    992107: {"symbol": "XAGUSDc", "tf": "M15", "atom": "london_orb", "tag": "lon", "label": "XAG M15 lon", "threshold": -0.0370110096739, "tp_r": 4.2, "sl_atr": 8.0, "risk_pct": 3.5, "atom_code": 10},
    992108: {"symbol": "XAUUSDc", "tf": "M15", "atom": "compression_h1_trend", "tag": "comp", "label": "XAU M15 comp", "threshold": 0.105474880203, "tp_r": 2.2, "sl_atr": 8.0, "risk_pct": 0.5, "atom_code": 4},
    992109: {"symbol": "XAUUSDc", "tf": "M15", "atom": "monthly_momentum", "tag": "mon", "label": "XAU M15 mon", "threshold": 0.0705154798464, "tp_r": 5.0, "sl_atr": 6.0, "risk_pct": 11.5, "atom_code": 11},
}

# ── Governor (live, AD-19 + AD-18 graduation freeze) ──
GOVERNOR = {
    "trail_pct": 40.0,
    "ratchet_pct": 0.0,
    "graduation_freeze_usc": 100000,
    "magic": 992110,
    "snapshot_magic": 992111,
}

# ── LEGACY (frozen 2026-09-06 — retired metals-8/101-tree book) ──
LEGACY_LABEL = "metals-8-101tree"
LEGACY_RETIRED_UTC = "2026-09-06T00:01:00Z"
LEGACY_TREES = 101
LEGACY_STREAMS = {
    992101: {"symbol": "XAUUSDc", "tf": "M5", "atom": "ny_orb",
              "label": "XAU M5 ny_orb"},
    992102: {"symbol": "XAGUSDc", "tf": "M15", "atom": "ny_orb",
              "label": "XAG M15 ny_orb"},
    992103: {"symbol": "XAUUSDc", "tf": "M5", "atom": "d1_momentum",
              "label": "XAU M5 d1_mom"},
    992104: {"symbol": "XAGUSDc", "tf": "M15", "atom": "london_orb",
              "label": "XAG M15 lon_orb"},
    992105: {"symbol": "XAUUSDc", "tf": "M15", "atom": "london_orb",
              "label": "XAU M15 lon_orb"},
    992106: {"symbol": "XAUUSDc", "tf": "M5", "atom": "monthly_momentum",
              "label": "XAU M5 mon_mom"},
    992107: {"symbol": "XAUUSDc", "tf": "M15", "atom": "ny_orb",
              "label": "XAU M15 ny_orb"},
    992108: {"symbol": "XAUUSDc", "tf": "M15", "atom": "d1_momentum",
              "label": "XAU M15 d1_mom"},
}
LEGACY_GOVERNOR_TRAIL_PCT = 35.0

# ── Symbol contract sizes (Exness cent account) ──
# SYMBOL_TRADE_CONTRACT_SIZE returns values that inflated pnl_pct ~100x in
# this terminal, so the real specs below are authoritative for XAU/XAG.
# Unknown symbols return None → ROI display is omitted, never guessed.
# Fill BTC/GBP from a LiveAutopsy *_symbols.csv export when available.
CONTRACT_SIZES = {
    "XAUUSD": 100, "XAGUSD": 5000,
    "XAUUSDc": 100, "XAGUSDc": 5000,
    "XAUEUR": 100, "XAGEUR": 5000,
}

ACCOUNT_START_BALANCE = 8397.0  # Jul-10 deposit (USC); balance-curve anchor

# (era_id, start_inclusive or None, end_exclusive or None), UTC-naive.
# Cuts sit in trade gaps (no closes Jul 27-30, none Aug 31-Sep 6), so they
# are exact for close-time attribution despite coarse (date) precision.
ERA_CUTS = [
    ("legacy-p1-141", None, "2026-07-30T00:00:00Z"),
    ("legacy-p2-231", "2026-07-30T00:00:00Z", "2026-08-31T00:00:00Z"),
    ("legacy-p3-101", "2026-08-31T00:00:00Z", "2026-09-06T00:01:00Z"),
    ("v16", "2026-09-06T00:01:00Z", None),
]

ERA_META = {
    "legacy-p1-141": {"trees": 141, "window": "pre-07-30",
                        "tag": "P1 141-tree July book"},
    "legacy-p2-231": {"trees": 231, "window": "07-30 to 08-31",
                        "tag": "P2 231-tree post-redeploy book"},
    "legacy-p3-101": {"trees": 101, "window": "08-31 to 09-06",
                        "tag": "P3 101-tree (leftover closes only)"},
    "v16": {"trees": 300, "window": "since 09-06",
              "tag": "v16 book"},
}

# Leftover closes: opened under the 101-tree book (MQL5 ENTRY Sep 2 14:10
# XAU M5 0.03, Sep 2 14:15 XAU M15 0.02, Sep 3 08:30 and 15:15 XAG M15 0.01),
# held through the Sep-6 swap, manually bulk-closed Sep 7 00:58:41 (same
# second, manual deals carry magic 0). Attributed to their OPEN era (P3),
# never to v16. TF comes from the ENTRY evidence; the two XAG opens share
# symbol/lots, so both wear the neutral 101-leftover tag.
LEFTOVER_CLOSES = {
    -601737598: {"era": "legacy-p3-101", "label": "XAG M15 (101 leftover)"},
    -601737599: {"era": "legacy-p3-101", "label": "XAG M15 (101 leftover)"},
    -601737600: {"era": "legacy-p3-101", "label": "XAU M15 (101 leftover)"},
    -601737601: {"era": "legacy-p3-101", "label": "XAU M5 (101 leftover)"},
}

AUX_EAS = {
    "AccountSnapshot": "Live equity/PnL snapshot (attached to any chart)",
    "BookGovernor": "T4 trailing DD brake + graduation freeze (chart 10)",
}


def magic_label(m):
    try:
        m = int(m)
    except (TypeError, ValueError):
        return str(m)
    if m in LIVE_STREAMS:
        return LIVE_STREAMS[m]["label"]
    if m in LEGACY_STREAMS:
        return LEGACY_STREAMS[m]["label"] + " (legacy)"
    if m in (0, GOVERNOR["magic"], GOVERNOR["snapshot_magic"]):
        return "manual/aux"
    return "magic " + str(m)


def deploy_ts():
    """Deployment boundary as naive datetime (server clock ~= UTC)."""
    return _dt.strptime(DEPLOYED_UTC, "%Y-%m-%dT%H:%M:%SZ")


def _parse_cut(s):
    return _dt.strptime(s, "%Y-%m-%dT%H:%M:%SZ") if s else None


def era_of(time_str, ticket=None):
    """Era id for a close. Leftover tickets map to their OPEN era
    regardless of close time."""
    if ticket is not None:
        try:
            key = int(ticket)
        except (TypeError, ValueError):
            key = None
        if key in LEFTOVER_CLOSES:
            return LEFTOVER_CLOSES[key]["era"]
    try:
        ts = _dt.strptime(time_str, SNAP_TS_FMT)
    except (TypeError, ValueError):
        return "unknown"
    for era_id, start, end in ERA_CUTS:
        if start and ts < _parse_cut(start):
            continue
        if end and ts >= _parse_cut(end):
            continue
        return era_id
    return "unknown"


def era_label(magic, time_str, ticket=None):
    """Era-correct display label. Legacy rows wear their fold's tree
    count, e.g. 'XAU M5 ny_orb (141)'. Fixes magic-number recycling."""
    if ticket is not None:
        try:
            key = int(ticket)
        except (TypeError, ValueError):
            key = None
        if key in LEFTOVER_CLOSES:
            return LEFTOVER_CLOSES[key]["label"]
    try:
        m = int(magic)
    except (TypeError, ValueError):
        return str(magic)
    if m in (0, GOVERNOR["magic"], GOVERNOR["snapshot_magic"]):
        return "manual/aux"
    era = era_of(time_str)
    if era in ERA_META and era != "v16":
        trees = ERA_META[era]["trees"]
        if m in LEGACY_STREAMS:
            return LEGACY_STREAMS[m]["label"] + " (%d)" % trees
    if m in LIVE_STREAMS:
        return LIVE_STREAMS[m]["label"]
    if m in LEGACY_STREAMS:
        return LEGACY_STREAMS[m]["label"] + " (legacy)"
    return "magic " + str(m)


def contract_size(sym):
    base = (sym or "").upper()
    if base in CONTRACT_SIZES:
        return CONTRACT_SIZES[base]
    for k, v in CONTRACT_SIZES.items():
        if base.startswith(k):
            return v
    return None
