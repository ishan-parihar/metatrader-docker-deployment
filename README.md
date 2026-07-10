# MetaTrader Docker Deployment

Docker-based MetaTrader 4 & 5 deployment with noVNC remote access.

## Quick Start

### MT5 (Requires AVX2 CPU)

```bash
cd MT5
cp .env.example .env
# Edit .env with your broker credentials
docker compose up -d
# Access: http://localhost:6080
```

### MT4 (Any x86 CPU)

```bash
cd MT4
cp .env.example .env
# Edit .env with your broker credentials
docker compose up -d
# Access: http://localhost:6081
```

## Requirements

| Platform | CPU | Wine | Port |
|----------|-----|------|------|
| MT5 | x86_64 with AVX2 | 11.0 (64-bit) | 6080 |
| MT4 | Any x86 | 8.0 (32-bit) | 6081 |

## EA/Script/Indicator Deployment

Place your MQL files in the `mql4mt5/` directory:

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
└── config/
    ├── mt4/          # MT4 configuration files
    └── mt5/          # MT5 configuration files
```

### Syncing Changes

After modifying MQL files, restart the terminal to pick up changes:

```bash
./sync-mql.sh
```

## Auth Gateway (Production)

Both MT4 and MT5 include a login-protected gateway with brute-force protection.

### MT4 Auth Gateway

```bash
cd MT4/auth
cp .env.example .env
# Set AUTH_USER and AUTH_PASS
docker compose up -d
# Access: http://localhost:6082
```

### MT5 Auth Gateway

```bash
cd MT5/auth
cp .env.example .env
# Set AUTH_USER and AUTH_PASS
docker compose up -d
# Access: http://localhost:6083
```

### Features

- Rate limit: 10 attempts per 5 minutes
- Session-based authentication (24h expiry)
- Nginx reverse proxy to noVNC with WebSocket support
- Login page with lockout feedback

### Cloudflare Tunnel

For external access via HTTPS:

```bash
# MT4
cloudflared tunnel --url http://localhost:6082

# MT5
cloudflared tunnel --url http://localhost:6083
```

### Production Deployment

For persistent tunnels with custom domains:

```bash
# Create tunnel
cloudflared tunnel create <name>

# Route DNS
cloudflared tunnel route dns <tunnel-id> <domain>

# Run with config
cloudflared tunnel --config cloudflared-config.yml run
```

## Credential Configuration

### MT5

Edit `MT5/.env`:

```env
MT5_BROKER_LOGIN=your_login
MT5_BROKER_PASSWORD=your_password
MT5_BROKER_SERVER=Exness-MT5Real8
```

### MT4

Edit `MT4/.env`:

```env
MT4_BROKER_LOGIN=your_login
MT4_BROKER_PASSWORD=your_password
MT4_BROKER_SERVER=Exness-MT4Real8
```

**Important:** Passwords with special characters (like `@`) are handled automatically via `.bat` launcher.

## Troubleshooting

### MT5 won't connect

- Ensure `servers.dat` is fresh (delete `MT5/config/` and restart)
- Verify broker server name matches exactly
- Check that CPU supports AVX2: `grep avx2 /proc/cpuinfo`

### MT4 Themida error

- The Dockerfile uses Wine 8.0 to bypass Themida security checks
- Do not upgrade Wine version without testing

### noVNC not loading

- Check container logs: `docker compose logs -f`
- Verify ports are not in use: `ss -tlnp | grep 608`

## Architecture

```
MT4: Internet → Cloudflare → mt4-auth:6082 → mt4-terminal:6081 (noVNC)
MT5: Internet → Cloudflare → mt5-auth:6083 → mt5-terminal:6080 (noVNC)
```

## License

MIT
