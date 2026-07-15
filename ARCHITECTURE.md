# MT5 Monitoring Stack — Architecture & Decision Log

## Overview

Unified monitoring stack for MetaTrader 5 deployments. Provides:
- **AccountSnapshot.mq5** (EA) — writes `account_snapshot.json` every 60s to FILE_COMMON
- **mt5ctl** — bash CLI that reads snapshot + container logs, outputs formatted dashboards
- **mt5_bot.py** — Telegram bot polling handler, routes commands through mt5ctl
- **mt5_logcheck.py** — weekly health checks (container, MT5 process, broker, charts, trees, warmup)
- **mt5_summary.py** — daily/weekly/monthly summaries with expectation bands
- **mt5_alert.py** — dual-channel alert dispatcher (SMTP + Telegram)

## Pipeline Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌──────────────────────┐
│ AccountSnapshot │────▶│   mt5ctl        │────▶│  Python consumers    │
│ .mq5 (EA)       │     │  (bash CLI)     │     │  (bot, logcheck,     │
│ writes JSON     │     │  reads via      │     │   summary, alert)    │
│ every 60s       │     │  docker exec    │     │                      │
└─────────────────┘     └─────────────────┘     └──────────────────────┘
         │                       │                        │
         ▼                       ▼                        ▼
   FILE_COMMON              mt5ctl                     Telegram/
   /account_snapshot.json   dashboard/                Email
                            status/health/
                            charts/alert
```

**Key invariant**: EA is the data bottleneck. All consumers read from the EA's JSON. Adding dimensions to the EA automatically makes them available everywhere — no consumer changes needed.

## Command Architecture (v3)

**mt5ctl** — single entry point with `--section` filter:
```
mt5ctl dashboard                    # full dashboard
mt5ctl dashboard positions          # open trades
mt5ctl dashboard history            # closed trades
mt5ctl dashboard exposure           # by symbol + strategy
mt5ctl dashboard drawdown           # peak equity + DD
mt5ctl dashboard risk               # margin + per-position R:R
mt5ctl dashboard orders             # pending orders
mt5ctl dashboard equity             # equity curve (24h hourly)
mt5ctl dashboard rolling            # daily/weekly/monthly PnL
mt5ctl status                       # 1-line health
mt5ctl health [days]                # full logcheck
mt5ctl charts                       # chart attach status
mt5ctl alert test                   # test email + Telegram
```

**Telegram bot** — unified `/dashboard [section]` command:
```
/dashboard          # full dashboard
/positions          # open trades
/history            # closed trades
/exposure           # by symbol + strategy
/drawdown           # peak equity + DD
/risk               # margin + R:R
/orders             # pending orders
/equity             # equity curve
/rolling            # daily/weekly/monthly
/status             # 1-line health
/health             # full health
/charts             # chart status
/help               # clickable command menu
```

All legacy aliases (`/pnl`, `/open`, `/trades`, `/snap`) map to `/dashboard`.

## Critical Constraints (NEVER VIOLATE)

| # | Constraint | Rationale |
|---|------------|-----------|
| C1 | **Never restart MT5 container for EA updates** | Kills live EAs on charts. Use `docker cp` + manual re-attach via noVNC. |
| C2 | **MT5 does not hot-reload .ex5 binaries** | New binary only takes effect after removing EA from chart and re-attaching. |
| C3 | **AccountSnapshot is an EA, not an indicator** | Uses `EventSetTimer`/`OnTimer`, not `OnCalculate`. Attach to ANY chart. |
| C4 | **POSITION_COMMISSION_REAL does not exist on deployed build** | Compiler rejects it. Use `POSITION_COMMISSION` (deprecation warning is harmless). |
| C5 | **Log files + snapshot JSON use UTF-16 LE with BOM** | All readers must handle BOM detection and decoding. |
| C6 | **Python f-strings with double-quoted dict subscripts break in bash heredocs** | Use `p['key']` (single quotes) or `ROLL_INDENT` variable instead of inline. |
| C7 | **Unicode escapes (`\u2500`) break in bash double-quoted heredocs** | Define shell var: `SEP='\u2500\u2500'` then use `${SEP[0]}` in Python. |
| C8 | **Telegram ignores all markup inside `<pre>`/` ``` ` codeblocks** | Use `<b>` for headers + `<pre>` for data blocks; never wrap entire output in codeblocks. |
| C9 | **Deploy via `docker cp` only** | Container restart is ONLY for catastrophic failures. |
| C10 | **Peak equity must persist across EA restarts** | Implemented via file persistence + historical deal reconstruction (v4.02+). |

## Key Decisions Log

| Date | Decision | Context |
|------|----------|---------|
| 2026-07-15 | EA is the data bottleneck — upgrade EA first | Adding dimensions to EA JSON flows to all consumers automatically |
| 2026-07-15 | Unified `/dashboard [section]` replaces 6 separate commands | Fragmented commands were redundant; single view with drill-down is superior |
| 2026-07-15 | Section dashboards must be comprehensive, not one-liners | Shallow sections were useless; each section now computes from positions array |
| 2026-07-15 | No `show_account()` in section functions | Dispatch block handles single account header; sections render only their content |
| 2026-07-15 | `section_end()` is no-op | Section headers (`──`) provide visual separation; blank lines created double-gaps |
| 2026-07-15 | HTML parse mode (`<b>` + `<pre>`) replaces codeblocks | Codeblocks suppress bold/italic; `<pre>` preserves alignment + allows markup |
| 2026-07-15 | `setMyCommands` registers all 13 commands as clickable menu items | Users click instead of typing; `/help` text uses plain text commands |
| 2026-07-15 | Historical peak equity reconstructed from deal history | EA attach time was ~7485, but account inception was 8300 — full history query fixes DD |
| 2026-07-15 | Rolling avg line `│` aligned with main line | Visual consistency: `ROLL_INDENT = 25 spaces` matches main line pipe position |
| 2026-07-15 | Singular/plural "1 point" vs "N points" | Grammar fix in equity curve label |

