# MetaTrader Docker Deployment

Docker-based MetaTrader 4 & 5 deployment with noVNC remote access and Cloudflare tunnel authentication.

## Requirements

| Platform | CPU | Wine | noVNC Port | Auth Port |
|----------|-----|------|------------|-----------|
| MT5 | x86_64 with AVX2 | 11.0 (64-bit) | 6080 | 6083 |
| MT4 | Any x86 | 8.0 (32-bit) | 6081 | 6082 |

## One-Command Deploy (MT4)

```bash
# Clone and deploy
git clone https://github.com/ishan-parihar/metatrader-docker-deployment.git
cd metatrader-docker-deployment

# Configure credentials
cp MT4/.env.example MT4/.env
cp MT4/auth/.env.example MT4/auth/.env

# Edit with your broker credentials
nano MT4/.env      # Set MT4_BROKER_LOGIN, MT4_BROKER_PASSWORD, MT4_BROKER_SERVER
nano MT4/auth/.env  # Set AUTH_USER, AUTH_PASS (login page credentials)

# Deploy everything
chmod +x deploy-mt4.sh
./deploy-mt4.sh mt4.ishanparihar.com
```

**Access:** `https://mt4.ishanparihar.com` (login required)

## One-Command Deploy (MT5)

```bash
# Clone and deploy
git clone https://github.com/ishan-parihar/metatrader-docker-deployment.git
cd metatrader-docker-deployment

# Configure credentials
cp MT5/.env.example MT5/.env
cp MT5/auth/.env.example MT5/auth/.env

# Edit with your broker credentials
nano MT5/.env      # Set MT5_BROKER_LOGIN, MT5_BROKER_PASSWORD, MT5_BROKER_SERVER
nano MT5/auth/.env  # Set AUTH_USER, AUTH_PASS (login page credentials)

# Deploy everything
chmod +x deploy-mt5.sh
./deploy-mt5.sh mt5.ishanparihar.com
```

**Access:** `https://mt5.ishanparihar.com` (login required)

## Manual Deploy

### MT4

```bash
# 1. Start terminal
cd MT4
cp .env.example .env
# Edit .env with broker credentials
docker compose up -d
# Local access: http://localhost:6081

# 2. Start auth proxy
cd auth
cp .env.example .env
# Edit .env with login credentials
docker compose up -d
# Local access: http://localhost:6082

# 3. Create cloudflared tunnel
cloudflared tunnel create mt4-terminal
cloudflared tunnel route dns <tunnel-id> mt4.ishanparihar.com

# 4. Start tunnel
nohup cloudflared --no-autoupdate tunnel --config auth/cloudflared-config.yml run &
```

### MT5

```bash
# 1. Start terminal
cd MT5
cp .env.example .env
# Edit .env with broker credentials
docker compose up -d
# Local access: http://localhost:6080

# 2. Start auth proxy
cd auth
cp .env.example .env
# Edit .env with login credentials
docker compose up -d
# Local access: http://localhost:6083

# 3. Create cloudflared tunnel
cloudflared tunnel create mt5-terminal
cloudflared tunnel route dns <tunnel-id> mt5.ishanparihar.com

# 4. Start tunnel
nohup cloudflared --no-autoupdate tunnel --config auth/cloudflared-config.yml run &
```

## Credential Files

### MT4/.env

```env
MT4_BROKER_LOGIN=your_login
MT4_BROKER_PASSWORD=your_password
MT4_BROKER_SERVER=Exness-MT4Real8
```

### MT4/auth/.env

```env
AUTH_USER=admin
AUTH_PASS=your_secure_password
```

### MT5/.env

```env
MT5_BROKER_LOGIN=your_login
MT5_BROKER_PASSWORD=your_password
MT5_BROKER_SERVER=Exness-MT5Real25
```

### MT5/auth/.env

```env
AUTH_USER=admin
AUTH_PASS=your_secure_password
```

**Note:** Passwords with `@` are handled automatically via `.bat` launcher.

## Directory Structure

Each terminal owns its MQL directory. Drop EAs, scripts, indicators, and presets directly into the appropriate folder:

```
MT4/
├── Dockerfile
├── docker-compose.yml
├── start.sh
├── mql4/                  # MT4 MQL source of truth
│   ├── Experts/           # .ex4 files
│   ├── Indicators/        # .ex4 files
│   ├── Scripts/           # .ex4 files
│   ├── Presets/           # .set files
│   └── Files/
├── config/                # Terminal config (servers.dat, common.ini)
└── auth/                  # Authentication proxy

MT5/
├── Dockerfile
├── docker-compose.yml
├── start.sh
├── mql5/                  # MT5 MQL source of truth
│   ├── Experts/           # .ex5 files
│   ├── Indicators/        # .ex5 files
│   ├── Scripts/           # .ex5 files
│   ├── Presets/           # .set files
│   └── Files/
├── config/                # Terminal config (servers.dat, common.ini)
└── auth/                  # Authentication proxy
```

## EA/Script/Indicator Deployment

### Drop-in (recommended)

Place files directly into the terminal's MQL folder:

```bash
# MT5: copy your EA
cp YourEA.ex5 MT5/mql5/Experts/

# MT4: copy your EA
cp YourEA.ex4 MT4/mql4/Experts/
```

### EA Bundle (automated)

```bash
./deploy-ea-bundle.sh /path/to/bundle --restart
```

