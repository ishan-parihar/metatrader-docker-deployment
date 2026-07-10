#!/bin/bash
# MT5 Production Deployment Script
# Deploys MT5 terminal + auth gateway + cloudflared tunnel
# Requires: x86_64 CPU with AVX2 support
set -e

DOMAIN="${1:-mt5.ishanparihar.com}"
AUTH_PORT=6083
TERM_PORT=6080

echo "=== MT5 Deployment ==="
echo "Domain: $DOMAIN"
echo "Auth proxy port: $AUTH_PORT"
echo "Terminal noVNC port: $TERM_PORT"
echo ""

# Check AVX2 support
if ! grep -q avx2 /proc/cpuinfo; then
    echo "ERROR: CPU does not support AVX2. MT5 requires AVX2."
    echo "Use MT4 for systems without AVX2."
    exit 1
fi

# 1. Build and start MT5 terminal
echo "[1/4] Building MT5 terminal..."
cd MT5
cp .env.example .env 2>/dev/null || true
echo "  Edit MT5/.env with your broker credentials, then press Enter to continue..."
read -r
docker compose up -d --build
cd ..

# 2. Build and start auth proxy
echo "[2/4] Building auth proxy..."
cd MT5/auth
cp .env.example .env 2>/dev/null || true
echo "  Edit MT5/auth/.env to set AUTH_USER and AUTH_PASS, then press Enter..."
read -r
docker compose up -d --build
cd ../..

# 3. Install cloudflared (if not present)
echo "[3/4] Checking cloudflared..."
if ! command -v cloudflared &> /dev/null; then
    echo "  Installing cloudflared..."
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi
echo "  cloudflared version: $(cloudflared --version)"

# 4. Create tunnel
echo "[4/4] Setting up cloudflared tunnel..."
TUNNEL_NAME="mt5-terminal"
if ! cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    echo "  Creating tunnel: $TUNNEL_NAME"
    cloudflared tunnel create "$TUNNEL_NAME"
fi

TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
CRED_FILE="$HOME/.cloudflared/$TUNNEL_ID.json"

# Write config
cat > MT5/auth/cloudflared-config.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: $DOMAIN
    service: http://localhost:$AUTH_PORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

# Route DNS
echo "  Routing DNS for $DOMAIN..."
cloudflared tunnel route dns "$TUNNEL_ID" "$DOMAIN" 2>/dev/null || true

# Start tunnel
echo "  Starting cloudflared tunnel..."
nohup cloudflared --no-autoupdate tunnel --config MT5/auth/cloudflared-config.yml run > MT5/auth/cloudflared.log 2>&1 &
echo "  Tunnel PID: $!"

echo ""
echo "=== Deployment Complete ==="
echo "Local access:  http://localhost:$AUTH_PORT"
echo "Remote access: https://$DOMAIN"
echo ""
echo "Credentials are in MT5/auth/.env"
echo "Tunnel logs:   tail -f MT5/auth/cloudflared.log"