## EA Version History

| Version | Key Changes |
|---------|-------------|
| v3 | Rolling daily/weekly/monthly PnL, position_summary, history_summary, 90-day history, DEAL_ENTRY_INOUT |
| v4.00 | peak_equity, drawdown_pct, margin_utilization, symbol_exposure, strategy_performance, pending_orders, position_risks, avg_trade_stats, equity_snapshots |
| v4.01 | peak_equity persisted to file (`peak_equity.dat`), survives OnInit restarts; rolling stats include avg_win/avg_loss |
| v4.02 | **FindHistoricalPeakBalance()** — queries ALL deal history on init, reconstructs running balance from first deposit, finds true all-time peak. Drawdown now reflects account inception (8300 USC) not EA attach time. |

## File Structure (Canonical)

```
metatrader-docker-deployment/
├── README.md                    # Main repo docs (deploy MT4/MT5, monitoring)
├── ARCHITECTURE.md              # This file
├── deploy-mt4.sh                # One-command MT4 + auth + tunnel deploy
├── deploy-mt5.sh                # One-command MT5 + auth + tunnel deploy
├── deploy-monitoring.sh         # Wrapper → monitoring/install.sh
├── deploy-ea-bundle.sh          # Install EA bundles (ex5 + sets + SHA256)
├── sync-mql.sh                  # Status check for MQL files (no container restart)
├── provision-host.sh            # 1-2GB VPS hardening (zram, purge snap, docker log rotation)
├── scripts/check-exness-latency.sh  # TCP RTT to live trade server
├── MT4/                         # MT4 stack (Dockerfile, compose, auth, mql4)
├── MT5/                         # MT5 stack (Dockerfile, compose, auth, mql5)
│   └── mql5/Experts/AccountSnapshot.mq5   # ← Source of truth for EA
└── monitoring/
    ├── README.md                # Monitoring stack docs
    ├── install.sh               # Installs to ~/mt5-monitoring + systemd
    ├── systemd/
    │   ├── mt5-logcheck.service/.timer
    │   ├── mt5-summary-daily.service/.timer
    │   ├── mt5-summary-weekly.service/.timer
    │   └── mt5-bot.service
    ├── config/alert.conf.example
    └── bin/
        ├── mt5ctl               # Main CLI (bash + embedded Python)
        ├── mt5_bot.py           # Telegram bot (HTML parse mode)
        ├── mt5_logcheck.py      # Core health checks
        ├── mt5_logcheck.sh      # Wrapper for systemd
        ├── mt5_summary.py       # Daily/weekly/monthly summaries
        └── mt5_alert.py         # Email + Telegram dispatcher
```

## Redundancy Audit (2026-07-15)

| File | Status | Notes |
|------|--------|-------|
| `deploy_v2.sh` | **ARCHIVED** | References v2 EA, restarts container (violates C1). Superseded by manual `docker cp` + monitoring/install.sh |
| `deploy-ea-bundle.sh --restart` | **FLAGGED** | Line 40 restarts container. Should document manual re-attach instead. |
| `sync-mql.sh` | **FLAGGED** | Line 39 restarts container. For general MQL sync only; EA updates use docker cp. |
| `MT5/prepare-build.sh` | **UNUSED** | Not referenced by any deploy script. Can be removed. |

**Action**: Archive `deploy_v2.sh` to `archive/` or remove. Update flagged scripts to document correct no-restart workflow.

## Deployment Checklist (No-Restart)

```bash
# 1. Compile EA locally or on VPS
docker cp AccountSnapshot.mq5 mt5-terminal:/config/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Experts/
docker exec mt5-terminal bash -c 'cd "/config/.wine/drive_c/Program Files/MetaTrader 5" && wine MetaEditor64.exe "/compile:MQL5/Experts/AccountSnapshot.mq5" "/log:MQL5/Experts/compile.log"'

# 2. Copy updated CLI + bot
scp monitoring/bin/mt5ctl monitoring/bin/mt5_bot.py ishanp@20.24.213.8:/tmp/
ssh ishanp@20.24.213.8 "sudo cp /tmp/mt5ctl /home/ishanp/mt5-deploy/logcheck/bin/ && sudo cp /tmp/mt5_bot.py /home/ishanp/mt5-deploy/logcheck/bin/ && sudo systemctl restart mt5-bot"

# 3. User re-attaches EA via noVNC:
#    Right-click chart → Expert Advisors → Remove → Drag AccountSnapshot.ex5 onto chart
#    Confirm "[AccountSnapshot] v4.02 attached" in Experts log
```

## Verification Commands

```bash
# On VPS:
export PATH="$HOME/mt5-monitoring/bin:$PATH"
mt5ctl status
mt5ctl dashboard
mt5ctl dashboard drawdown    # Should show peak ~8300, DD ~12%
mt5ctl health

# In Telegram:
/dashboard
/drawdown
/status
/help    # All 13 commands clickable
```

## Known Limitations

1. **Historical floating PnL not reconstructible** — Deal history only has closed deals. True peak equity (including floating) requires tick data. Current implementation tracks peak *balance* from deals, which is a conservative lower bound.
2. **Equity snapshots only 24h** — Circular buffer of 24 hourly points. Longer history needs persistent storage.
3. **Single EA instance** — AccountSnapshot attaches to one chart. Multiple charts = duplicate writes.
4. **No database** — All state is files. Horizontal scaling not supported.