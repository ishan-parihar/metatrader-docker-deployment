#!/bin/bash
# ============================================================================
# provision-host.sh — production host preparation for 1–2GB Linux VPS
# ============================================================================
# Applies the measured RAM/reliability patches (validated on Azure East Asia
# B2ats_v2, 894MB: usage dropped 676MB->338MB used / 59->399MB available):
#   1. 3GB disk swapfile (fallback tier)
#   2. zram compressed swap, zstd, priority 100 (used before disk swap)
#      - cloud kernels (Azure/AWS/GCP) need linux-modules-extra for zram
#   3. purge snapd + lxd (unused, ~25MB + mounts), disable multipathd (~27MB)
#   4. unattended-upgrades: security ON, automatic reboot OFF
#   5. docker daemon log rotation (json-file 20m x3 — protects the disk)
#   6. UTC timezone
# Idempotent: safe to re-run. Requires sudo.
# Usage: sudo bash provision-host.sh
# ============================================================================
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

echo "[1/6] Disk swapfile (3G, fallback prio -2)..."
if ! swapon --show=NAME | grep -q "^/swapfile$"; then
    fallocate -l 3G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q "^/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi
sysctl -q -w vm.swappiness=10
echo "vm.swappiness=10" > /etc/sysctl.d/99-swap.conf

echo "[2/6] zram swap (768M zstd, prio 100)..."
if ! swapon --show=NAME | grep -q zram; then
    modprobe zram 2>/dev/null || {
        apt-get install -y -qq "linux-modules-extra-$(uname -r)" >/dev/null
        modprobe zram
    }
    echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || \
        echo lz4 > /sys/block/zram0/comp_algorithm
    echo 768M > /sys/block/zram0/disksize
    mkswap /dev/zram0 >/dev/null
    swapon -p 100 /dev/zram0
fi
echo zram > /etc/modules-load.d/zram.conf
cat > /etc/systemd/system/zram-swap.service <<'EOF'
[Unit]
Description=zram swap (zstd, prio 100)
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c "echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || echo lz4 > /sys/block/zram0/comp_algorithm; echo 768M > /sys/block/zram0/disksize; mkswap /dev/zram0; swapon -p 100 /dev/zram0"
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable zram-swap >/dev/null 2>&1

echo "[3/6] Purging unused daemons (snapd/lxd/multipathd)..."
if command -v snap >/dev/null 2>&1; then
    snap list 2>/dev/null | awk 'NR>1 && $1!="snapd" && $1!~"^core" {print $1}' | xargs -r -n1 snap remove --purge 2>/dev/null || true
    snap list 2>/dev/null | awk 'NR>1 && $1~"^core" {print $1}' | xargs -r -n1 snap remove --purge 2>/dev/null || true
    systemctl disable --now snapd snapd.socket snapd.seeded 2>/dev/null || true
    apt-get purge -y -qq snapd >/dev/null 2>&1 || true
fi
systemctl disable --now multipathd multipathd.socket 2>/dev/null || true

echo "[4/6] Unattended-upgrades: no automatic reboot..."
if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
    sed -i 's|^//\s*Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "false";|' \
        /etc/apt/apt.conf.d/50unattended-upgrades || true
fi

echo "[5/6] Docker log rotation (protects the disk over months)..."
if command -v docker >/dev/null 2>&1; then
    mkdir -p /etc/docker
    if [ ! -f /etc/docker/daemon.json ] || ! grep -q max-size /etc/docker/daemon.json; then
        cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "3" }
}
EOF
        echo "  daemon.json written — restart docker when convenient"
        echo "  (running containers keep old settings until recreated)"
    fi
fi

echo "[6/6] UTC timezone..."
timedatectl set-timezone Etc/UTC 2>/dev/null || true

echo "=== DONE ==="
swapon --show
free -h | grep -E "Mem|Swap"
