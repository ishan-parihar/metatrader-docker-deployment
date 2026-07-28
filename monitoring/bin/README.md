# AD-12 MT5 Log Checker

Automated health monitoring, alerting, and on-demand control for the deployed
`MetaSystemV9` (v10-cent) on the Exness Standard Cent MT5 terminal running in
Docker on this VPS.

## What it does

| Component | Trigger | Output |
|---|---|---|
| **Health check** (`mt5_logcheck.py`) | systemd timer (Sun 18:00 IST) | JSON + text report |
| **Alert dispatcher** (`mt5_alert.py`) | On CRITICAL/WARNING exit | Email + Telegram |
| **Daily summary** (`mt5_summary.py daily`) | systemd timer (daily 23:00 IST) | Email + Telegram |
| **Weekly summary** (`mt5_summary.py weekly`) | systemd timer (Sun 18:00 IST) | Email + Telegram |
| **Account snapshot** (`AccountSnapshot.mq5`) | MQL5 timer (60s) | JSON file |
| **On-demand control** (`mt5ctl`) | Manual | Terminal output |

## Layout

```
logcheck/
├── bin/
│   ├── mt5_logcheck.py        # core: parses logs, runs checks
│   ├── mt5_logcheck.sh        # bash wrapper (called by systemd)
│   ├── mt5_alert.py           # email + Telegram dispatcher
│   ├── mt5_summary.py         # daily/weekly/monthly summaries
│   ├── mt5ctl                 # on-demand command interface
│   ├── AccountSnapshot.mq5    # MQL5 EA — dumps account state to JSON
│   └── README.md              # this file
├── config/
│   └── alert.conf             # email + Telegram config (0600)
├── state/
│   ├── logcheck.log           # append-only run log
│   ├── alert.log              # alert send log
│   └── account.json           # cached account snapshot
└── reports/
    ├── logcheck_*.json        # health check reports
    ├── logcheck_*.txt         # human-readable
    ├── summary_*.json         # daily/weekly/monthly summaries
    └── latest.json            # symlink to most recent
```

## Quick start

```bash
# Quick health (1-line)
mt5ctl status

# Full health check
mt5ctl health

# Current PnL
mt5ctl pnl

# Today's trades
mt5ctl trades today

# Chart attach status
mt5ctl charts

# Weekly summary
mt5ctl summary weekly

# Test alert (email + Telegram)
mt5ctl alert test
```

## What it checks (per `ad12-operations-manual.md` 

| Check | Source | Severity |
|---|---|---|
| Container `mt5-terminal` running & healthy | `docker ps` | CRITICAL if down |
| `terminal64.exe` process alive | `docker exec pgrep` | CRITICAL if dead |
| Broker connection (last `authorized on`) | terminal log | CRITICAL if missing |
| All 8 charts loaded with magics 992101–992108 | MQL5 log | CRITICAL if missing |
| 141-tree build confirmation per chart | `=== MetaSystemV9 (141 trees) ===` | CRITICAL if wrong |
| Warmup completed per chart | `[V9] rolling-median warmup: N bars` | WARNING if missing |
| No active `FATAL (RG-22)` errors | MQL5 log | CRITICAL if present |
| Trade count (entries + deals) | both logs | INFO |
| Disk usage on `/` | `df -h` | WARNING if >90% |
| Account balance/equity/PnL | `account_snapshot.json` | INFO |
| Open positions | `account_snapshot.json` | INFO |
| Margin level | `account_snapshot.json` | WARNING if <500% |

## Exit codes

- `0` — all checks pass (OK)
- `1` — warnings (some charts missing, warmup incomplete, etc.)
- `2` — critical (container down, no broker, FATAL errors, wrong build)

## Alerting

Alerts fire on WARNING or CRITICAL severity. Configured in
`config/alert.conf` (0600 perms):

- **Email**: via `gog gmail send` (account: `ishan.parihar.official@gmail.com`)
- **Telegram**: via bot API (chat: `5297486612`)

To test: `mt5ctl alert test`

## systemd timers

| Timer | Schedule | What it runs |
|---|---|---|
| `mt5-logcheck.timer` | Sun 12:30 UTC (= 18:00 IST) | Weekly health check + alert |
| `mt5-summary-daily.timer` | Daily 17:30 UTC (= 23:00 IST) | Daily summary email |
| `mt5-summary-weekly.timer` | Sun 12:30 UTC (= 18:00 IST) | Weekly summary email |

Check status: `systemctl list-timers mt5-*`
Run now: `sudo systemctl start mt5-logcheck.service`

## MQL5 AccountSnapshot

`AccountSnapshot.mq5` is a tiny EA that attaches to any chart (recommend a
dedicated XAUUSDc M1 chart) and writes the live account state + open
positions to `MQL5/Files/account_snapshot.json` every 60 seconds. This is
what `mt5ctl pnl` and `mt5_summary.py` read for live equity/PnL.

To deploy:
1. Compile: `python3 Scripts/Python/tools/compile_rnd_ea.py AccountSnapshot`
2. Copy `.ex5` to `/home/ishanp/mt5-deploy/ea/Experts/`
3. Attach to any chart in MT5

## References

- `docs/architecture/ad12-operations-manual.md`  §2 (weekly checklist)
- `docs/architecture/ad12-operations-manual.md`  §3 (expectation bands)
- `docs/architecture/ad12-vps-deployment.md`  (VPS layout)
- `skills/quantitative-strategy-rd/references/regression-guards.md`  (RG-22, RG-28, RG-34)
