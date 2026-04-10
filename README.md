<p align="center">
  <img src="https://raw.githubusercontent.com/WyldMagic-Workshop/audiodeck-install/main/logo.svg" alt="AudioDeck" width="96" height="96" />
</p>

<h1 align="center">AudioDeck Installer</h1>

<p align="center">
  One-command setup for <a href="https://hub.docker.com/r/wyldmagic/audiodeck">AudioDeck</a> — the cross-platform network audio routing tool.
</p>

---

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/WyldMagic-Workshop/audiodeck-install/main/docker-setup.sh | bash
```

Creates `~/audiodeck/`, generates `config.yaml` and `docker-compose.yml`, pulls the image, and starts the container. Open **http://localhost:8400** when it finishes.

> **Heads-up**: Docker Desktop on macOS and Windows cannot pass audio hardware into its Linux VM. The container still runs — you get the routing UI, peer discovery, and network subscriptions — but no local capture/playback devices will be visible. For real audio I/O on macOS or Windows, use the [native installer](https://github.com/WyldMagic-Workshop/audiodeck) instead.

---

## What It Does

The setup script:

1. Checks that Docker and Docker Compose are installed and running
2. Creates `~/audiodeck/` with directories for recordings and logs
3. Generates `config.yaml` with sensible defaults
4. Generates a platform-specific `docker-compose.yml`:
   - **Linux**: includes `/dev/snd` passthrough + `audio` group membership for ALSA
   - **macOS/Windows**: omits the audio device block (Docker Desktop can't forward audio)
5. Pulls the AudioDeck image from Docker Hub
6. Starts the container
7. Prints your LAN-accessible URL

## After Install

Open **http://localhost:8400** in your browser.

From other devices on your network: `http://<your-ip>:8400`

Other AudioDeck instances on the same LAN are discovered automatically via mDNS.

### Directory Structure

```
~/audiodeck/
  config.yaml         ← audio, network, and path settings
  docker-compose.yml
  recordings/         ← WAV files recorded from the mix
  logs/               ← rotating application logs
```

### Changing recording / log paths

AudioDeck's **Settings → Paths** tab lets you edit where recordings, logs, and the database live. Recording and log paths take effect immediately (no restart); the database path requires a restart.

**Inside Docker**, the path you pick must resolve to one of the container's bind-mounted volumes — the process can't write outside them. The generated compose mounts:

| Host path                        | Container path      |
|----------------------------------|---------------------|
| `~/audiodeck/recordings`         | `/app/recordings`   |
| `~/audiodeck/logs`               | `/app/logs`         |

To record into a new host directory, add another volume to `~/audiodeck/docker-compose.yml` (e.g. `- /srv/stream/backup:/app/backup`), restart the stack with `docker compose up -d`, then set **Settings → Paths → Recordings directory** to `/app/backup`.

### Ports

| Port   | Protocol | Purpose                               |
|--------|----------|---------------------------------------|
| 8400   | TCP      | HTTP API + Svelte UI                  |
| 8401   | UDP      | Opus audio transport between peers    |
| 8402   | TCP      | Peer signaling (HELLO/TRACKS/PING)    |
| 5353   | UDP      | mDNS peer discovery (standard port)   |

---

## Prerequisites

- **Docker** — [Install Docker](https://docs.docker.com/get-docker/)
- **Docker Compose** — included with Docker Desktop, or install the plugin on Linux

### Platform Support

| Platform       | UI + networking | Local audio I/O |
|----------------|-----------------|-----------------|
| Linux          | Yes             | Yes (ALSA passthrough) |
| macOS          | Yes             | **No** — use the [native installer](https://github.com/WyldMagic-Workshop/audiodeck) |
| Windows + WSL2 | Yes             | **No** — use the [native installer](https://github.com/WyldMagic-Workshop/audiodeck) |

> If you only need AudioDeck as a network *subscriber* (receiving a stream from another machine and monitoring on the host's speakers outside the container), the native installer is still the better choice on Mac/Windows.

---

## Manual Setup

If you prefer not to pipe scripts from the internet:

```bash
# 1. Clone this repo
git clone https://github.com/WyldMagic-Workshop/audiodeck-install.git
cd audiodeck-install

# 2. Run the script locally
bash docker-setup.sh
```

---

## Managing AudioDeck

```bash
cd ~/audiodeck

# View logs
docker compose logs -f

# Restart
docker compose restart

# Stop
docker compose down

# Manual update (if you disabled auto-updates)
docker compose pull && docker compose up -d
```

---

## Auto-Updates

AudioDeck's compose file includes [Watchtower](https://github.com/containrrr/watchtower), which checks Docker Hub hourly for new images and redeploys automatically. Your config, database, recordings, and logs are unaffected by updates.

To disable, remove or comment out the `watchtower` service in `~/audiodeck/docker-compose.yml` and `docker compose up -d` again.

---

## Troubleshooting

### Container won't start
```bash
docker compose logs
```

### No audio devices visible (Linux)
The container's audiodeck user needs to be in the `audio` group to access `/dev/snd`. The generated compose file does this via `group_add: [audio]`. If you're still stuck:

```bash
# Verify your host has an audio group
getent group audio
# Verify /dev/snd exists and is readable
ls -la /dev/snd
```

### Peer discovery not working
mDNS requires `network_mode: host` (which the generated compose uses) AND a host network that supports multicast. Check your firewall isn't blocking UDP 5353:

```bash
# Linux (ufw)
sudo ufw allow 5353/udp
sudo ufw allow 8401/udp
sudo ufw allow 8400/tcp
sudo ufw allow 8402/tcp
```

### Permission denied on recordings
```bash
sudo chown -R 1000:1000 ~/audiodeck/recordings ~/audiodeck/logs
```
(The container runs as UID 1000 by default.)

### Changing the port
Edit `~/audiodeck/config.yaml`'s `server.port` and restart:
```bash
cd ~/audiodeck && docker compose restart
```

---

## Links

- [AudioDeck on Docker Hub](https://hub.docker.com/r/wyldmagic/audiodeck)
- [AudioDeck main repo](https://github.com/WyldMagic-Workshop/audiodeck)
- [Support on Ko-fi](https://ko-fi.com/deadcodedad)

---

*Built by [DeadCodeDad](https://twitch.tv/DeadCodeDad)*
