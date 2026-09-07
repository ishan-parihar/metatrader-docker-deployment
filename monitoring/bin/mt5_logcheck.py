#!/usr/bin/env python3
"""
mt5_logcheck.py — AD-12 weekly KPI/log checker for MetaSystemV9 (v10-cent).

Parses MT5 terminal + MQL5 journal logs from the Docker container,
extracts the signals defined in ad12-operations-manual.md §2/§3, and
emits a structured report (JSON + human-readable).

Runs ON the VPS (inside or alongside the mt5-terminal container).
Reads logs via: docker exec mt5-terminal cat <path>

Usage:
  python3 mt5_logcheck.py                    # full check, today's logs
  python3 mt5_logcheck.py --days 7           # last 7 days
  python3 mt5_logcheck.py --json             # JSON only (for piping)
  python3 mt5_logcheck.py --container mt5-terminal  # override container name

Exit codes:
  0 = all checks pass
  1 = warnings (some charts missing, warmup incomplete, etc.)
  2 = critical (container down, no broker connection, FATAL errors)
"""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

# ── Constants ─────────────────────────────────────────────────────────────

CONTAINER = "mt5-terminal"
WINE_PREFIX = "/config/.wine"
MT5_DIR = f"{WINE_PREFIX}/drive_c/Program Files/MetaTrader 5"
TERMINAL_LOG_DIR = f"{MT5_DIR}/logs"
MQL5_LOG_DIR = f"{MT5_DIR}/MQL5/logs"

# The 8 deployed charts — magic → (symbol, timeframe, atom)
EXPECTED_CHARTS = {
    992101: ("XAUUSDc", "M5",  "ny_orb"),
    992102: ("XAGUSDc", "M15", "ny_orb"),
    992103: ("XAUUSDc", "M5",  "d1_momentum"),
    992104: ("XAGUSDc", "M15", "london_orb"),
    992105: ("XAUUSDc", "M15", "london_orb"),
    992106: ("XAUUSDc", "M5",  "monthly_momentum"),
    992107: ("XAUUSDc", "M15", "ny_orb"),
    992108: ("XAUUSDc", "M15", "d1_momentum"),
}

# Additional EAs that are expected but not part of the 8-chart book
EXPECTED_AUX_EAS = {
    "AccountSnapshot": "Live equity/PnL snapshot (attached to any chart)",
}

# ── Regex patterns ────────────────────────────────────────────────────────

# RG-22: wrong-TF chart attach (MQL5 log)
FATAL_RG22_RE = re.compile(r"FATAL\s*\(RG-22\):\s*chart is (\w+),\s*set expects (\w+)")

# EA banner (MQL5 log): === MetaSystemV9 (101 trees) magic=99210x tag=... thr=... box=...h ===
BANNER_RE = re.compile(
    r"=== MetaSystemV9 \((\d+) trees\) magic=(\d+) tag=\S+ thr=([-\d.]+) box=(\d+)h ==="
)

# Warmup line (MQL5 log)
WARMUP_RE = re.compile(r"\[V9\] rolling-median warmup:\s*(\d+) bars")

# Entry signal (MQL5 log)
ENTRY_RE = re.compile(
    r"\[ENTRY\]\s*(\w+)\s+dir=(-?\d+)\s+score=([-\d.]+)\s+lots=([\d.]+)\s+SL=([\d.]+)"
)

# Deal confirmation (terminal log)
DEAL_RE = re.compile(
    r"deal #(\d+)\s+(buy|sell)\s+([\d.]+)\s+(\w+)\s+at\s+([\d.]+)\s+done"
)

# Broker auth (terminal log)
AUTH_RE = re.compile(r"authorized on\s+(\S+)")

# Trading enabled (terminal log)
TRADE_ENABLED_RE = re.compile(r"trading has been enabled")

# EA loaded (terminal log) — fires every time an EA loads, regardless of activity
EA_LOADED_RE = re.compile(r"expert (\w+) \((\w+),(\w+)\) loaded successfully")
EA_REMOVED_RE = re.compile(r"expert (\w+) \((\w+),(\w+)\) removed")

