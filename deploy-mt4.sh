#!/bin/bash
# MT4 Production Deployment Script
# Deploys MT4 terminal + auth gateway + cloudflared tunnel
set -e

DOMAIN="${1:-mt4.ishanparihar.com}"
AUTH_PORT=6082
TERM_PORT=6081

echo "=== MT4 Deployment ==="
echo "Domain: $DOMAIN"
echo "Auth proxy port: $AUTH_PORT"
echo "Terminal noVNC port: $TERM_PORT"
echo ""

# 1. Build and start MT4 terminal
echo "[1/4] Building MT4 terminal..."
cd MT4
cp .env.example .env 2>/dev/null || true
echo "  Edit MT4/.env with your broker credentials, then press Enter to continue..."
read -r
docker compose up -d --build
cd ..

# 2. Build and start auth proxy
echo "[2/4] Building auth proxy..."
cd MT4/auth
cp .env.example .env 2>/dev/null || true
echo "  Edit MT4/auth/.env to set AUTH_USER and AUTH_PASS, then press Enter..."
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
TUNNEL_NAME="mt4-terminal"
if ! cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
    echo "  Creating tunnel: $TUNNEL_NAME"
    cloudflared tunnel create "$TUNNEL_NAME"
fi

TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
CRED_FILE="$HOME/.cloudflared/$TUNNEL_ID.json"

# Write config
cat > MT4/auth/cloudflared-config.yml << EOF
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
nohup cloudflared --no-autoupdate tunnel --config MT4/auth/cloudflared-config.yml run > MT4/auth/cloudflared.log 2>&1 &
echo "  Tunnel PID: $!"

echo ""
echo "=== Deployment Complete ==="
echo "Local access:  http://localhost:$AUTH_PORT"
echo "Remote access: https://$DOMAIN"
echo ""
echo "Credentials are in MT4/auth/.env"
echo "Tunnel logs:   tail -f MT4/auth/cloudflared.log"
