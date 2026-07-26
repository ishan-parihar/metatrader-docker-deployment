# MetaTrader Docker Deployment

![Docker](https://img.shields.io/badge/Docker-24+-blue?logo=docker)
![License](https://img.shields.io/badge/License-MIT-green)
![Wine](https://img.shields.io/badge/Wine-9.0+-red?logo=winehq)
![Cloudflare](https://img.shields.io/badge/Cloudflare_Tunnel-orange?logo=cloudflare)
![noVNC](https://img.shields.io/badge/noVNC-1.4+-green)


**Deploy MT4/MT5 to cloud in one command** — noVNC remote access, Cloudflare tunnel auth, Wine-powered, production-ready.

![MT5 in browser](https://github.com/ishan-parihar/metatrader-docker-deployment/raw/main/assets/readme/mt5-novnc.png)

---

## What it is

| Component | Technology |
|-----------|------------|
| **MT4/MT5** | Windows apps via Wine 9+ |
| **Remote UI** | noVNC (browser-based VNC) |
| **Auth** | Cloudflare Tunnel + Access (Zero Trust) |
| **Orchestration** | Docker Compose, systemd-ready |
| **Persistence** | Named volumes for config/terminals |

**Use case:** Run EAs 24/7 on cheap VPS, access from any browser, zero Windows license.

---

## Quick start

```bash
# Clone
git clone https://github.com/ishan-parihar/metatrader-docker-deployment
cd metatrader-docker-deployment

# Configure
cp .env.example .env
# Edit .env: CLOUDFLARE_TUNNEL_TOKEN, VNC_PASSWORD, MT_VERSION=5

# Deploy
docker compose up -d

# Access: https://mt5.yourdomain.com (Cloudflare Access protected)
```

---


## Features

| Feature | Details |
|---------|---------|
| **MT4 & MT5** | Switch via `MT_VERSION` env |
| **Multi-terminal** | Run multiple accounts in one container |
| **EA support** | Copy `.ex4`/`.ex5` to `experts/` volume |
| **Cloudflare Access** | Email, GitHub, Google, OTP auth |
| **Auto-restart** | `restart: unless-stopped` + healthcheck |
| **Backup** | `docker compose exec mt5 backup` |

---

## Configuration

```bash
# .env
CLOUDFLARE_TUNNEL_TOKEN=xxx
VNC_PASSWORD=secure_password
MT_VERSION=5                    # or 4
MT_LOGIN=12345678               # optional: auto-login
MT_PASSWORD=******              # optional
MT_SERVER=MetaQuotes-Demo       # optional
TIMEZONE=UTC
```

---

## Commands

| Command | Description |
|---------|-------------|
| `docker compose up -d` | Deploy |
| `docker compose logs -f` | View logs |
| `docker compose exec mt5 backup` | Backup terminals |
| `docker compose exec mt5 restore` | Restore backup |
| `docker compose down` | Stop |

---



## Visual proof

| noVNC MT5 | Architecture | Deploy output |
|:---:|:---:|:---:|
| ![noVNC](https://github.com/ishan-parihar/metatrader-docker-deployment/raw/main/assets/readme/novnc.png) | ![Arch](https://github.com/ishan-parihar/metatrader-docker-deployment/raw/main/assets/readme/arch.png) | ![Deploy](https://github.com/ishan-parihar/metatrader-docker-deployment/raw/main/assets/readme/deploy.png) |

| Cloudflare auth | Multi-terminal | Backup/restore |
|:---:|:---:|:---:|
| ![Auth](https://github.com/ishan-parihar/metatrader-docker-deployment/raw/main/assets/readme/auth.png) | ![Multi](https://github.com/ishan-parihar/metatrader-docker-deployment/raw/main/assets/readme/multi.png) | ![Backup](https://github.com/ishan-parihar/metatrader-docker-deployment/raw/main/assets/readme/backup.png) |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Cloudflare Tunnel (Zero Trust)                  │
│         HTTPS + Auth (email/SSO/OTP)                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Docker Host                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Container: metatrader                                │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │    │
│  │  │  Wine   │─▶│  MT5    │  │  Xvfb   │             │    │
│  │  │  (Win10)│  │  terminal│  │  :99    │             │    │
│  │  └─────────┘  └─────────┘  └────┬────┘             │    │
│  │                                 │                   │    │
│  │  ┌─────────┐  ┌─────────┐      │                   │    │
│  │  │  x11vnc │──▶│  noVNC  │──────┘                   │    │
│  │  │  :5900  │  │  :6080  │                          │    │
│  │  └─────────┘  └─────────┘                          │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## Requirements

- Docker 24+ / Docker Compose 2+
- Cloudflare account (free tier works)
- Domain (or use Cloudflare Pages subdomain)
- 2 GB RAM minimum (4 GB recommended)
- Linux host (x86_64)

---

## License

MIT — see [LICENSE](LICENSE).
