# PCOS Setup & Deployment Guide

## 1. Quick Start (One Command)

### Windows (PowerShell)
```powershell
# Default Core Lite profile (Postgres + Redis + Backend + Frontend + Caddy)
.\spinup.ps1

# With Media Transcoding (FFmpeg)
.\spinup.ps1 -Profile media

# With Local AI (Ollama)
.\spinup.ps1 -Profile ai

# Full Telemetry Stack (NATS JetStream + Prometheus + Grafana)
.\spinup.ps1 -Profile full
```

### Linux / macOS (Bash)
```bash
# Default Core Lite profile
./spinup.sh

# With Media Transcoding
./spinup.sh --profile media

# With Local AI
./spinup.sh --profile ai

# Full Telemetry Stack
./spinup.sh --profile full
```

---

## 2. Container Runtime Support: Docker & Podman

PCOS automatically detects whether your system is running **Docker** or **Podman**:
- **Docker**: Uses `docker compose` or `docker-compose`.
- **Podman**: Uses `podman compose` or `podman-compose`. Rootless port binding for standard web ports (80/443) is automatically configured via `sysctl net.ipv4.ip_unprivileged_port_start=80`.

---

## 3. Deployment Profiles

| Profile | Included Services | Idle RAM | Ideal For |
|---|---|---|---|
| **`lite`** *(default)* | PostgreSQL, Redis, Axum Backend, Flutter Web, Caddy | ~250MB | Raspberry Pi, low-spec VPS, NAS, personal desktop |
| **`media`** | `lite` + FFmpeg Transcoding Worker | ~350MB | Media servers, streaming large non-native video files |
| **`ai`** | `media` + Ollama Local LLM Engine | ~2.5GB | On-premise semantic search, OCR summarization |
| **`full`** | `ai` + NATS JetStream + Prometheus + Grafana + Exporters | ~3.0GB | Enterprise homelabs, deep metrics monitoring |

---

## 4. Initial Onboarding Flow

1. Open your browser to `http://localhost/` or your server's LAN IP (`http://192.168.x.x/`).
2. Run through the **PCOS Setup Wizard** (`/#/setup`):
   - Admin account creation (email + strong passphrase)
   - Master recovery key generation (24-word BIP39 mnemonic)
   - Storage location selection
3. **PCOS Doctor Diagnostics** (`/#/doctor`):
   - Verifies Database, File Storage, Auth, Tantivy Search, and PCOS Connect Network Reachability (LAN IP, CGNAT assessment, TLS).
4. **Device Pairing** (`/#/devices`):
   - Scan the one-time, 5-minute rate-limited QR code from your phone or tablet to pair and sync instantly without manually typing IPs or tokens.

---

## 5. Maintenance Commands

- **Check Service Status**:
  ```bash
  docker compose ps    # or: podman compose ps
  ```
- **Inspect Live Logs**:
  ```bash
  docker compose logs -f backend    # or: podman compose logs -f backend
  ```
- **Bring Down Stack**:
  ```powershell
  .\bringdown.ps1      # Linux: ./bringdown.sh
  ```
- **Perform Instant Encrypted Backup**:
  ```bash
  docker compose exec postgres pg_dump -U pcos pcos > backup.sql
  ```