# EA init failure (terminal log)
EA_INIT_FAILED_RE = re.compile(r"initializing of (\w+) \((\w+),(\w+)\) failed with code (\d+)")

# Source pattern for MQL5 log entries (e.g. "MetaSystemV9 (XAUUSDc,M5)")
SOURCE_RE = re.compile(r"(\w+) \((\w+),(\w+)\)")

# ── Log reading ────────────────────────────────────────────────────────────

def docker_exec(path: str, container: str = CONTAINER) -> bytes:
    """Read a file from inside the container via docker exec."""
    try:
        result = subprocess.run(
            ["docker", "exec", container, "cat", path],
            capture_output=True, timeout=15,
        )
        return result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return b""


def parse_mt5_log(raw: bytes) -> list[dict]:
    """
    Parse MT5's UTF-16 LE log format.
    The file starts with a 2-byte BOM (\\xff\\xfe), then each line
    has a 2-char prefix code, a tab, a severity number, a tab, a timestamp,
    a tab, a source, a tab, and the message.
    """
    if not raw:
        return []

    # Detect encoding: UTF-16 LE BOM (0xFF 0xFE) → most common for MT5
    if raw[:2] == b"\xff\xfe":
        text = raw[2:].decode("utf-16-le", errors="replace")
    elif raw[:2] == b"\xfe\xff":
        text = raw[2:].decode("utf-16-be", errors="replace")
    elif raw[:3] == b"\xef\xbb\xbf":
        text = raw[3:].decode("utf-8", errors="replace")
    else:
        try:
            text = raw.decode("utf-16-le", errors="strict")
        except UnicodeDecodeError:
            text = raw.decode("utf-8", errors="replace")

    entries = []
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        try:
            severity = int(parts[1])
        except (ValueError, IndexError):
            continue

        timestamp_str = parts[2] if len(parts) > 2 else ""
        source = parts[3] if len(parts) > 3 else ""
        message = "\t".join(parts[4:]) if len(parts) > 4 else ""

        entries.append({
            "severity": severity,
            "time": timestamp_str,
            "source": source,
            "message": message,
            "raw": line,
        })

    return entries


def get_log_dates(days: int) -> list[str]:
    """Return list of YYYYMMDD strings for the last N days."""
    today = datetime.now(timezone.utc)
    return [(today - timedelta(days=i)).strftime("%Y%m%d") for i in reversed(range(days))]


# ── Checks ─────────────────────────────────────────────────────────────────

def check_container(container: str) -> dict:
    """Check if the mt5-terminal container is running and healthy."""
    try:
        result = subprocess.run(
            ["docker", "ps", "--filter", f"name={container}",
             "--format", "{{.Status}}"],
            capture_output=True, text=True, timeout=10,
        )
        status = result.stdout.strip()
        if not status:
            return {"alive": False, "status": "container not found", "critical": True}
        healthy = "healthy" in status
        return {
            "alive": True,
            "status": status,
            "healthy": healthy,
            "critical": not healthy and "unhealthy" in status,
        }
    except Exception as e:
        return {"alive": False, "status": str(e), "critical": True}


def check_mt5_process(container: str) -> dict:
    """Check if terminal64.exe is running inside the container."""
    try:
        result = subprocess.run(
            ["docker", "exec", container, "pgrep", "-c", "-f", "terminal64.exe"],
            capture_output=True, text=True, timeout=10,
        )
        count = int(result.stdout.strip()) if result.stdout.strip() else 0
        return {"running": count > 0, "processes": count, "critical": count == 0}
    except Exception as e:
        return {"running": False, "error": str(e), "critical": True}


