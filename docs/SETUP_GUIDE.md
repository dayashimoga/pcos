# PCOS Setup & Usage Guide

> **Personal Cloud Operating System** — Your self-hosted cloud storage, file sync, and media platform.

---

## Table of Contents

1. [Quick Start (5 Minutes)](#quick-start)
2. [Server Setup](#server-setup)
3. [Desktop/Laptop Setup](#desktop-setup)
4. [Upload & Download Files](#upload-download)
5. [Features Guide](#features-guide)
6. [Mobile Access](#mobile-access)
7. [Administration](#administration)
8. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- **Docker** and **Docker Compose** installed ([Get Docker](https://docs.docker.com/get-docker/))
- A server, desktop, or laptop (any OS — Linux, Windows, macOS)
- At least 2 GB RAM, 10 GB disk space

### 3-Command Setup

```bash
# 1. Clone the repository
git clone https://github.com/dayashimoga/pcos.git
cd pcos

# 2. Configure environment
cp .env.example .env
# Edit .env to set your passwords and domain:
#   POSTGRES_PASSWORD=your_secure_password
#   JWT_SECRET=your_random_32_char_secret
#   PCOS_DOMAIN=cloud.yourdomain.com (or localhost for local)

# 3. Start everything
docker compose up -d
```

**That's it!** Open `http://localhost:3000` in your browser.

---

## Server Setup

### Option A: Cloud VPS (DigitalOcean, Hetzner, AWS, etc.)

```bash
# SSH into your server
ssh root@your-server-ip

# Install Docker (Ubuntu/Debian)
curl -fsSL https://get.docker.com | sh

# Clone and start PCOS
git clone https://github.com/dayashimoga/pcos.git
cd pcos
cp .env.example .env

# Edit .env with your domain and strong passwords
nano .env
```

**Key `.env` settings for production:**

```env
# Database
POSTGRES_USER=pcos
POSTGRES_PASSWORD=CHANGE_THIS_STRONG_PASSWORD
POSTGRES_DB=pcos

# Auth
PCOS_AUTH__JWT_SECRET=CHANGE_THIS_RANDOM_32_CHAR_STRING

# Storage
PCOS_STORAGE__BASE_PATH=/data/pcos/storage
PCOS_STORAGE__MAX_UPLOAD_SIZE_MB=10240

# Domain (for Caddy auto-HTTPS)
PCOS_DOMAIN=cloud.yourdomain.com
```

```bash
# Start the full stack (14 services)
docker compose up -d

# Check all services are healthy
docker compose ps

# View logs
docker compose logs -f backend
```

### Option B: Home Server / Local Desktop

```bash
# Same as above, but use localhost
git clone https://github.com/dayashimoga/pcos.git
cd pcos
cp .env.example .env
docker compose up -d
```

Access at: `http://localhost:3000`

### Option C: Kubernetes

```bash
# Using Helm chart
helm install pcos ./k8s/helm/pcos -f custom-values.yaml

# Or raw manifests
kubectl apply -f k8s/deployment.yaml
```

### What Gets Started (14 Services)

| Service | Purpose | Port |
|---------|---------|------|
| **Backend** (Rust/Axum) | API server (90+ endpoints) | 8080 |
| **Frontend** (Flutter Web) | Web UI | 3000 |
| **PostgreSQL 16** | Database (16 tables) | 5432 |
| **Redis 7** | Cache & sessions | 6379 |
| **NATS** | Event messaging | 4222 |
| **Caddy** | Reverse proxy + auto-HTTPS | 80/443 |
| **Prometheus** | Metrics collection | 9090 |
| **Grafana** | Monitoring dashboards | 3001 |
| Node/PG/Redis Exporters | Metrics | — |
| Backup Scheduler | Daily automated backups | — |

---

## Desktop Setup

### Web Browser (All Platforms)

Simply open your PCOS URL in any browser:
- **Local**: `http://localhost:3000`
- **Remote**: `https://cloud.yourdomain.com`

### Desktop Agent (Background Sync)

The PCOS agent runs in the background and auto-syncs folders:

```bash
# Build the agent (Docker — no Rust install needed)
docker build -f agent/Dockerfile -t pcos-agent agent/

# Run the agent
docker run -d --name pcos-agent \
  -v ~/Documents/PCOS:/data/sync \
  -e PCOS_SERVER_URL=https://cloud.yourdomain.com \
  -e PCOS_AUTH_TOKEN=your_jwt_token \
  pcos-agent
```

The agent will:
- Watch your `~/Documents/PCOS` folder for changes
- Auto-upload new/modified files
- Delta sync (only changed parts of files are uploaded)
- LAN discovery (finds other PCOS devices on your network)

### WebDAV Mount (File Manager Integration)

Mount PCOS as a network drive in your OS file manager:

**Windows:**
```
\\cloud.yourdomain.com\webdav
```
Or: Map Network Drive → `https://cloud.yourdomain.com/webdav`

**macOS (Finder):**
Finder → Go → Connect to Server → `https://cloud.yourdomain.com/webdav`

**Linux (Nautilus/Dolphin):**
```
davs://cloud.yourdomain.com/webdav
```

### S3-Compatible Access

Use any S3 client (AWS CLI, Cyberduck, rclone):

```bash
# AWS CLI
aws configure set aws_access_key_id your_jwt_token
aws configure set aws_secret_access_key unused
aws --endpoint-url https://cloud.yourdomain.com/s3 s3 ls

# rclone
rclone config
# Type: s3, Provider: Other, Endpoint: https://cloud.yourdomain.com/s3
rclone ls pcos:
```

---

## Upload & Download

### Via Web UI

1. **Login** at `http://localhost:3000` (register on first visit)
2. **Upload**: Click the **Upload** button (or drag & drop files onto the page)
3. **Download**: Click any file → **Download** button
4. **Create Folder**: Click **New Folder** button
5. **Move/Rename**: Right-click file → Rename or Move
6. **Trash**: Right-click file → Delete (moves to trash, recoverable)

### Via API (cURL)

```bash
# Set your server URL and token
SERVER="http://localhost:8080"
TOKEN="your_jwt_token"

# ── Register ──
curl -X POST $SERVER/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"YourP@ss123!","display_name":"Your Name"}'

# ── Login ──
TOKEN=$(curl -s -X POST $SERVER/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"YourP@ss123!"}' | jq -r '.token')

# ── Upload a file ──
curl -X POST $SERVER/api/v1/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@/path/to/your/document.pdf" \
  -F "parent_id="

# ── List files ──
curl $SERVER/api/v1/files \
  -H "Authorization: Bearer $TOKEN" | jq .

# ── Download a file ──
curl -O $SERVER/api/v1/files/{file_id}/download \
  -H "Authorization: Bearer $TOKEN"

# ── Create folder ──
curl -X POST $SERVER/api/v1/files/folder \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"My Documents","parent_id":null}'

# ── Search ──
curl "$SERVER/api/v1/search?q=report&limit=20" \
  -H "Authorization: Bearer $TOKEN" | jq .

# ── Share a file ──
curl -X POST $SERVER/api/v1/shares \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"file_id":"FILE_UUID","password":"optional","expires_hours":72,"max_downloads":10}'
```

---

## Features Guide

### 🔍 Search

Full-text search powered by Tantivy (Rust search engine):

```bash
# Search files by name, content, or metadata
curl "$SERVER/api/v1/search?q=quarterly+report&limit=50" \
  -H "Authorization: Bearer $TOKEN"
```

The web UI has a search bar in the navigation — type and get instant results.

### 📤 File Sharing

Create password-protected share links with expiration:

```bash
curl -X POST $SERVER/api/v1/shares \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"file_id":"UUID","password":"secret123","expires_hours":24,"max_downloads":5}'
```

Share the returned URL — recipients can download without logging in.

### 📱 Notifications

- **In-App**: Bell icon in the web UI shows unread notifications
- **Email**: Configure SMTP in `.env` for email alerts on shares, uploads
- **Web Push**: Subscribe to push notifications in Settings

### 💾 Backup & Restore

```bash
# Create a backup (database + files + manifest)
curl -X POST $SERVER/api/v1/backups \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name":"weekly-backup"}'

# List backups
curl $SERVER/api/v1/backups -H "Authorization: Bearer $TOKEN"

# Restore a backup
curl -X POST $SERVER/api/v1/backups/{backup_id}/restore \
  -H "Authorization: Bearer $TOKEN"

# Automated: backup scheduler runs daily (configured in docker-compose)
```

### 📊 Monitoring

- **Grafana**: `http://localhost:3001` (admin/admin)
  - Pre-loaded dashboards: API latency, error rates, storage usage
- **Prometheus**: `http://localhost:9090`
- **Health Check**: `http://localhost:8080/health`

### 🔐 Security

- **MFA/TOTP**: Settings → Security → Enable Two-Factor Authentication
- **RBAC**: Admin, User, Viewer roles
- **E2EE**: Client-side encryption (encrypt before upload)
- **SSO/OIDC**: Connect to Keycloak, Auth0, Okta, Google, Azure AD

### 🎬 Video/Audio Streaming

```bash
# Transcode a video to HLS adaptive (360p/720p/1080p)
curl -X POST $SERVER/api/v1/streaming/transcode \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"file_id":"VIDEO_UUID","profile":"adaptive"}'

# Check job status
curl $SERVER/api/v1/streaming/jobs -H "Authorization: Bearer $TOKEN"

# Get HLS stream URL
curl $SERVER/api/v1/streaming/stream/{job_id} -H "Authorization: Bearer $TOKEN"
# Returns: {"stream_url": "path/to/master.m3u8", "type": "application/x-mpegURL"}
```

### 🔌 Plugins

The Plugin SDK supports 8 lifecycle hooks:
- BeforeUpload, AfterUpload, BeforeDownload, AfterDelete
- OnSearch, OnShare, OnNotification, OnSchedule

### 🌐 Localization

10 supported languages: English, Spanish, French, German, Japanese, Chinese, Korean, Portuguese, Hindi, Arabic.

Set via `Accept-Language` header or user preferences.

---

## Mobile Access

### Android

```bash
# Build APK via Docker (no Android Studio needed)
bash build/build_apps.sh android
# APK output: build/artifacts/android/
```

Install the APK on your phone, enter your PCOS server URL, and login.

### iOS

Build via GitHub Actions (triggers on tag push) or Xcode on a Mac.

### Web (Any Device)

Open `https://cloud.yourdomain.com` on any phone/tablet browser.

---

## Administration

### Admin Panel

Login as admin → navigate to `/admin`:
- **User Management**: View, create, delete users
- **Role Assignment**: Set admin/user/viewer roles
- **Storage Quotas**: Set per-user storage limits
- **System Stats**: Total users, files, storage, shares, devices

```bash
# API: List all users (admin only)
curl $SERVER/api/v1/admin/users -H "Authorization: Bearer $ADMIN_TOKEN"

# API: Update user role
curl -X PUT $SERVER/api/v1/admin/users/role \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"user_id":"UUID","role":"admin"}'

# API: Set storage quota
curl -X PUT $SERVER/api/v1/admin/users/quota \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"user_id":"UUID","storage_quota_bytes":10737418240}'
```

### Maintenance Commands

```bash
# View logs
docker compose logs -f backend

# Database backup
docker compose exec postgres pg_dump -U pcos pcos > backup.sql

# Restart a service
docker compose restart backend

# Update to latest version
git pull
docker compose up -d --build

# Check disk usage
docker system df
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Can't connect** | Check `docker compose ps` — all services should be "healthy" |
| **Login fails** | Verify `JWT_SECRET` in `.env` matches what was set during registration |
| **Upload fails** | Check `PCOS_STORAGE__MAX_UPLOAD_SIZE_MB` in `.env` (default: 100MB) |
| **Slow search** | Search index builds in background — wait a few minutes after first upload |
| **WebDAV mount fails** | Ensure Caddy is running and proxying `/webdav` route |
| **No HTTPS** | Set `PCOS_DOMAIN` in `.env` — Caddy auto-provisions Let's Encrypt certs |
| **Out of disk space** | Run `docker system prune -a` or increase disk, check backup retention |
| **Service won't start** | Check logs: `docker compose logs <service_name>` |

### Get Help

```bash
# Full system status
docker compose ps
curl http://localhost:8080/health | jq .

# API documentation
# See: docs/API_REFERENCE.md (90+ endpoints documented)
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Caddy (Reverse Proxy)                 │
│                 Auto-HTTPS (Let's Encrypt)               │
├─────────────┬──────────────┬──────────────┬─────────────┤
│  /api/*     │  /webdav/*   │  /s3/*       │  /*         │
│  Backend    │  WebDAV      │  S3 Gateway  │  Frontend   │
│  (Axum)     │  Server      │              │  (Flutter)  │
├─────────────┴──────────────┴──────────────┴─────────────┤
│                      Backend (Rust/Axum)                  │
│  Auth │ Files │ Search │ Sync │ Backup │ Notifications   │
│  AI   │ Admin │ Sharing │ Streaming │ Plugins │ i18n     │
├──────────────┬──────────────┬───────────────────────────┤
│ PostgreSQL   │    Redis     │        NATS               │
│ (16 tables)  │  (cache)     │   (event bus)             │
├──────────────┴──────────────┴───────────────────────────┤
│              File Storage (local disk/NAS)               │
└─────────────────────────────────────────────────────────┘
```
