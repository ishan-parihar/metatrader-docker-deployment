# MT5 Monitoring Stack

Automated health monitoring, alerting, and on-demand control for any
MetaTrader 5 deployment using this repo's Docker stack.

## What it does

| Component | Trigger | Output |
|---|---|---|
| **Health check** (`mt5_logcheck.py`) | systemd timer (weekly) | JSON + text report |
| **Alert dispatcher** (`mt5_alert.py`) | On CRITICAL/WARNING exit | Email + Telegram |
| **Daily summary** (`mt5_summary.py daily`) | systemd timer (daily) | Email + Telegram |
| **Weekly summary** (`mt5_summary.py weekly`) | systemd timer (weekly) | Email + Telegram |
| **Account snapshot** (`AccountSnapshot.mq5`) | MQL5 timer (60s) | JSON file |
| **On-demand control** (`mt5ctl`) | Manual | Terminal output |
| **Telegram bot** (`mt5_bot.py`) | Long-running | Replies to slash commands |

## What it checks

| Check | Source | Severity |
|---|---|---|
| Container `mt5-terminal` running & healthy | `docker ps` | CRITICAL if down |
| `terminal64.exe` process alive | `docker exec pgrep` | CRITICAL if dead |
| Broker connection (last `authorized on`) | terminal log | CRITICAL if missing |
| All expected charts loaded with correct magics | terminal log + MQL5 log | CRITICAL if missing |
| 141-tree build confirmation per chart | MQL5 banner | CRITICAL if wrong |
| Warmup completed per chart | MQL5 log | WARNING if missing |
| No active `FATAL (RG-22)` errors | MQL5 log | CRITICAL if present |
| Trade count (entries + deals) | both logs | INFO |
| Disk usage on `/` | `df -h` | WARNING if >90% |
| Account balance/equity/PnL | `account_snapshot.json` | INFO |
| Open positions | `account_snapshot.json` | INFO |
| Margin level | `account_snapshot.json` | WARNING if <500% |

## Installation

### 1. Configure alert channels

```bash
cd monitoring
cp config/alert.conf.example config/alert.conf
nano config/alert.conf
chmod 600 config/alert.conf
```

Fill in:
- **Email**: SMTP host/user/password (Gmail App Password recommended)
- **Telegram**: bot token (from @BotFather) + chat ID

### 2. Run the installer

```bash
./install.sh
```

This will:
- Copy all scripts to `~/mt5-monitoring/bin/`
- Install systemd units to `/etc/systemd/system/`
- Enable and start all timers + the bot service

### 3. Attach the AccountSnapshot EA

In MT5 (via noVNC):
1. Open any chart (recommend a dedicated XAUUSDc M1 chart)
2. Drag `AccountSnapshot.ex5` from the Navigator onto the chart
3. The EA will start writing `account_snapshot.json` every 60 seconds

### 4. Verify

```bash
export PATH="$HOME/mt5-monitoring/bin:$PATH"
mt5ctl status
mt5ctl pnl
mt5ctl health
```

## Quick reference

```bash
# On the VPS:
export PATH="$HOME/mt5-monitoring/bin:$PATH"

mt5ctl status              # 1-line health
mt5ctl dashboard           # full dashboard
mt5ctl dashboard positions # open trades + totals
mt5ctl dashboard history   # closed trades + stats
mt5ctl dashboard exposure  # by symbol + strategy
mt5ctl dashboard drawdown  # peak equity + drawdown
mt5ctl dashboard risk      # margin + per-position R:R
mt5ctl dashboard orders    # pending orders
mt5ctl dashboard equity    # equity curve
mt5ctl dashboard rolling   # daily/weekly/monthly PnL
mt5ctl health              # full health check (default 2 days)
mt5ctl health 7            # health check last 7 days
mt5ctl charts              # chart attach status
mt5ctl summary weekly      # weekly summary
mt5ctl alert test          # test email + Telegram
```

## Telegram bot commands

Send these to your bot in Telegram:

<b>Dashboard (unified view):</b>
- `/dashboard` — Full dashboard (all dimensions)
- `/positions` — Open trades + totals
- `/history` — Closed trades + stats
- `/exposure` — By symbol + strategy
- `/drawdown` — Peak equity + drawdown
- `/risk` — Margin + per-position R:R
- `/orders` — Pending orders
- `/equity` — Equity curve
- `/rolling` — Daily/weekly/monthly PnL

<b>System:</b>
- `/status` — 1-line health check
- `/health` — Full health report
- `/charts` — Chart attach status
- `/help` — Show this message

All commands are clickable in Telegram's command menu.

## Layout

```
mt5-monitoring/
├── bin/
│   ├── mt5_logcheck.py        # core: parses logs, runs checks
│   ├── mt5_logcheck.sh        # bash wrapper (called by systemd)
│   ├── mt5_alert.py           # email + Telegram dispatcher
│   ├── mt5_summary.py         # daily/weekly/monthly summaries
│   ├── mt5_bot.py              # Telegram bot polling handler
│   └── mt5ctl                  # on-demand command interface
├── state/
│   ├── logcheck.log           # append-only run log
│   ├── alert.log              # alert send log
│   └── bot.log                # bot activity log
├── reports/
│   ├── logcheck_*.json        # health check reports
│   ├── logcheck_*.txt         # human-readable
│   ├── summary_*.json         # daily/weekly/monthly summaries
│   └── latest.json            # symlink to most recent
└── config/
    └── alert.conf             # email + Telegram config (0600)
```

## systemd timers

| Timer | Schedule | Action |
|---|---|---|
| `mt5-logcheck.timer` | Sun 18:00 local | Weekly health check + alert |
| `mt5-summary-daily.timer` | Daily 23:00 local | Daily summary email |
| `mt5-summary-weekly.timer` | Sun 18:00 local | Weekly summary email |
| `mt5-bot.service` | Always running | Telegram bot polling |

Check status: `systemctl list-timers mt5-*`
Run now: `sudo systemctl start mt5-logcheck.service`

## Customization

### Add expected charts

Edit `bin/mt5_logcheck.py` and modify the `EXPECTED_CHARTS` dict:

```python
EXPECTED_CHARTS = {
    992101: ("XAUUSDc", "M5",  "ny_orb"),
    # ... add your charts here
}
```

### Add auxiliary EAs

```python
EXPECTED_AUX_EAS = {
    "AccountSnapshot": "Live equity/PnL snapshot",
    "YourCustomEA": "Description of what it does",
}
```

### Change log window

Default is 2 days. Override with `--days N`:

```bash
mt5ctl health 7    # last 7 days
```

## References

- `MT5/mql5/Experts/AccountSnapshot.mq5` — the equity feed EA
- `../deploy-ea-bundle.sh` — deploys EA bundles to the MT5 container
- `../README.md` — main repo documentation
