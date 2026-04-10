#!/bin/bash
# AudioDeck Docker Setup
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/wyldmagic/audiodeck/main/docker-setup.sh | bash
set -e

AUDIODECK_DIR="$HOME/audiodeck"
IMAGE="wyldmagic/audiodeck:latest"

echo ""
echo "=================================="
echo "  AudioDeck Docker Setup"
echo "=================================="
echo ""

# ── Detect platform ──────────────────────────────────────────────────────────

OS="$(uname -s)"
case "$OS" in
    Linux*)                 PLATFORM="linux";;
    Darwin*)                PLATFORM="macos";;
    MINGW*|MSYS*|CYGWIN*)   PLATFORM="windows";;
    *)                      PLATFORM="unknown";;
esac
echo "Platform: $PLATFORM"

# ── Check Docker ─────────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
    echo "Error: Docker is not installed."
    echo ""
    echo "Install Docker:"
    echo "  Linux:   curl -fsSL https://get.docker.com | sh"
    echo "  macOS:   https://docs.docker.com/desktop/install/mac-install/"
    echo "  Windows: https://docs.docker.com/desktop/install/windows-install/"
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo "Error: Docker is not running."
    echo "  Start Docker Desktop, or run: sudo systemctl start docker"
    exit 1
fi

echo "Docker: $(docker --version | head -1)"

# Check for Docker Compose (v2 plugin or standalone)
if docker compose version &>/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
else
    echo "Error: Docker Compose not found."
    echo "  Install: https://docs.docker.com/compose/install/"
    exit 1
fi
echo "Compose: $($COMPOSE version 2>/dev/null | head -1)"
echo ""

# ── Platform-specific audio capability notice ────────────────────────────────

if [ "$PLATFORM" != "linux" ]; then
    echo "⚠  Heads-up: on $PLATFORM, Docker Desktop cannot pass audio"
    echo "   hardware into the Linux container. AudioDeck will still"
    echo "   start — you'll get the routing UI, peer discovery, and"
    echo "   network subscriptions — but no local capture or playback"
    echo "   devices will be visible inside the container. For real"
    echo "   audio I/O on $PLATFORM, use the native venv install:"
    echo "     curl -fsSL https://raw.githubusercontent.com/wyldmagic/audiodeck/main/install.sh | bash"
    echo ""
fi

# ── Create directory structure ───────────────────────────────────────────────

echo "Setting up $AUDIODECK_DIR..."
mkdir -p "$AUDIODECK_DIR/recordings"
mkdir -p "$AUDIODECK_DIR/logs"

# Match the container's pinned UID 1000 so bind mounts are writable
# from inside the container without chown gymnastics. Best-effort:
# if the host user isn't UID 1000 and has sudo, we chown the new
# dirs to 1000. On macOS/Windows Docker Desktop this isn't needed
# because the VFS layer handles it automatically.
if [ "$PLATFORM" = "linux" ] && [ "$(id -u)" != "1000" ]; then
    if sudo -n true 2>/dev/null; then
        sudo chown -R 1000:1000 "$AUDIODECK_DIR/recordings" "$AUDIODECK_DIR/logs" 2>/dev/null || true
    fi
fi

# ── Generate config.yaml ────────────────────────────────────────────────────

if [ ! -f "$AUDIODECK_DIR/config.yaml" ]; then
    cat > "$AUDIODECK_DIR/config.yaml" << 'EOF'
server:
  host: "0.0.0.0"
  port: 8400

instance:
  name: ""

audio:
  sample_rate: 48000
  buffer_size: 256
  channels: 2
  default_quality: "standard"

network:
  udp_port: 8401
  tcp_port: 8402
  jitter_buffer_ms: 30
  keepalive_interval_seconds: 5.0
  peer_timeout_seconds: 15.0

paths:
  database: "/app/data/audiodeck.db"
  recordings: "/app/recordings"
  logs: "/app/logs"
EOF
    echo "  Created config.yaml"
