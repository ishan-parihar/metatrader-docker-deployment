#!/usr/bin/env python3
"""
mt5_summary.py — AD-12 daily/weekly summary generator.

Aggregates logcheck reports + account snapshots over a window and produces
a human-readable summary + JSON.

Usage:
  python3 mt5_summary.py daily              # last 24h
  python3 mt5_summary.py weekly             # last 7 days
  python3 mt5_summary.py monthly            # last 30 days
  python3 mt5_summary.py --days 14          # custom window
  python3 mt5_summary.py daily --send       # also send via alert channels
"""
import argparse
import glob
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

REPORT_DIR = "/home/ishanp/mt5-deploy/logcheck/reports"
ACCOUNT_SNAPSHOT_PATH = "/home/ishanp/mt5-deploy/logcheck/state/account.json"
ALERT_SCRIPT = "/home/ishanp/mt5-deploy/logcheck/bin/mt5_alert.py"

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

# Per ad12-operations-manual.md §3
EXPECTATION_BANDS = {
    "monthly_return_pct": {"low": -10, "high": 40, "median_low": 10, "median_high": 20},
    "trades_per_month":   {"low": 40, "high": 70},
    "max_dd_pct":         {"normal_max": 80},
}


def load_reports(window_days: int) -> list[dict]:
    """Load all logcheck JSON reports within the window."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=window_days)
    reports = []
    for path in sorted(glob.glob(os.path.join(REPORT_DIR, "logcheck_*.json"))):
        try:
            mtime = datetime.fromtimestamp(os.path.getmtime(path), tz=timezone.utc)
            if mtime < cutoff:
                continue
            with open(path) as f:
                reports.append(json.load(f))
        except Exception:
            continue
    return reports


def load_account_snapshot() -> dict | None:
    """Load the latest account snapshot from MQL5/Files/account_snapshot.json
    (read via docker exec). FILE_COMMON writes to the Common/Files directory."""
    paths = [
        "/config/.wine/drive_c/users/root/AppData/Roaming/MetaQuotes/Terminal/Common/Files/account_snapshot.json",
        "/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Files/account_snapshot.json",
    ]
    for path in paths:
        try:
            result = subprocess.run(
                ["docker", "exec", "mt5-terminal", "cat", path],
                capture_output=True, timeout=10,
            )
            if result.returncode == 0 and result.stdout:
                raw = result.stdout
                # MT5 writes text files as UTF-16 LE by default
                if raw[:2] == b"\xff\xfe":
                    text = raw[2:].decode("utf-16-le", errors="replace")
                elif raw[:2] == b"\xfe\xff":
                    text = raw[2:].decode("utf-16-be", errors="replace")
                elif raw[:3] == b"\xef\xbb\xbf":
                    text = raw[3:].decode("utf-8", errors="replace")
                else:
                    text = raw.decode("utf-8", errors="replace")
                return json.loads(text)
        except Exception:
            continue
    return None


def aggregate_trades(reports: list[dict]) -> dict:
    """Sum entry signals + deals across all reports in the window."""
    total_entries = 0
    total_deals = 0
    entries_by_atom = {}
    deals_by_symbol = {}
    for r in reports:
        t = r.get("trades", {})
        total_entries += t.get("entry_signals", 0)
        total_deals += t.get("deals", 0)
        for e in t.get("entries", []):
            atom = e.get("atom", "?")
            entries_by_atom[atom] = entries_by_atom.get(atom, 0) + 1
        for d in t.get("deal_list", []):
            sym = d.get("symbol", "?")
            deals_by_symbol[sym] = deals_by_symbol.get(sym, 0) + 1
    return {
        "total_entries": total_entries,
        "total_deals": total_deals,
        "entries_by_atom": entries_by_atom,
        "deals_by_symbol": deals_by_symbol,
    }


def aggregate_health(reports: list[dict]) -> dict:
    """Track health over the window."""
    if not reports:
        return {"checks": 0}
    severities = [r.get("severity", "?") for r in reports]
    return {
        "checks": len(reports),
        "ok_count":      severities.count("OK"),
        "warning_count": severities.count("WARNING"),
        "critical_count": severities.count("CRITICAL"),
        "first_check":   reports[0].get("timestamp"),
        "last_check":    reports[-1].get("timestamp"),
        "last_severity": reports[-1].get("severity"),
    }


def aggregate_charts(reports: list[dict]) -> dict:
    """Latest chart status from the most recent report."""
    if not reports:
        return {}
    last = reports[-1]
    return last.get("charts", {})


def compute_pnl(snapshot: dict | None, window_days: int) -> dict:
    """Compute PnL from the account snapshot. Without a starting balance
    baseline we can only show current state — for true PnL we'd need to
    snapshot balance at window start."""
    if not snapshot:
        return {"available": False}
    return {
        "available": True,
        "balance": snapshot.get("balance"),
        "equity": snapshot.get("equity"),
        "margin": snapshot.get("margin"),
        "free_margin": snapshot.get("free_margin"),
        "margin_level": snapshot.get("margin_level"),
        "open_pnl": snapshot.get("profit"),
        "open_positions": len(snapshot.get("positions", [])),
        "leverage": snapshot.get("leverage"),
        "currency": snapshot.get("currency"),
        "ts": snapshot.get("ts"),
    }


def check_expectation_bands(window_days: int, total_entries: int, pnl: dict) -> list[str]:
    """Compare against ad12-operations-manual.md §3 expectation bands."""
    notes = []
    # Scale monthly bands to window
    scale = window_days / 30.0
    expected_entries_low = EXPECTATION_BANDS["trades_per_month"]["low"] * scale
    expected_entries_high = EXPECTATION_BANDS["trades_per_month"]["high"] * scale

    if total_entries < expected_entries_low * 0.5:
        notes.append(f"⚠️ Trade count {total_entries} is well below expected ({expected_entries_low:.0f}–{expected_entries_high:.0f} for {window_days}d window)")
    elif total_entries > expected_entries_high * 2:
        notes.append(f"⚠️ Trade count {total_entries} is well above expected ({expected_entries_low:.0f}–{expected_entries_high:.0f})")
    else:
        notes.append(f"✅ Trade count {total_entries} inside expected band ({expected_entries_low:.0f}–{expected_entries_high:.0f})")

    if pnl.get("available") and pnl.get("margin_level"):
        ml = pnl["margin_level"]
        if ml < 200:
            notes.append(f"🔴 Margin level {ml:.1f}% is dangerously low (broker margin call at ~50–100%)")
        elif ml < 500:
            notes.append(f"⚠️ Margin level {ml:.1f}% is low (watch for further drawdown)")
        else:
            notes.append(f"✅ Margin level {ml:.1f}% healthy")

    return notes


def format_summary(window_label: str, window_days: int, health: dict,
                   trades: dict, charts: dict, pnl: dict, notes: list[str]) -> str:
    """Format the summary as human-readable text."""
    lines = []
    lines.append(f"📊 AD-12 {window_label} Summary ({window_days} days)")
    lines.append(f"   Generated: {datetime.now(timezone.utc).isoformat()[:16]}")
    lines.append("")

    # Health
    if health.get("checks"):
        lines.append(f"── Health: {health['last_severity']} (last check)")
        lines.append(f"   Checks: {health['checks']} | OK: {health['ok_count']} | "
                     f"Warning: {health['warning_count']} | Critical: {health['critical_count']}")
        lines.append(f"   Window: {health['first_check'][:16]} → {health['last_check'][:16]}")

    # PnL
    if pnl.get("available"):
        lines.append("")
        lines.append(f"── Account ({pnl.get('currency','?')})")
        lines.append(f"   Balance:      {pnl.get('balance','?')}")
        lines.append(f"   Equity:       {pnl.get('equity','?')}")
        lines.append(f"   Open PnL:     {pnl.get('open_pnl','?')}")
        lines.append(f"   Margin:       {pnl.get('margin','?')} (free: {pnl.get('free_margin','?')})")
        lines.append(f"   Margin level: {pnl.get('margin_level','?')}%")
        lines.append(f"   Open positions: {pnl.get('open_positions','?')}")
        lines.append(f"   Leverage: {pnl.get('leverage','?')}")
        lines.append(f"   Snapshot: {pnl.get('ts','?')}")
    else:
        lines.append("")
        lines.append("── Account: no snapshot available (AccountSnapshot.mq5 not running?)")

    # Trades
    lines.append("")
    lines.append(f"── Trades")
    lines.append(f"   Entries: {trades['total_entries']} | Deals: {trades['total_deals']}")
    if trades["entries_by_atom"]:
        atoms = ", ".join(f"{k}={v}" for k, v in sorted(trades["entries_by_atom"].items()))
        lines.append(f"   By atom: {atoms}")
    if trades["deals_by_symbol"]:
        syms = ", ".join(f"{k}={v}" for k, v in sorted(trades["deals_by_symbol"].items()))
        lines.append(f"   By symbol: {syms}")

    # Charts
    if charts:
        loaded = charts.get("loaded_count", charts.get("found_count", "?"))
        expected = charts.get("expected_count", "?")
        lines.append("")
        lines.append(f"── Charts (latest): {loaded}/{expected}")
        for mg, info in sorted(charts.get("charts", {}).items()):
            warmup = info.get("warmup_bars")
            warmup_str = f"warmup={warmup}" if warmup else "⚠️ NO warmup"
            trees = info.get("trees")
            trees_ok = "✅" if trees == 141 else ("🔴" if trees else "⚠️")
            trees_str = f"{trees} trees" if trees else "no banner"
            lines.append(f"  {trees_ok} magic={mg} {info.get('symbol','?')},{info.get('tf','?')} "
                         f"{info.get('atom','?')} ({trees_str}, {warmup_str})")

        # Auxiliary EAs
        aux = charts.get("auxiliary_eas", {})
        if aux:
            aux_parts = []
            for n, a in sorted(aux.items()):
                state = a.get("state", "?")
                aux_parts.append(f"{n} ({state})")
            lines.append(f"  Auxiliary EAs: {', '.join(aux_parts)}")

    # Expectation band notes
    if notes:
        lines.append("")
        lines.append("── Expectation band check")
        for n in notes:
            lines.append(f"   {n}")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="AD-12 summary generator")
    parser.add_argument("period", nargs="?", default="daily",
                        choices=["daily", "weekly", "monthly"],
                        help="Summary period")
    parser.add_argument("--days", type=int, help="Override window in days")
    parser.add_argument("--send", action="store_true", help="Send via alert channels")
    parser.add_argument("--json", action="store_true", help="JSON output only")
    args = parser.parse_args()

    window_days = args.days or {"daily": 1, "weekly": 7, "monthly": 30}[args.period]
    window_label = args.period.capitalize()

    reports = load_reports(window_days)
    health = aggregate_health(reports)
    trades = aggregate_trades(reports)
    charts = aggregate_charts(reports)
    pnl = compute_pnl(load_account_snapshot(), window_days)
    notes = check_expectation_bands(window_days, trades["total_entries"], pnl)

    summary_text = format_summary(window_label, window_days, health, trades, charts, pnl, notes)

    summary_obj = {
        "period": args.period,
        "window_days": window_days,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "health": health,
        "pnl": pnl,
        "trades": trades,
        "charts": charts,
        "notes": notes,
    }

    if args.json:
        print(json.dumps(summary_obj, indent=2, default=str))
    else:
        print(summary_text)

    # Save report
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    out_path = os.path.join(REPORT_DIR, f"summary_{args.period}_{ts}.json")
    with open(out_path, "w") as f:
        json.dump(summary_obj, f, indent=2, default=str)
    latest = os.path.join(REPORT_DIR, f"summary_latest.json")
    try:
        os.unlink(latest)
    except FileNotFoundError:
        pass
    os.symlink(os.path.basename(out_path), latest)

    # Send if requested — summaries always send (they're informational digests)
    if args.send:
        body = summary_text + f"\n\nFull JSON: {out_path}"
        subject = f"[AD-12] {window_label} Summary — {datetime.now(timezone.utc).strftime('%Y-%m-%d')}"
        # Call alert dispatcher directly with custom subject/body (bypasses severity gate)
        subprocess.run(
            ["python3", ALERT_SCRIPT,
             "--subject", subject,
             "--body", body],
            check=False,
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