def check_broker_connection(terminal_entries: list[dict]) -> dict:
    """Find the last broker authorization event."""
    auth_events = []
    trade_enabled = False
    for e in terminal_entries:
        m = AUTH_RE.search(e["message"])
        if m:
            auth_events.append({"time": e["time"], "server": m.group(1)})
        if TRADE_ENABLED_RE.search(e["message"]):
            trade_enabled = True

    if not auth_events:
        return {"connected": False, "last_auth": None, "trade_enabled": False,
                "critical": True}

    return {
        "connected": True,
        "last_auth": auth_events[-1],
        "auth_count": len(auth_events),
        "trade_enabled": trade_enabled,
        "critical": False,
    }


def read_account_snapshot(container: str) -> dict:
    """Read the AccountSnapshot EA's JSON output from the container.
    The snapshot is UTF-16 LE encoded and lives at Common/Files/.
    Returns parsed dict or empty dict on error.
    """
    snapshot_paths = [
        "/config/.wine/drive_c/users/root/AppData/Roaming/MetaQuotes/Terminal/Common/Files/account_snapshot.json",
        "/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Files/account_snapshot.json",
    ]
    for path in snapshot_paths:
        raw = docker_exec(path, container)
        if not raw:
            continue
        try:
            # UTF-16 LE with BOM
            if raw[:2] == b"\xff\xfe":
                text = raw[2:].decode("utf-16-le", errors="replace")
            else:
                text = raw.decode("utf-8", errors="replace")
            return json.loads(text)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
    return {}


