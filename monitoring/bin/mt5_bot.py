#!/usr/bin/env python3
"""
mt5_bot.py — AD-12 Telegram bot handler v2.

Consolidated commands:
  /status   — comprehensive snapshot (positions + history + rolling PnL)
  /health   — full health check
  /charts   — chart attach status
  /help     — show commands

Config: /home/ishanp/mt5-deploy/logcheck/config/alert.conf [telegram] section.
"""

import argparse
import configparser
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

CONFIG_PATH = "/home/ishanp/mt5-deploy/logcheck/config/alert.conf"
LOG_FILE = "/home/ishanp/mt5-deploy/logcheck/state/bot.log"
MT5CTL = "/home/ishanp/mt5-deploy/logcheck/bin/mt5ctl"
ALLOWED_CHAT_ID = None

TG_MAX_LEN = 4096


def load_config() -> dict:
    if not os.path.exists(CONFIG_PATH):
        return {}
    cp = configparser.ConfigParser()
    cp.read(CONFIG_PATH)
    cfg = {}
    if cp.has_section("telegram"):
        cfg["bot_token"] = cp.get("telegram", "bot_token", fallback="")
        cfg["chat_id"] = cp.get("telegram", "chat_id", fallback="")
    return cfg


def log(msg: str):
    ts = datetime.now(timezone.utc).isoformat()
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


# ── Telegram API ──────────────────────────────────────────────────────────

def tg_api(token: str, method: str, params: dict | None = None,
           timeout: int = 30) -> dict:
    url = f"https://api.telegram.org/bot{token}/{method}"
    if params:
        data = urllib.parse.urlencode(params).encode()
        req = urllib.request.Request(url, data=data, method="POST")
    else:
        req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def send_message(token: str, chat_id: str, text: str,
                 parse_mode: str | None = None) -> bool:
    if not text:
        return False
    chunks = []
    if len(text) <= TG_MAX_LEN:
        chunks = [text]
    else:
        current = ""
        for line in text.split("\n"):
            if len(current) + len(line) + 1 > TG_MAX_LEN:
                if current:
                    chunks.append(current)
                current = line
            else:
                current = current + "\n" + line if current else line
        if current:
            chunks.append(current)

    ok = True
    for i, chunk in enumerate(chunks):
        prefix = f"[{i+1}/{len(chunks)}]\n" if len(chunks) > 1 else ""
        params = {"chat_id": chat_id, "text": prefix + chunk}
        if parse_mode:
            params["parse_mode"] = parse_mode
        try:
            r = tg_api(token, "sendMessage", params)
            if not r.get("ok"):
                ok = False
                log(f"sendMessage failed: {r}")
        except Exception as e:
            ok = False
            log(f"sendMessage error: {e}")
    return ok


def get_updates(token: str, offset: int | None = None,
                timeout: int = 30) -> list[dict]:
    params = {"timeout": timeout, "allowed_updates": json.dumps(["message"])}
    if offset is not None:
        params["offset"] = offset
    try:
        r = tg_api(token, "getUpdates", params, timeout=timeout + 10)
        if r.get("ok"):
            return r.get("result", [])
        log(f"getUpdates not ok: {r}")
        return []
    except Exception as e:
        log(f"getUpdates error: {e}")
        return []


# ── Command routing ───────────────────────────────────────────────────────

HELP_TEXT = """\
🤖 *AD-12 MT5 Bot*

/status  — Full snapshot (positions + history + rolling PnL)
/health  — Health check
/charts  — Chart attach status
/help    — This message

One command, everything you need."""

# Alias map: /pnl, /open, /history, /snapshot all map to /status
CMD_ALIASES = {
    "pnl": "status",
    "open": "status",
    "history": "status",
    "snapshot": "status",
}


def run_mt5ctl(args: list[str], timeout: int = 60) -> str:
    try:
        result = subprocess.run(
            [MT5CTL] + args,
            capture_output=True, text=True, timeout=timeout,
        )
        out = result.stdout
        if result.returncode != 0 and result.stderr:
            out += f"\n[exit {result.returncode}]\n{result.stderr}"
        return out.strip() or "(no output)"
    except subprocess.TimeoutExpired:
        return f"⏱ Timeout after {timeout}s"
    except FileNotFoundError:
        return f"❌ mt5ctl not found at {MT5CTL}"
    except Exception as e:
        return f"❌ Error: {e}"


def handle_command(command: str, args: list[str]) -> str:
    cmd = command.lower().lstrip("/")

    # Resolve aliases
    cmd = CMD_ALIASES.get(cmd, cmd)

    if cmd in ("help", "start"):
        return HELP_TEXT

    if cmd == "status":
        return run_mt5ctl(["snapshot"])

    if cmd == "health":
        days = args[0] if args and args[0].isdigit() else "1"
        return run_mt5ctl(["health", days])

    if cmd == "charts":
        return run_mt5ctl(["charts"])

    return f"❌ Unknown command: /{command}\n\nType /help for the list."


# ── Main loop ─────────────────────────────────────────────────────────────

def process_updates(token: str, updates: list[dict]) -> int | None:
    max_update_id = 0
    for u in updates:
        uid = u.get("update_id", 0)
        max_update_id = max(max_update_id, uid)

        msg = u.get("message", {})
        if not msg:
            continue
        chat_id = str(msg.get("chat", {}).get("id", ""))
        text = msg.get("text", "").strip()
        if not text:
            continue

        if ALLOWED_CHAT_ID and chat_id != ALLOWED_CHAT_ID:
            log(f"ignoring message from chat {chat_id}")
            continue

        if not text.startswith("/"):
            continue

        parts = text.split(maxsplit=1)
        command = parts[0]
        args_text = parts[1] if len(parts) > 1 else ""
        args = args_text.split() if args_text else []

        log(f"chat={chat_id} cmd={command} args={args}")

        try:
            reply = handle_command(command, args)
        except Exception as e:
            reply = f"❌ Handler error: {e}"
            log(f"handler error: {e}")

        parse_mode = "Markdown" if command.lower() in ("/help", "/start") else None
        send_message(token, chat_id, reply, parse_mode=parse_mode)

    return max_update_id + 1 if max_update_id else None


def main():
    parser = argparse.ArgumentParser(description="AD-12 Telegram bot handler")
    parser.add_argument("--once", action="store_true",
                        help="Process pending updates once, then exit")
    parser.add_argument("--offset", type=int, default=None,
                        help="Start from a specific update offset")
    parser.add_argument("--poll-timeout", type=int, default=30,
                        help="Long-poll timeout in seconds")
    args = parser.parse_args()

    cfg = load_config()
    if not cfg.get("bot_token"):
        print(f"ERROR: no bot_token in {CONFIG_PATH}", file=sys.stderr)
        sys.exit(2)

    global ALLOWED_CHAT_ID
    ALLOWED_CHAT_ID = cfg.get("chat_id") or None

    token = cfg["bot_token"]
    log(f"bot starting (chat_id={ALLOWED_CHAT_ID}, once={args.once})")

    offset = args.offset
    while True:
        updates = get_updates(token, offset=offset, timeout=args.poll_timeout)
        if updates:
            new_offset = process_updates(token, updates)
            if new_offset is not None:
                offset = new_offset
        if args.once:
            break

    log("bot exiting")


if __name__ == "__main__":
    main()
