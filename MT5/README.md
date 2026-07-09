# MT5 Docker with noVNC

Standalone MetaTrader 5 terminal running in Docker with browser-based remote access via noVNC.

## Quick Start

```bash
# 1. Copy environment config
cp .env.example .env

# 2. Edit .env with your broker credentials
nano .env

# 3. Place MT5 binaries in ./mt5-bin/
#    - terminal64.exe
#    - Config/ (optional, for saved profiles)

# 4. Place EA .ex5 files in ./ea/ (optional)

# 5. Build and run
docker compose up -d

# 6. Open browser
http://localhost:6080
```

## Directory Structure

```
MT5-docker-general/
├── Dockerfile          # MT5 + Wine + noVNC container
├── docker-compose.yml  # Container orchestration
├── start.sh            # Container startup script
├── .env.example        # Environment variables template
├── mt5-bin/            # Place MT5 binaries here
│   └── terminal64.exe  # Required
└── ea/                 # Place .ex5 EA files here (optional)
```

## Prerequisites

1. **MT5 Binaries**: Copy `terminal64.exe` from your Windows MT5 installation
   - Location: `C:\Program Files\MetaTrader 5\terminal64.exe`
   - Place in `./mt5-bin/`

2. **Docker**: Docker Desktop or Docker Engine with Compose v2

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MT5_BROKER_LOGIN` | (empty) | Broker account number |
| `MT5_BROKER_PASSWORD` | (empty) | Broker password |
| `MT5_BROKER_SERVER` | `MetaQuotes-Demo` | Broker server name |
| `MT5_ENABLE_NOVNC` | `1` | Enable browser-based VNC |
| `MT5_NOVNC_PORT` | `6080` | noVNC web interface port |
| `MT5_ENABLE_VNC` | `0` | Enable native VNC server |
| `MT5_VNC_PORT` | `5900` | VNC server port |
| `TZ` | `UTC` | Container timezone |

## Ports

| Port | Service | Access |
|------|---------|--------|
| 6080 | noVNC | Browser: `http://localhost:6080` |
| 5900 | VNC | Native VNC client (optional) |

## Usage

### First Run
1. Container initializes Wine prefix (takes ~30 seconds)
2. Wine Mono is installed automatically
3. MT5 terminal starts
4. Open browser to `http://localhost:6080`
5. Log in to your broker account via MT5 GUI

### Subsequent Runs
- Wine prefix persists in Docker volume `mt5-config`
- MT5 starts faster (~5 seconds)
- Your settings and profiles are preserved

### Installing EAs
1. Place `.ex5` files in `./ea/` directory
2. Inside the container, copy to MT5 Experts folder:
   ```bash
   docker exec -it mt5-terminal bash
   cp /opt/mt5/ea/*.ex5 "$HOME/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/"
   ```
3. In MT5: Navigator → Expert Advisors → Refresh

### Using the MCP Server (Optional)
The container exposes port 8001 for mt5linux RPyC if you want to use the Python MetaTrader5 package:
```python
import MetaTrader5 as mt5
mt5.initialize()
mt5.login(login, password, server)
```

## Troubleshooting

### Container won't start
```bash
docker compose logs mt5
```

### noVNC shows black screen
- Wait 30 seconds for MT5 to initialize
- Check if Xvfb is running: `docker exec mt5-terminal pgrep Xvnc`

### Can't connect to broker
- Verify credentials in `.env`
- Check broker server name (exact spelling)
- Some brokers require VPN or specific network configuration

### Performance issues
- Default memory limit: 2GB
- Increase in `docker-compose.yml` if needed
- VNC quality can be adjusted in noVNC settings (gear icon)

## Building Custom Images

```bash
# Build with custom MT5 binaries
docker compose build --no-cache

# Run with different settings
MT5_BROKER_LOGIN=12345 MT5_BROKER_SERVER=ICMarkets docker compose up -d
```