def check_charts(terminal_entries: list[dict], mql5_entries: list[dict],
                 container: str = CONTAINER) -> dict:
    """
    Verify all 8 expected charts are loaded with correct magics and the live model's tree count (101 since 2026-08-31).

    Strategy (v2 — fixes false "removed" reports):
    1. PRIMARY: MQL5 log banner for this magic in the scan window. Banners
       appear every time the EA reinitializes (daily or on chart tick).
       If a banner exists for magic=99210x, that chart IS loaded.
    2. SECONDARY: Terminal log "expert loaded/removed" events. Only used
       to confirm or deny loaded state if no banner found.
    3. TERTIARY: AccountSnapshot positions array. If any open position
       has this magic number, the chart's EA is actively trading.
    4. Track auxiliary EAs (AccountSnapshot) separately.
    """
    # ── Step 1: Parse terminal log for EA load/remove events ──
    # Track per-(ea_name, symbol, tf) the last event: "loaded" or "removed"
    ea_state: dict[tuple, str] = {}  # (ea_name, sym, tf) → "loaded" | "removed"
    ea_loaded_time: dict[tuple, str] = {}  # (ea_name, sym, tf) → time of last load
    init_failures: list[dict] = []

    for e in terminal_entries:
        msg = e["message"]
        m = EA_LOADED_RE.search(msg)
        if m:
            ea_name, sym, tf = m.group(1), m.group(2), m.group(3)
            key = (ea_name, sym, tf)
            ea_state[key] = "loaded"
            ea_loaded_time[key] = e["time"]
            continue
        m = EA_REMOVED_RE.search(msg)
        if m:
            ea_name, sym, tf = m.group(1), m.group(2), m.group(3)
            key = (ea_name, sym, tf)
            ea_state[key] = "removed"
            continue
        m = EA_INIT_FAILED_RE.search(msg)
        if m:
            init_failures.append({
                "time": e["time"],
                "ea": m.group(1),
                "symbol": m.group(2),
                "tf": m.group(3),
                "code": m.group(4),
            })

    # ── Step 2: Parse MQL5 log for banner/warmup details ──
    # Banner: === MetaSystemV9 (101 trees) magic=99210x thr=... box=...h ===
    # The banner's magic number is the authoritative link to EXPECTED_CHARTS.
    banner_by_magic: dict[int, dict] = {}  # magic → {trees, thr, box, time, sym, tf}
    warmup_by_magic: dict[int, int] = {}  # magic → bars

    # Track last banner per (sym, tf) for warmup matching
    last_banner_per_chart: dict[tuple, dict] = {}

    for e in mql5_entries:
        msg = e["message"]
        source = e["source"]

        # Extract (ea_name, sym, tf) from source
        sm = SOURCE_RE.search(source)
        if not sm:
            continue
        ea_name, sym, tf = sm.group(1), sm.group(2), sm.group(3)

        # Banner line
        m = BANNER_RE.search(msg)
        if m:
            trees = int(m.group(1))
            magic = int(m.group(2))
            thr = float(m.group(3))
            box = int(m.group(4))
            info = {
                "trees": trees, "thr": thr, "box": box,
                "time": e["time"], "sym": sym, "tf": tf,
                "ea": ea_name,
            }
            info["stamp"] = e.get("day", "") + " " + info["time"]
            prev = banner_by_magic.get(magic)
            if prev is None or info["stamp"] >= prev.get("stamp", ""):
                banner_by_magic[magic] = info
            cur = last_banner_per_chart.get((sym, tf))
            if cur is None or info["stamp"] >= cur.get("stamp", ""):
                last_banner_per_chart[(sym, tf)] = {**info, "magic": magic}

        # Warmup line — match to the most recent banner for this (sym, tf)
        m = WARMUP_RE.search(msg)
        if m and (sym, tf) in last_banner_per_chart:
            bars = int(m.group(1))
            latest = last_banner_per_chart[(sym, tf)]
            magic = latest["magic"]
            # warmup belongs only to the chart that (re)initialized within this minute
            if e.get("day", "") + " " + e["time"] >= latest.get("stamp", ""):
                warmup_by_magic[magic] = max(warmup_by_magic.get(magic, 0), bars)

    # ── Step 3: FATAL RG-22 detection ──
    raw_fatals = []
    for e in mql5_entries:
        m = FATAL_RG22_RE.search(e["message"])
        if m:
            raw_fatals.append({
                "time": e["time"],
                "chart_tf": m.group(1),
                "expected_tf": m.group(2),
                "source": e["source"],
            })

    # Filter stale FATALs: stale if a banner for the same (sym, tf) exists after it
    fatals = []
    for f in raw_fatals:
        sm = SOURCE_RE.search(f["source"])
        if sm:
            _, sym, tf = sm.group(1), sm.group(2), sm.group(3)
            if (sym, tf) in last_banner_per_chart:
                banner_time = last_banner_per_chart[(sym, tf)]["time"]
                if banner_time > f["time"]:
                    continue  # stale
        fatals.append(f)

    # ── Step 4: Read account snapshot for position-based confirmation ──
    snapshot = read_account_snapshot(container)
    snapshot_magics_with_positions: set[int] = set()
    if snapshot and "positions" in snapshot:
        for pos in snapshot["positions"]:
            mg = pos.get("magic")
            if mg:
                snapshot_magics_with_positions.add(mg)

    # ── Step 5: Build chart status ──
    # For each expected magic, determine if the chart is loaded.
    # Priority: MQL5 banner > terminal log > snapshot positions
    chart_status: dict[str, dict] = {}
    loaded_magics: set[int] = set()

    for magic, (exp_sym, exp_tf, exp_atom) in EXPECTED_CHARTS.items():
        # Check MQL5 log for banner (PRIMARY signal)
        banner = banner_by_magic.get(magic)
        warmup = warmup_by_magic.get(magic)

        # Check terminal log (SECONDARY signal)
        key = ("MetaSystemV9", exp_sym, exp_tf)
        terminal_state = ea_state.get(key, "never_loaded")
        terminal_loaded_time = ea_loaded_time.get(key)

        # Check snapshot for position with this magic (TERTIARY signal)
        has_position = magic in snapshot_magics_with_positions

        # Determine loaded state:
        # - If banner exists in MQL5 logs → loaded (PRIMARY)
        # - If no banner but terminal says loaded → loaded (SECONDARY)
        # - If no banner, no terminal event, but has open position → loaded (TERTIARY)
        # - If terminal says removed AND no banner → removed
        if banner:
            is_loaded = True
            loaded_source = "mql5_banner"
        elif terminal_state == "loaded":
            is_loaded = True
            loaded_source = "terminal_log"
        elif has_position:
            is_loaded = True
            loaded_source = "snapshot_position"
        elif terminal_state == "removed":
            is_loaded = False
            loaded_source = "terminal_removed"
        else:
            is_loaded = False
            loaded_source = "no_signal"

        if is_loaded:
            loaded_magics.add(magic)

        chart_status[str(magic)] = {
            "symbol": exp_sym,
            "tf": exp_tf,
            "atom": exp_atom,
            "loaded": is_loaded,
            "loaded_source": loaded_source,
            "terminal_state": terminal_state,
            "terminal_loaded_time": terminal_loaded_time,
            "has_open_position": has_position,
            "trees": banner["trees"] if banner else None,
            "thr": banner["thr"] if banner else None,
            "box": banner["box"] if banner else None,
            "banner_time": banner["time"] if banner else None,
            "warmup_bars": warmup,
        }

    # ── Step 5: Auxiliary EAs ──
    aux_eas: dict[str, dict] = {}
    for (ea_name, sym, tf), state in ea_state.items():
        if ea_name not in EXPECTED_CHARTS and ea_name in EXPECTED_AUX_EAS:
            aux_eas[ea_name] = {
                "symbol": sym,
                "tf": tf,
                "state": state,
                "loaded_time": ea_loaded_time.get((ea_name, sym, tf)),
            }

    # ── Step 6: Compute summary ──
    expected = set(EXPECTED_CHARTS.keys())
    missing = expected - loaded_magics
    wrong_build = [
        mg for mg in loaded_magics
        if banner_by_magic.get(mg, {}).get("trees") not in (None, 101)
    ]

    # Filter stale init failures: stale if a later "loaded" event exists for
    # the same (ea, sym, tf) after the failure.
    active_init_failures = []
    for f in init_failures:
        key = (f["ea"], f["symbol"], f["tf"])
        loaded_time = ea_loaded_time.get(key)
        if loaded_time and loaded_time > f["time"]:
            continue  # stale — EA was reloaded successfully after the failure
        active_init_failures.append(f)

    return {
        "expected_count": len(EXPECTED_CHARTS),
        "loaded_count": len(loaded_magics),
        "missing_magics": sorted(missing),
        "wrong_build_magics": wrong_build,
        "charts": chart_status,
        "fatals": fatals,
        "init_failures": active_init_failures,
        "auxiliary_eas": aux_eas,
        "snapshot_available": bool(snapshot),
        "critical": bool(missing) or bool(wrong_build) or bool(fatals) or bool(active_init_failures),
    }


