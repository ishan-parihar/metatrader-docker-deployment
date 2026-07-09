# syntax=docker/dockerfile:1
#
# Standalone MetaTrader 4 Terminal with noVNC
# Access MT4 via browser at http://localhost:6080
#
# For systems without AVX2 (uses 32-bit terminal.exe)
# Uses Wine 9.0 (bookworm-backports) to avoid Themida detection issues
#

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

ENV WINEPREFIX=/config/.wine \
    WINEDEBUG=-all \
    DISPLAY=:99 \
    DEBIAN_FRONTEND=noninteractive \
    TITLE=MT4-Terminal

WORKDIR /opt/mt4

# ============================================================================
# Install Wine 9.0 from Debian bookworm-backports (avoids Themida issues)
# + Xvfb + VNC + noVNC + window manager
# ============================================================================
RUN dpkg --add-architecture i386 && \
    # Enable bookworm-backports
    echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/backports.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        -t bookworm-backports \
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
        netcat-openbsd \
        procps \
        unzip \
        novnc \
        websockify \
        python3-numpy \
    && rm -rf /var/lib/apt/lists/*

# Install Wine 9.0 from bookworm-backports (not Wine 11.0 from WineHQ)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        -t bookworm-backports \
        wine \
        wine32 \
        wine64 \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ============================================================================
# MT4 binaries (user-provided in mt4-bin/)
# ============================================================================
COPY mt4-bin/ /opt/mt4/mt4/

# ============================================================================
# Startup script
# ============================================================================
COPY start.sh /opt/mt4/start.sh
RUN chmod +x /opt/mt4/start.sh

# ============================================================================
# Volumes and ports
# ============================================================================
VOLUME /config
EXPOSE 6080 5900

CMD ["/opt/mt4/start.sh"]
