#!/usr/bin/env python3
"""
mt5_alert.py — AD-12 alert dispatcher.

Sends alerts via email (gog gmail send) and/or Telegram (bot API) when
the log check exits with CRITICAL or WARNING severity.

Reads config from /home/ishanp/mt5-deploy/logcheck/config/alert.conf
(INI format). Skips channels that aren't configured.

Usage:
  python3 mt5_alert.py --report /path/to/logcheck_*.json
  python3 mt5_alert.py --severity CRITICAL --subject "..." --body "..."

Exit codes:
  0 = alert sent (or no alert needed)
  1 = alert failed (one or more channels)
  2 = config missing/invalid
"""
import argparse
import configparser
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

CONFIG_PATH = "/home/ishanp/mt5-deploy/logcheck/config/alert.conf"

# ── Config ────────────────────────────────────────────────────────────────

def load_config() -> dict:
    """Load alert config from INI file. Returns dict with email/telegram keys."""
    if not os.path.exists(CONFIG_PATH):
        return {}
    cp = configparser.ConfigParser()
    cp.read(CONFIG_PATH)
    cfg = {}
    if cp.has_section("email"):
        cfg["email"] = {
            "to":      cp.get("email", "to", fallback=""),
            "from":    cp.get("email", "from", fallback="ishan.parihar.official@gmail.com"),
            "subject_prefix": cp.get("email", "subject_prefix", fallback="[AD-12]"),
            # SMTP config (used on VPS where gog isn't installed)
            "smtp_host":     cp.get("email", "smtp_host",     fallback=""),
            "smtp_port":     cp.get("email", "smtp_port",     fallback="587"),
            "smtp_user":     cp.get("email", "smtp_user",     fallback=""),
            "smtp_password": cp.get("email", "smtp_password", fallback=""),
        }
    if cp.has_section("telegram"):
        cfg["telegram"] = {
            "bot_token": cp.get("telegram", "bot_token", fallback=""),
            "chat_id":   cp.get("telegram", "chat_id",   fallback=""),
        }
    return cfg


# ── Channels ──────────────────────────────────────────────────────────────

def send_email(cfg: dict, subject: str, body: str) -> tuple[bool, str]:
    """Send email via SMTP (Gmail with app password) or `gog gmail send`.
    Tries SMTP first (works on VPS without gog), falls back to gog."""
    if not cfg.get("to"):
        return False, "no recipient configured"

    # Try SMTP first if configured
    if cfg.get("smtp_host"):
        return _send_email_smtp(cfg, subject, body)

    # Fall back to gog
    return _send_email_gog(cfg, subject, body)


def _send_email_smtp(cfg: dict, subject: str, body: str) -> tuple[bool, str]:
    """Send via SMTP (Gmail: smtp.gmail.com:587, TLS, app password)."""
    import smtplib
    from email.mime.text import MIMEText
    host = cfg.get("smtp_host", "")
    port = int(cfg.get("smtp_port", "587"))
    user = cfg.get("smtp_user", "")
    password = cfg.get("smtp_password", "")
    sender = cfg.get("from", user)
    recipient = cfg.get("to", "")
    if not all([host, user, password, recipient]):
        return False, "SMTP config incomplete (need host, user, password, to)"
    try:
        msg = MIMEText(body)
        msg["Subject"] = subject
        msg["From"] = sender
        msg["To"] = recipient
        with smtplib.SMTP(host, port, timeout=30) as smtp:
            smtp.starttls()
            smtp.login(user, password)
            smtp.send_message(msg)
        return True, "sent (smtp)"
    except smtplib.SMTPAuthenticationError as e:
        return False, f"SMTP auth failed: {e}"
    except Exception as e:
        return False, f"SMTP error: {e}"