def check_trades(terminal_entries: list[dict], mql5_entries: list[dict]) -> dict:
    """Count trades (entries + deals) from the logs."""
    entries = []
    deals = []

    for e in mql5_entries:
        m = ENTRY_RE.search(e["message"])
        if m:
            entries.append({
                "time": e["time"],
                "atom": m.group(1),
                "dir": int(m.group(2)),
                "score": float(m.group(3)),
                "lots": float(m.group(4)),
                "sl": float(m.group(5)),
                "source": e["source"],
            })

    for e in terminal_entries:
        m = DEAL_RE.search(e["message"])
        if m:
            deals.append({
                "time": e["time"],
                "deal_id": m.group(1),
                "side": m.group(2),
                "lots": float(m.group(3)),
                "symbol": m.group(4),
                "price": float(m.group(5)),
            })

    return {
        "entry_signals": len(entries),
        "deals": len(deals),
        "entries": entries,
        "deal_list": deals,
    }


def check_disk(container: str) -> dict:
    """Check disk usage on the VPS."""
    try:
        result = subprocess.run(
            ["df", "-h", "/"], capture_output=True, text=True, timeout=5
        )
        lines = result.stdout.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            return {
                "total": parts[1],
                "used": parts[2],
                "avail": parts[3],
                "use_pct": parts[4],
                "critical": int(parts[4].rstrip("%")) > 90,
            }
    except Exception:
        pass
    return {"error": "could not read disk"}


