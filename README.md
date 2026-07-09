# MetaTrader Docker Deployment

Production-grade MetaTrader 4 & 5 deployment using Docker with browser-based noVNC access.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/ishan-parihar/metatrader-docker-deployment.git
cd metatrader-docker-deployment

# 1. Place your MT4/MT5 binaries (see below)
# 2. Configure credentials
# 3. Start terminals
cd MT4 && docker compose up -d    # MT4 on http://localhost:6081
cd ../MT5 && docker compose up -d # MT5 on http://localhost:6080
```

## Directory Structure

```
metatrader-docker-deployment/
├── MT4/                          # MetaTrader 4 (32-bit, works on any x86)
│   ├── Dockerfile                # Wine 8.0 (avoids Themida detection)
│   ├── docker-compose.yml
│   ├── .env.example              # Copy to .env and configure
│   └── start.sh
├── MT5/                          # MetaTrader 5 (64-bit, requires AVX2)
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── .env.example              # Copy to .env and configure
│   ├── prepare-build.sh          # Extract terminal64.exe from installer
│   └── start.sh
├── mql4mt5/                      # Your EA/Indicator/Script files
│   ├── MQL4/                     # MT4 files (mounted into MT4 container)
│   │   ├── Experts/              # .ex4 files
│   │   ├── Indicators/           # .ex4 files
│   │   ├── Scripts/              # .ex4 files
│   │   ├── Presets/              # .set files
│   │   ├── Files/                # Data files
│   │   └── Libraries/            # .dll files
│   └── MQL5/                     # MT5 files (mounted into MT5 container)
│       ├── Experts/              # .ex5 files
│       ├── Indicators/           # .ex5 files
│       ├── Scripts/              # .ex5 files
│       ├── Presets/              # .set files
│       ├── Files/                # Data files
│       └── Libraries/            # .dll files
├── sync-mql.sh                   # Refresh script
└── README.md
```

## Prerequisites

- Docker & Docker Compose
- MT4/MT5 terminal binaries (user-provided)

## Setting Up MT4

### 1. Place Binaries

Copy your MT4 terminal files into `MT4/mt4-bin/`:

```bash
# From your Windows MT4 installation, copy:
# - terminal.exe
# - metaeditor.exe (optional)
# - terminal.ico (optional)
# - config/ directory

cp -r /path/to/MT4/installation/* MT4/mt4-bin/
```

### 2. Configure Credentials

```bash
cp MT4/.env.example MT4/.env
# Edit MT4/.env with your broker credentials
```

### 3. Start

```bash
cd MT4
docker compose up -d
```

Access at: **http://localhost:6081**

## Setting Up MT5

### 1. Extract Binaries

Use the provided script to extract from the official installer:

```bash
cd MT5
./prepare-build.sh
# Downloads and extracts terminal64.exe automatically
```

Or manually place `terminal64.exe` and `Config/` directory in `MT5/mt5-bin/`.

### 2. Configure Credentials

```bash
cp MT5/.env.example MT5/.env
# Edit MT5/.env with your broker credentials
```

### 3. Start

```bash
cd MT5
docker compose up -d
```

Access at: **http://localhost:6080**

## Adding EAs and Indicators

Drop your compiled EA/Indicator/Script files into the appropriate directories:

```bash
# MT4
cp MyEA.ex4 mql4mt5/MQL4/Experts/
cp MyIndicator.ex4 mql4mt5/MQL4/Indicators/

# MT5
cp MyEA.ex5 mql4mt5/MQL5/Experts/
cp MyIndicator.ex5 mql4mt5/MQL5/Indicators/

# Refresh terminals to pick up changes
./sync-mql.sh all
```

## Sync Script

```bash
./sync-mql.sh [mt4|mt5|all|status]
```

| Command | Description |
|---------|-------------|
| `./sync-mql.sh mt4` | Restart MT4 terminal |
| `./sync-mql.sh mt5` | Restart MT5 terminal |
| `./sync-mql.sh all` | Restart both terminals |
| `./sync-mql.sh status` | Show directory and container status |

## Environment Variables

### MT4

| Variable | Description | Default |
|----------|-------------|---------|
| `MT4_BROKER_LOGIN` | Broker account number | (required) |
| `MT4_BROKER_PASSWORD` | Broker password | (required) |
| `MT4_BROKER_SERVER` | Broker server name | `MetaQuotes-Demo` |

### MT5

| Variable | Description | Default |
|----------|-------------|---------|
| `MT5_BROKER_LOGIN` | Broker account number | (required) |
| `MT5_BROKER_PASSWORD` | Broker password | (required) |
| `MT5_BROKER_SERVER` | Broker server name | `MetaQuotes-Demo` |
| `TZ` | Timezone | `UTC` |

## Hardware Requirements

| | MT4 | MT5 |
|---|---|---|
| **Architecture** | 32-bit (x86) | 64-bit (x86_64) |
| **CPU Requirement** | Any x86 CPU | AVX2 support required |
| **Wine Version** | 8.0 | 11.0 |
| **Memory** | 512MB | 2GB |

### Checking AVX2 Support

```bash
# Linux
grep -o avx2 /proc/cpuinfo

# If empty, use MT4 (32-bit) instead of MT5
```

## Troubleshooting

### MT4: "Debugger has been found running" Error

This is a Themida protection issue with Wine 11+. The MT4 Dockerfile uses Wine 8.0 to avoid this. If you still see this error:

```bash
cd MT4
docker compose down
docker compose build --no-cache
docker compose up -d
```

### MT5: Terminal Won't Start (AVX2 Error)

MT5 requires AVX2 instruction support. Check your CPU:

```bash
grep -o avx2 /proc/cpuinfo
# If empty, your CPU doesn't support AVX2
# Use MT4 instead (32-bit, works on any x86)
```

### EAs Not Showing

1. Ensure files are in the correct directory (`mql4mt5/MQL4/Experts/` or `mql4mt5/MQL5/Experts/`)
2. Run `./sync-mql.sh` to restart terminals
3. Check the terminal's Navigator panel

### Container Won't Start

```bash
# Check logs
docker compose logs -f

# Rebuild from scratch
docker compose down -v
docker compose build --no-cache
docker compose up -d
```

## Production Deployment

### VPS Deployment

```bash
# On your VPS
git clone https://github.com/ishan-parihar/metatrader-docker-deployment.git
cd metatrader-docker-deployment

# Configure credentials
cp MT5/.env.example MT5/.env
nano MT5/.env

# Start
cd MT5
docker compose up -d

# Access via browser
# http://your-vps-ip:6080
```

### Running Multiple Terminals

```bash
# Start both MT4 and MT5
docker compose -f MT4/docker-compose.yml up -d
docker compose -f MT5/docker-compose.yml up -d
```

## License

MIT
