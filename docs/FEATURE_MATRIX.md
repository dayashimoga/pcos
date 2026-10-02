# PCOS Feature Matrix

## Legend
- ✅ **Implemented** — Code exists, compiles, integrated, has tests or CI validation
- ⚙️ **Library Only** — Code implemented but no HTTP routes / UI wired
- 🔌 **Optional/External** — Requires external dependency not bundled (ldap3, Samba)
- ❌ **Not Implemented** — Feature does not exist

---

## Core Platform

| Feature | Backend | Frontend | Agent | Status |
|---------|---------|----------|-------|--------|
| User registration & login | ✅ | ✅ | — | ✅ |
| JWT token rotation (access + refresh) | ✅ | ✅ | — | ✅ |
| Password hashing (Argon2id) | ✅ | — | — | ✅ |
| User profile CRUD | ✅ | ✅ | — | ✅ |
| Device registration & heartbeat | ✅ | ✅ | ✅ | ✅ |
| File upload (single + chunked) | ✅ | ✅ | ✅ | ✅ |
| File download (+ HTTP Range) | ✅ | ✅ | — | ✅ |
| Folder CRUD | ✅ | ✅ | — | ✅ |
| Trash / restore | ✅ | ✅ | — | ✅ |
| Storage stats & analytics | ✅ | ✅ | — | ✅ |
| File preview endpoints | ✅ | — | — | ✅ |
| Notifications (create, list, mark read) | ✅ | ✅ | — | ✅ |
| Background job queue | ✅ | — | — | ✅ |

## Security

| Feature | Backend | Frontend | Status |
|---------|---------|----------|--------|
| TOTP 2FA (setup, verify, disable) | ✅ | ✅ | ✅ |
| RBAC (admin/user/viewer) | ✅ | ✅ | ✅ |
| Per-user storage quotas | ✅ | ✅ | ✅ |
| E2EE (AES-256-GCM key derivation) | ✅ | — | ⚙️ |
| OIDC/SSO (discovery, code exchange) | ✅ | — | ⚙️ |
| LDAP/AD authentication | 🔌 | — | 🔌 |

## Search & AI

| Feature | Backend | Status |
|---------|---------|--------|
| Database ILIKE search | ✅ | ✅ |
| Tantivy full-text search | ✅ | ✅ |
| Reindex endpoint | ✅ | ✅ |
| AI auto-tagging (Ollama) | ✅ | ✅ |
| OCR text extraction (Tesseract) | ✅ | ✅ |
| EXIF/metadata extraction | ✅ | ✅ |

## File Protocols

| Feature | Backend | Status |
|---------|---------|--------|
| WebDAV RFC 4918 (PROPFIND, MKCOL, GET Range, HEAD, PUT SHA-256, DELETE, MOVE, COPY, OPTIONS) | ✅ | ✅ |
| S3 Gateway (ListBuckets, ListObjectsV2, GetObject Range, PutObject SHA-256, HeadObject, DeleteObject) | ✅ | ✅ |
| SMB/CIFS bridge | 🔌 | 🔌 |

## Sync & Sharing

| Feature | Backend | Agent | Status |
|---------|---------|-------|--------|
| WebSocket sync (Bearer / subprotocol auth, change tracking) | ✅ | ✅ | ✅ |
| Delta sync (content-defined chunking + chunked upload) | ✅ | ✅ | ✅ |
| LAN/P2P peer discovery (UDP broadcast port 38472) | — | ✅ | ✅ |
| Share links (password, expiry, download limits) | ✅ | — | ✅ |
| File versioning (list, restore, download) | ✅ | — | ✅ |

## Streaming

| Feature | Backend | Status |
|---------|---------|--------|
| Scoped revocable playback tokens (2h, user/file/device-scoped) | ✅ | ✅ |
| Direct Play (HTTP 206 Partial Content Range streaming) | ✅ | ✅ |
| ffprobe probing (codecs, bitrate, dimensions, audio tracks) | ✅ | ✅ |
| HLS adaptive bitrate (360p/720p/1080p) & hardware acceleration | ✅ | ✅ |
| Audio extraction & thumbnails | ✅ | ✅ |

## Backup & Disaster Recovery