# ── Report ─────────────────────────────────────────────────────────────────

def build_report(container: str, days: int) -> dict:
    """Run all checks and build the report."""
    log_dates = get_log_dates(days)

    # Container + process
    container_status = check_container(container)
    mt5_proc = check_mt5_process(container)

    # Read logs across all days in the window
    terminal_entries = []
    mql5_entries = []
    logs_read = []

    for date_str in log_dates:
        t_path = f"{TERMINAL_LOG_DIR}/{date_str}.log"
        m_path = f"{MQL5_LOG_DIR}/{date_str}.log"
        t_raw = docker_exec(t_path, container)
        m_raw = docker_exec(m_path, container)
        if t_raw:
            for e in parse_mt5_log(t_raw):
                e["day"] = date_str
                terminal_entries.append(e)
            logs_read.append(f"terminal:{date_str}")
        if m_raw:
            for e in parse_mt5_log(m_raw):
                e["day"] = date_str
                mql5_entries.append(e)
            logs_read.append(f"mql5:{date_str}")

    # Run checks
    broker = check_broker_connection(terminal_entries)
    charts = check_charts(terminal_entries, mql5_entries, container)
    trades = check_trades(terminal_entries, mql5_entries)
    disk = check_disk(container)

    # Overall severity
    critical = any([
        container_status.get("critical", False),
        mt5_proc.get("critical", False),
        broker.get("critical", False),
        charts.get("critical", False),
        disk.get("critical", False),
    ])

    # Only warn on warmup if loaded but no banner found (unlikely with v2 fix)
    warnings = any([
        charts.get("loaded_count", 0) < charts.get("expected_count", 0),
        not broker.get("trade_enabled"),
    ])

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "container": container_status,
        "mt5_process": mt5_proc,
        "broker": broker,
        "charts": charts,
        "trades": trades,
        "disk": disk,
        "logs_read": logs_read,
        "days_scanned": days,
        "snapshot_available": charts.get("snapshot_available", False),
        "severity": "CRITICAL" if critical else ("WARNING" if warnings else "OK"),
        "exit_code": 2 if critical else (1 if warnings else 0),
    }