A bundle = `<EA>.ex5` + `*.set` + `SHA256SUMS`. Verifies integrity, installs into the bind-mounted `MT5/mql5/`, restarts the terminal.

### Sync after changes

```bash
./sync-mql.sh [mt4|mt5|all|status]
```

## Architecture

```
MT4: Internet → Cloudflare → mt4-auth:6082 → mt4-terminal:6081 (noVNC)
MT5: Internet → Cloudflare → mt5-auth:6083 → mt5-terminal:6080 (noVNC)
```

## Auth Features

- Rate limit: 10 attempts per 5 minutes
- Session-based authentication (24h expiry)
- Nginx reverse proxy with WebSocket support
- Login page with lockout feedback

## Troubleshooting

### MT5 won't connect

- Ensure `servers.dat` is fresh (delete `MT5/config/` and restart)
- Verify broker server name matches exactly
- Check AVX2: `grep avx2 /proc/cpuinfo`

### MT4 Themida error

- Dockerfile uses Wine 8.0 to bypass Themida security checks
- Do not upgrade Wine version without testing

### noVNC not loading

- Check logs: `docker compose logs -f`
- Verify ports: `ss -tlnp | grep 608`

### Cloudflared tunnel not working

- Check tunnel status: `cloudflared tunnel list`
- Check logs: `tail -f auth/cloudflared.log`
- Re-authorize: `cloudflared tunnel login`

## License

MIT

## Production deployment (1-2GB VPS playbook)

Validated on Azure East Asia B2ats_v2 (894MB RAM) running the QuantFin-R&D
BOOK10 book (8 charts, Exness Standard Cent demo).

### 1. Provision the host FIRST

```bash
sudo bash provision-host.sh
```

Applies (idempotent, measured 676->338MB used on the reference box):
zram compressed swap (zstd, prio 100) + 3GB disk swapfile fallback,
snapd/lxd/multipathd purge, unattended-upgrades without auto-reboot,
docker json-file log rotation (20mx3), UTC.

### 2. Deploy the stack

```bash
./deploy-mt5.sh yourdomain.example
```

On a 1GB host set in `MT5/.env`: `MT5_MEM_LIMIT=800m`, `MT5_MAX_BARS=5000`.

### 3. Deploy an EA bundle

```bash
./deploy-ea-bundle.sh /path/to/bundle --restart
```

A bundle = `<EA>.ex5` + `*.set` + `SHA256SUMS` (reference layout:
QuantFin-R&D `STRATEGIES/PHANTOM/EA/sets/v10-cent/`). Verifies integrity,
installs into the bind-mounted `MT5/mql5/{Experts,Presets}`, restarts the
terminal. Re-run at every model retrain -- the bundle is the redeployable unit.

### 4. Verify latency to the broker (ground truth)

```bash
./scripts/check-exness-latency.sh
```

Finds the terminal's live trade-server peer and measures 5-sample TCP RTT +
geolocation. For bar-close/day-scale EAs (broker-side SL/TP), anything under
~150ms is economically irrelevant -- choose the VPS region for reliability,
not milliseconds.

### 5. Deploy the monitoring stack (optional but recommended)

```bash
# Configure alert channels first
cp monitoring/config/alert.conf.example monitoring/config/alert.conf
nano monitoring/config/alert.conf   # fill in SMTP + Telegram credentials
chmod 600 monitoring/config/alert.conf

# One-command install
./deploy-monitoring.sh
```

This deploys a complete health monitoring + alerting + Telegram bot stack:

- **Weekly health check** (Sunday 18:00) — verifies container, MT5 process,
  broker connection, all expected charts loaded with correct magics, 141-tree
  build confirmation, warmup completed, no FATAL errors
- **Daily summary email** (23:00) — PnL, trade count, expectation band check
- **Weekly summary email** (Sunday 18:00) — same with 7-day window
- **Telegram bot** (always running) — unified dashboard commands:
  `/dashboard` (full), `/positions`, `/history`, `/exposure`, `/drawdown`,
  `/risk`, `/orders`, `/equity`, `/rolling`, plus `/status`, `/health`,
  `/charts`, `/help` — all clickable in Telegram's command menu
- **AccountSnapshot EA v4.02** — already in `MT5/mql5/Experts/AccountSnapshot.mq5`;
  attach to any chart in MT5 to start streaming live equity/PnL with historical
  peak reconstruction (drawdown from account inception)

On-demand CLI (via SSH):

```bash
export PATH="$HOME/mt5-monitoring/bin:$PATH"
mt5ctl status              # 1-line health
mt5ctl dashboard           # full dashboard
mt5ctl dashboard positions # open trades
mt5ctl dashboard drawdown  # peak equity + drawdown
mt5ctl health              # full health check
mt5ctl charts              # chart attach status
mt5ctl alert test          # test email + Telegram
```

See `monitoring/README.md` for full documentation.

### Security notes

- **Credentials never go on the command line.** `start.sh` logs in via MT5's
  startup-config ini (`chmod 600`, shredded after startup; the terminal keeps
  credentials in its own encrypted store afterwards). The old
  `/login:/password:` args were visible to every process on the HOST.
- Prefer tunnel-only access: set `MT5_BIND=127.0.0.1` (or close 6080/5900/6083
  in the cloud firewall) and reach noVNC through the auth proxy + cloudflared.
- MT5-side RAM knobs (baked into the autostart ini): `MaxBars=5000`, algo
  trading pre-enabled, news off. Also hide all Market Watch symbols except
  the traded ones after first login.
