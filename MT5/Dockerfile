# syntax=docker/dockerfile:1
#
# Standalone MetaTrader 5 Terminal with noVNC
# Access MT5 via browser at http://localhost:6080
#
# Ports:
#   6080   — noVNC web interface (browser access)
#   5900   — VNC (optional, for native VNC clients)
#

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

ENV WINEPREFIX=/config/.wine \
    WINEDEBUG=-all \
    DISPLAY=:99 \
    DEBIAN_FRONTEND=noninteractive \
    TITLE=MT5-Terminal

WORKDIR /opt/mt5

# ============================================================================
# Install Wine + Xvfb + VNC + noVNC + window manager
# ============================================================================
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg2 \
        wget \
        xvfb \
        x11vnc \
        x11-utils \
        xdotool \
        fluxbox \
        xauth \
        xkb-data \
        netcat-openbsd \
        procps \
        unzip \
        novnc \
        websockify \
        python3-numpy \
    && rm -rf /var/lib/apt/lists/*

# Add WineHQ repository (Debian bookworm) — provides wine 9.x+
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key && \
    wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN rm -f /etc/apt/keyrings/winehq-archive.key

# ============================================================================
# MT5 binaries (user-provided)
# ============================================================================
COPY mt5-bin/ /opt/mt5/mt5/

# ============================================================================
# Startup script
# ============================================================================
COPY start.sh /opt/mt5/start.sh
RUN chmod +x /opt/mt5/start.sh

# ============================================================================
# Volumes and ports
# ============================================================================
VOLUME /config
# 6080 = noVNC web interface, 5900 = VNC (optional)
EXPOSE 6080 5900

CMD ["/opt/mt5/start.sh"]