def format_report(report: dict) -> str:
    """Format the report as human-readable text."""
    lines = []
    sev = report["severity"]
    icon = {"OK": "✅", "WARNING": "⚠️", "CRITICAL": "🔴"}[sev]
    lines.append(f"{icon} AD-12 Log Check — {sev}")
    lines.append(f"   Timestamp: {report['timestamp']}")
    lines.append(f"   Days scanned: {report['days_scanned']}")
    lines.append(f"   Logs read: {', '.join(report.get('logs_read', []))}")
    lines.append("")

    # Container
    c = report["container"]
    lines.append(f"── Container: {'✅ ' + c['status'] if c['alive'] else '🔴 DOWN'}")

    # MT5 process
    p = report["mt5_process"]
    lines.append(f"── MT5 Process: {'✅ running' if p['running'] else '🔴 NOT running'}"
                 + (f" ({p['processes']} proc)" if p.get("processes") else ""))

    # Broker
    b = report["broker"]
    if b["connected"]:
        la = b.get("last_auth", {})
        lines.append(f"── Broker: ✅ connected (last auth: {la.get('time','?')} on {la.get('server','?')})")
        lines.append(f"   Trade enabled: {'✅' if b['trade_enabled'] else '⚠️ NO'}")
    else:
        lines.append("── Broker: 🔴 NO connection found")

    # Charts
    ch = report["charts"]
    lines.append(f"── Charts: {ch['loaded_count']}/{ch['expected_count']} loaded")
    if ch["missing_magics"]:
        lines.append(f"   🔴 Missing magics: {ch['missing_magics']}")
    if ch["wrong_build_magics"]:
        lines.append(f"   🔴 Wrong build (not 101 trees — live canonical): {ch['wrong_build_magics']}")
    if ch["fatals"]:
        for f in ch["fatals"]:
            lines.append(f"   🔴 FATAL (RG-22): {f['chart_tf']} chart, set expects {f['expected_tf']} @ {f['time']}")
    if ch["init_failures"]:
        for f in ch["init_failures"]:
            lines.append(f"   🔴 Init failure: {f['ea']} ({f['symbol']},{f['tf']}) code={f['code']} @ {f['time']}")

    for mg_str, info in sorted(ch.get("charts", {}).items()):
        mg = int(mg_str)
        loaded_icon = "✅" if info["loaded"] else "🔴"
        source = info.get("loaded_source", "?")
        pos_flag = "📈" if info.get("has_open_position") else ""
        warmup = info.get("warmup_bars")
        warmup_str = f"warmup={warmup} bars" if warmup else "no warmup line"
        trees = info.get("trees")
        trees_str = f"{trees} trees" if trees else "no banner"
        thr = info.get("thr")
        thr_str = f"thr={thr:.4f}" if thr is not None else ""
        box = info.get("box")
        box_str = f"box={box}h" if box is not None else ""
        load_time = info.get("terminal_loaded_time", "?")
        lines.append(f"   {loaded_icon} magic={mg} {info['symbol']},{info['tf']} {info['atom']} {pos_flag} "
                     f"[{source}] (loaded {load_time}, {trees_str} {thr_str} {box_str}, {warmup_str})")

    # Auxiliary EAs
    aux = ch.get("auxiliary_eas", {})
    if aux:
        lines.append(f"── Auxiliary EAs ({len(aux)}):")
        for name, info in sorted(aux.items()):
            state_icon = "✅" if info["state"] == "loaded" else "🔴"
            desc = EXPECTED_AUX_EAS.get(name, "")
            lines.append(f"   {state_icon} {name} ({info['symbol']},{info['tf']}) "
                         f"state={info['state']} loaded={info.get('loaded_time','?')} — {desc}")

    # Trades
    t = report["trades"]
    lines.append(f"── Trades: {t['entry_signals']} entry signals, {t['deals']} deals")
    for e in t.get("entries", [])[-5:]:  # last 5
        lines.append(f"   {e['time']} {e['source']} [ENTRY] {e['atom']} dir={e['dir']} "
                     f"score={e['score']:.4f} lots={e['lots']} SL={e['sl']}")

    # Disk
    d = report["disk"]
    if "total" in d:
        lines.append(f"── Disk: {d['used']}/{d['total']} ({d['use_pct']})")

    lines.append("")
    lines.append(f"Exit code: {report['exit_code']} ({sev})")
    return "\n".join(lines)


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="AD-12 MT5 log checker")
    parser.add_argument("--container", default=CONTAINER, help="Docker container name")
    parser.add_argument("--days", type=int, default=2, help="Days of logs to scan (default: 2)")
    parser.add_argument("--json", action="store_true", help="Output JSON only")
    parser.add_argument("--report-dir", default=None, help="Write report files to this dir")
    args = parser.parse_args()

    report = build_report(args.container, args.days)

    if args.json:
        print(json.dumps(report, indent=2, default=str))
    else:
        print(format_report(report))

    # Save report if requested
    if args.report_dir:
        os.makedirs(args.report_dir, exist_ok=True)
        ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        json_path = os.path.join(args.report_dir, f"logcheck_{ts}.json")
        with open(json_path, "w") as f:
            json.dump(report, f, indent=2, default=str)
        txt_path = os.path.join(args.report_dir, f"logcheck_{ts}.txt")
        with open(txt_path, "w") as f:
            f.write(format_report(report))
        latest = os.path.join(args.report_dir, "latest.json")
        try:
            os.unlink(latest)
        except FileNotFoundError:
            pass
        os.symlink(os.path.basename(json_path), latest)

    sys.exit(report["exit_code"])


if __name__ == "__main__":
    main()
