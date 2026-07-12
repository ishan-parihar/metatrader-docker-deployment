# systemd units

These are template files. The installer (`../install.sh`) substitutes
`%USER` and `%HOME` with the actual values before installing them.

## Files

| File | Purpose |
|---|---|
| `mt5-logcheck.service` / `.timer` | Weekly health check (Sunday 18:00) |
| `mt5-summary-daily.service` / `.timer` | Daily summary email (23:00) |
| `mt5-summary-weekly.service` / `.timer` | Weekly summary email (Sunday 18:00) |
| `mt5-bot.service` | Telegram bot polling handler (long-running) |

## Manual install (if not using `install.sh`)

```bash
# Substitute placeholders
USER=$(whoami)
HOME_DIR=$HOME
sed -e "s|%USER|$USER|g" -e "s|%HOME|$HOME_DIR|g" mt5-logcheck.service | sudo tee /etc/systemd/system/mt5-logcheck.service
# ... repeat for each unit
sudo systemctl daemon-reload
sudo systemctl enable --now mt5-logcheck.timer mt5-summary-daily.timer mt5-summary-weekly.timer mt5-bot.service
```

## Status

```bash
systemctl list-timers mt5-*
systemctl status mt5-bot.service
```
