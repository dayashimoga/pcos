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
| WebDAV (PROPFIND, MKCOL, DELETE, MOVE) | ✅ | ✅ |
| S3-compatible API (ListBuckets, ListObjects, HeadObject, DeleteObject) | ✅ | ✅ |
| SMB/CIFS bridge | 🔌 | 🔌 |

## Sync & Sharing

| Feature | Backend | Agent | Status |
|---------|---------|-------|--------|
| WebSocket sync (JWT auth, change tracking) | ✅ | ✅ | ✅ |
| Delta sync (content-defined chunking) | — | ✅ | ✅ |
| LAN/P2P discovery (UDP broadcast) | — | ✅ | ✅ |
| Share links (password, expiry, download limits) | ✅ | — | ✅ |
| File versioning (list, restore, download) | ✅ | — | ✅ |

## Streaming

| Feature | Backend | Status |
|---------|---------|--------|
| HLS adaptive bitrate (360p/720p/1080p) | ✅ | ✅ |
| Audio extraction (HLS + MP3) | ✅ | ✅ |
| Thumbnail + sprite generation | ✅ | ✅ |
| Media probing (ffprobe) | ✅ | ✅ |

## Backup & Recovery

| Feature | Backend | Status |
|---------|---------|--------|
| Backup with file copy + manifest | ✅ | ✅ |
| Backup restore with file restore | ✅ | ✅ |
| Backup retention policy | ✅ | ✅ |
| Backup verification (integrity check) | ✅ | ✅ |
| Scheduled pg_dump container | ✅ | ✅ |

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