| Feature | Backend | Status |
|---------|---------|--------|
| Full DR Backup (raw payloads, versions, manifest.json, metadata) | ✅ | ✅ |
| Full DR Restore (payload copy, relational DB hierarchy, verify) | ✅ | ✅ |
| Cryptographic Verification (SHA-256 integrity check of all files) | ✅ | ✅ |
| Automated Retention Policies & Schedules | ✅ | ✅ |
| Standalone verification test suite (100% passing) | ✅ | ✅ |

## Frontend & Transfers

| Feature | Frontend | Status |
|---------|----------|--------|
| Unified Transfer Center (queue, progress, speed, ETA) | ✅ | ✅ |
| Transfer lifecycle (pause, resume, retry, cancel, clear) | ✅ | ✅ |
| Bandwidth throttling / rate limiting | ✅ | ✅ |
| Live status indicator & pulse badge in Shell layout | ✅ | ✅ |
| Global Command Palette (Ctrl+K) & Transfers shortcut (Ctrl+T) | ✅ | ✅ |


## Email & Notifications

| Feature | Backend | Status |
|---------|---------|--------|
| SMTP email (async TCP sender) | ✅ | ✅ |
| Web Push (RFC 8030) | ✅ | ✅ |
| Email templates (4 types) | ✅ | ✅ |

## Deployment

| Feature | Status |
|---------|--------|
| Docker Compose (13 services) | ✅ |
| Kubernetes manifests | ✅ |
| Helm chart | ✅ |
| Caddy reverse proxy | ✅ |
| Prometheus + Grafana monitoring | ✅ |
| CI/CD (GitHub Actions) | ✅ |
| Native apps (6 platforms) | ✅ |

## Frontend (Flutter)

| Feature | Status |
|---------|--------|
| Dashboard with live stats | ✅ |
| Files (grid/list, breadcrumb, upload, rename, delete) | ✅ |
| Search | ✅ |
| Devices | ✅ |
| Trash | ✅ |
| Admin portal (users, roles, quotas) | ✅ |
| Settings (profile, MFA, logout) | ✅ |
| Responsive layout (desktop/tablet/mobile) | ✅ |
| Collapsible sidebar + keyboard shortcuts | ✅ |
| Skeleton loading + error retry | ✅ |
| Service worker (offline + push) | ✅ |

## Plugin System

| Feature | Backend | Status |
|---------|---------|--------|
| Plugin manifest + registry | ✅ | ✅ |
| 8 lifecycle hooks | ✅ | ✅ |
| i18n (10 locales, 16 keys) | ✅ | ✅ |

## Distributed Edge & Hybrid Cloud

| Feature | Cloudflare Edge | Node Agent | Flutter Client | Status |
|---|---|---|---|---|
| Cloudflare Workers Control API | ✅ | — | ✅ | ✅ |
| Cloudflare Pages Static Web hosting | ✅ | — | ✅ | ✅ |
| Durable Object DevicePresenceHub | ✅ | ✅ | ✅ | ✅ |
| Durable Object PairingHub | ✅ | ✅ | ✅ | ✅ |
| D1 Distributed Relational Control Store | ✅ | — | — | ✅ |
| Authoritative QR / 6-digit Code Pairing | ✅ | ✅ | ✅ | ✅ |
| Real Camera QR scanning with permissions | — | — | ✅ | ✅ |
| Candidate Device Approval on Dashboard | ✅ | — | ✅ | ✅ |
| Single-Use Enrollment Tokens & Lockout | ✅ | ✅ | ✅ | ✅ |
| Dynamic Route Resolution (LAN / P2P / Relay) | ✅ | ✅ | ✅ | ✅ |
| Outbound-Only Node Agent (`pcos-agent`) | — | ✅ | — | ✅ |
| PCOS Node Doctor Diagnostics CLI | — | ✅ | — | ✅ |
| Free-Tier Guard ($0 Hard Budget Mode) | ✅ | — | ✅ | ✅ |
| File Availability Tiers | ✅ | ✅ | ✅ | ✅ |
| Encrypted Cloud Cache Replication (R2) | ✅ | ✅ | ✅ | ✅ |
| Play-on-TV & Send-to-Device Remote Control | ✅ | ✅ | ✅ | ✅ |