def _send_email_gog(cfg: dict, subject: str, body: str) -> tuple[bool, str]:
    """Send via `gog gmail send` (requires gog installed and authenticated)."""
    try:
        result = subprocess.run(
            [
                "gog", "gmail", "send",
                "--account", cfg.get("from", ""),
                "--to", cfg["to"],
                "--subject", subject,
                "--body", body,
                "--no-input",
            ],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            return True, "sent (gog)"
        return False, f"gog exit {result.returncode}: {result.stderr.strip()[:200]}"
    except FileNotFoundError:
        return False, "gog not found in PATH"
    except subprocess.TimeoutExpired:
        return False, "gog timeout"
    except Exception as e:
        return False, str(e)


def send_telegram(cfg: dict, text: str) -> tuple[bool, str]:
    """Send Telegram message via bot API. Returns (ok, message)."""
    token = cfg.get("bot_token", "")
    chat_id = cfg.get("chat_id", "")
    if not token or not chat_id:
        return False, "bot_token or chat_id not configured"
    try:
        url = f"https://api.telegram.org/bot{token}/sendMessage"
        data = urllib.parse.urlencode({"chat_id": chat_id, "text": text}).encode()
        req = urllib.request.Request(url, data=data, method="POST")
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = resp.read().decode()
        if '"ok":true' in body:
            return True, "sent"
        return False, f"telegram: {body[:200]}"
    except Exception as e:
        return False, str(e)


# ── Formatting ────────────────────────────────────────────────────────────

SEVERITY_ICONS = {"OK": "✅", "WARNING": "⚠️", "CRITICAL": "🔴"}

def format_email(report: dict) -> tuple[str, str]:
    """Build (subject, body) for email from a logcheck report."""
    sev = report.get("severity", "OK")
    icon = SEVERITY_ICONS.get(sev, "?")
    ts = report.get("timestamp", "")
    subject = f"{icon} AD-12 {sev} — {ts[:16]}"

    lines = [f"{icon} AD-12 Log Check — {sev}", f"Timestamp: {ts}", ""]

    # Container
    c = report.get("container", {})
    lines.append(f"Container: {'✅ ' + c.get('status','?') if c.get('alive') else '🔴 DOWN'}")

    # MT5
    p = report.get("mt5_process", {})
    lines.append(f"MT5 Process: {'✅ running' if p.get('running') else '🔴 NOT running'}")

    # Broker
    b = report.get("broker", {})
    if b.get("connected"):
        la = b.get("last_auth", {})
        lines.append(f"Broker: ✅ connected (last auth {la.get('time','?')} on {la.get('server','?')})")
        lines.append(f"  Trade enabled: {'✅' if b.get('trade_enabled') else '⚠️ NO'}")
    else:
        lines.append("Broker: 🔴 NO connection")

    # Charts
    ch = report.get("charts", {})
    lines.append(f"Charts: {ch.get('found_count','?')}/{ch.get('expected_count','?')} loaded")
    if ch.get("missing_magics"):
        lines.append(f"  🔴 Missing: {ch['missing_magics']}")
    if ch.get("wrong_build_magics"):
        lines.append(f"  🔴 Wrong build: {ch['wrong_build_magics']}")
    if ch.get("fatals"):
        for f in ch["fatals"]:
            lines.append(f"  🔴 FATAL (RG-22): {f.get('chart_tf')} chart, set expects {f.get('expected_tf')} @ {f.get('time')}")

    for mg, info in sorted(ch.get("charts", {}).items()):
        warmup = info.get("warmup_bars")
        warmup_str = f"warmup={warmup}" if warmup else "⚠️ NO warmup"
        trees_ok = "✅" if info.get("trees") == 141 else "🔴"
        lines.append(f"  {trees_ok} magic={mg} {info.get('symbol','?')},{info.get('tf','?')} "
                     f"{info.get('atom','?')} ({info.get('trees','?')} trees, {warmup_str})")

    # Trades
    t = report.get("trades", {})
    lines.append(f"Trades: {t.get('entry_signals',0)} entries, {t.get('deals',0)} deals")

    # Disk
    d = report.get("disk", {})
    if "total" in d:
        lines.append(f"Disk: {d.get('used','?')}/{d.get('total','?')} ({d.get('use_pct','?')})")

    lines.append("")
    lines.append(f"Full report: /home/ishanp/mt5-deploy/logcheck/reports/latest.json")
    lines.append(f"Run manually: ssh ishanp@20.24.213.8 '/home/ishanp/mt5-deploy/logcheck/bin/mt5_logcheck.sh'")
    return subject, "\n".join(lines)


def format_telegram(report: dict) -> str:
    """Build compact Telegram message from a logcheck report."""
    sev = report.get("severity", "OK")
    icon = SEVERITY_ICONS.get(sev, "?")

    ch = report.get("charts", {})
    missing = ch.get("missing_magics", [])
    wrong = ch.get("wrong_build_magics", [])
    fatals = ch.get("fatals", [])

    issues = []
    if missing: issues.append(f"missing {missing}")
    if wrong:   issues.append(f"wrong-build {wrong}")
    if fatals:  issues.append(f"{len(fatals)} FATAL(RG-22)")

    b = report.get("broker", {})
    broker_ok = "✅" if b.get("connected") else "🔴"

    msg = f"{icon} *AD-12 {sev}*\n"
    msg += f"Charts: {ch.get('found_count','?')}/{ch.get('expected_count','?')} | Broker: {broker_ok}\n"
    if issues:
        msg += f"Issues: {', '.join(issues)}\n"
    t = report.get("trades", {})
    if t.get("entry_signals", 0) or t.get("deals", 0):
        msg += f"Trades: {t['entry_signals']} entries / {t['deals']} deals\n"
    msg += f"_Full report: latest.json_"
    return msg


# ── Main ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="AD-12 alert dispatcher")
    parser.add_argument("--report", help="Path to logcheck JSON report")
    parser.add_argument("--severity", choices=["OK", "WARNING", "CRITICAL"], help="Override severity")
    parser.add_argument("--subject", help="Custom subject (email)")
    parser.add_argument("--body", help="Custom body (email)")
    args = parser.parse_args()

    cfg = load_config()
    if not cfg:
        print(f"ERROR: no config at {CONFIG_PATH}", file=sys.stderr)
        sys.exit(2)

    # Load report if provided
    report = None
    if args.report:
        try:
            with open(args.report) as f:
                report = json.load(f)
        except Exception as e:
            print(f"ERROR: cannot read {args.report}: {e}", file=sys.stderr)
            sys.exit(2)

    # Determine severity: if --severity given, use it; else from report; else OK
    severity = args.severity
    if not severity and report:
        severity = report.get("severity", "OK")
    if not severity:
        severity = "OK"

    # If --subject was provided (e.g. from summary), always send regardless of severity
    force_send = bool(args.subject and args.body)

    # Don't alert on OK unless explicitly forced (summaries, etc.)
    if severity == "OK" and not force_send:
        print(f"severity=OK, no alert sent")
        sys.exit(0)

    # Build subject/body
    if report:
        subject, body = format_email(report)
        tg_text = format_telegram(report)
    else:
        subject = args.subject or f"[AD-12] {severity}"
        body = args.body or "(no body)"
        tg_text = body

    # Send
    results = []
    if "email" in cfg:
        ok, msg = send_email(cfg["email"], subject, body)
        results.append(f"email: {'OK' if ok else 'FAIL'} ({msg})")
    if "telegram" in cfg:
        ok, msg = send_telegram(cfg["telegram"], tg_text)
        results.append(f"telegram: {'OK' if ok else 'FAIL'} ({msg})")

    print("\n".join(results))

    # Exit 1 if any channel failed
    if any("FAIL" in r for r in results):
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