else
    echo "  config.yaml already exists, keeping existing."
fi

# ── Generate docker-compose.yml ──────────────────────────────────────────────
#
# The compose file is generated per-platform so the audio device
# passthrough block is only emitted on Linux — on macOS/Windows the
# Docker Desktop Linux VM cannot access host audio hardware, and
# pinning /dev/snd there would just cause the container to fail to
# start.

if [ "$PLATFORM" = "linux" ]; then
    cat > "$AUDIODECK_DIR/docker-compose.yml" << EOF
services:
  audiodeck:
    image: $IMAGE
    network_mode: host
    volumes:
      - ./config.yaml:/app/config.yaml
      - ./recordings:/app/recordings
      - ./logs:/app/logs
      - audiodeck_data:/app/data
    # Audio hardware passthrough (Linux only). The 'audio' group
    # must contain the container's audiodeck user for ALSA writes
    # to succeed — group_add adds the host's 'audio' GID at runtime.
    devices:
      - "/dev/snd:/dev/snd"
    group_add:
      - "audio"
    restart: unless-stopped

  watchtower:
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_POLL_INTERVAL: "3600"
    restart: unless-stopped

volumes:
  audiodeck_data:
EOF
else
    cat > "$AUDIODECK_DIR/docker-compose.yml" << EOF
services:
  audiodeck:
    image: $IMAGE
    # host networking behaves differently on Docker Desktop for
    # macOS/Windows — the container still reaches the LAN via the
    # VM, but mDNS multicast discovery may not work reliably. Use
    # the native venv install for real peer discovery on this OS.
    network_mode: host
    ports:
      - "8400:8400"
      - "8401:8401/udp"
      - "8402:8402"
    volumes:
      - ./config.yaml:/app/config.yaml
      - ./recordings:/app/recordings
      - ./logs:/app/logs
      - audiodeck_data:/app/data
    restart: unless-stopped

  watchtower:
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_POLL_INTERVAL: "3600"
    restart: unless-stopped

volumes:
  audiodeck_data:
EOF
fi
echo "  Created docker-compose.yml"

# ── Pull and start ───────────────────────────────────────────────────────────

cd "$AUDIODECK_DIR"

echo ""
echo "Pulling $IMAGE..."
docker pull "$IMAGE"

echo ""
echo "Starting AudioDeck..."
$COMPOSE up -d

# ── Detect access URL ────────────────────────────────────────────────────────

if [ "$PLATFORM" = "linux" ]; then
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
elif [ "$PLATFORM" = "macos" ]; then
    IP=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost")
else
    IP="localhost"
fi

echo ""
echo "=================================="
echo "  AudioDeck is running!"
echo "=================================="
echo ""
echo "  Open in your browser:"
echo "    http://localhost:8400"
if [ "$IP" != "localhost" ] && [ -n "$IP" ]; then
    echo "    http://${IP}:8400  (from other devices)"
fi
echo ""
echo "  Network ports:"
echo "    HTTP API:       8400"
echo "    UDP Audio:      8401"
echo "    TCP Signaling:  8402"
echo "    mDNS Discovery: 5353 (standard)"
echo ""

if [ "$PLATFORM" = "linux" ]; then
    echo "  Audio hardware passthrough: enabled (/dev/snd + audio group)"
    echo ""
fi

echo "  Other AudioDeck instances on the same LAN will"
echo "  be discovered automatically via mDNS."
echo ""
echo "  Data directories:"
echo "    Recordings: $AUDIODECK_DIR/recordings"
echo "    Logs:       $AUDIODECK_DIR/logs"
echo "    Config:     $AUDIODECK_DIR/config.yaml"
echo ""
echo "  Manage AudioDeck:"
echo "    cd $AUDIODECK_DIR"
echo "    $COMPOSE logs -f        # View logs"
echo "    $COMPOSE restart        # Restart"
echo "    $COMPOSE down           # Stop"
echo "    $COMPOSE pull && $COMPOSE up -d  # Update"
echo ""
