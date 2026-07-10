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

## EA/Script/Indicator Deployment

Place MQL files in `mql4mt5/`:

```
mql4mt5/
├── MQL4/
│   ├── Experts/      # MT4 Expert Advisors (.ex4)
│   ├── Indicators/   # MT4 Indicators (.ex4)
│   ├── Scripts/      # MT4 Scripts (.ex4)
│   └── Presets/      # MT4 Preset files (.set)
├── MQL5/
│   ├── Experts/      # MT5 Expert Advisors (.ex5)
│   ├── Indicators/   # MT5 Indicators (.ex5)
│   ├── Scripts/      # MT5 Scripts (.ex5)
│   └── Presets/      # MT5 Preset files (.set)
```

Sync changes:

```bash
./sync-mql.sh
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
