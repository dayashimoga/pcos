# PCOS TODO & Feature History

## Completed ✅

### v0.1.0 — Core Platform
- [x] Auth: register, login, refresh (token rotation), logout with Argon2id + JWT
- [x] Users: profile CRUD with password change
- [x] Devices: registration, listing, heartbeat, deletion
- [x] File Management: upload (single + chunked), download, folder CRUD, trash/restore, storage stats
- [x] File preview endpoints (inline content-disposition + content-type)
- [x] Search: database-backed search with ILIKE, suggestions, reindex endpoint
- [x] AI: Ollama integration for auto-tagging, classification, duplicate detection, smart search
- [x] Sharing: share links with password protection, expiration, download limits
- [x] Sync Engine: WebSocket with JWT auth, change tracking, conflict resolution, sync folders
- [x] Notifications: create, list, mark read, unread count
- [x] Jobs: background job queue with status tracking
- [x] Backups: metadata-based backup/restore with schedules
- [x] Analytics: dashboard stats, storage breakdown, activity, file types
- [x] Prometheus metrics endpoint
- [x] Flutter Web frontend: dashboard, files, search, devices, trash, settings
- [x] Rust device agent: file watcher, heartbeat, auto-upload
- [x] Docker Compose deployment with Caddy reverse proxy
- [x] GitHub Actions CI/CD pipeline
- [x] 15 unit tests + 9 BLoC tests

### v0.2.0 — Enterprise Security
- [x] HTTP Range Downloads: `206 Partial Content`, `Content-Range`, `Accept-Ranges`, ETag
- [x] Per-user storage quota enforcement: `storage_quota_bytes` column, admin quota management
- [x] TOTP-based 2FA: setup, verify, disable, status (Pure-Rust HMAC-SHA1, ±1 step tolerance)
- [x] File versioning: `file_versions` table, list/restore/download version APIs
- [x] RBAC: admin/user/viewer roles, `require_admin` guard, self-demotion prevention
- [x] Admin Portal: list users, update roles, update quotas, system statistics
- [x] Admin Portal UI: Flutter page with system stats cards, user management, role editing
- [x] MFA Settings UI: Flutter page with setup flow, status card, enable/disable
- [x] 12 integration tests (auth/files/devices/notifications/search/storage)
- [x] Operations runbook (`docs/OPERATIONS.md`)
- [x] Search reindex handler: replaced stub with real DB-based reindex
- [x] Dockerfile: all 14 crate manifests copied (was 5)

### v0.3.0 — Search, Backup, Observability, Docs
- [x] Tantivy search index wired into AppState: search handler tries Tantivy first, DB ILIKE fallback
- [x] Reindex endpoint: actually indexes all user files into Tantivy when available
- [x] Real backup with file copy: copies all user files + manifest.json + pg_dump, restore copies back
- [x] Backup delete cleans up files from disk
- [x] Email notifications (SMTP): async TCP sender with AUTH PLAIN, MIME multipart
- [x] Email templates: welcome, backup complete, share notification, MFA enabled
- [x] Grafana dashboard template: 12 panels (HTTP, storage, errors, DB pool, WS, jobs, AI)
- [x] User guide (`docs/USER_GUIDE.md`): comprehensive with curl examples for all features
- [x] Architecture Decision Records (`docs/ADR.md`): 8 ADRs

### v0.4.0 — Compatibility & Sync
- [x] WebDAV compatibility layer: PROPFIND (XML directory listing), MKCOL, DELETE, MOVE, OPTIONS
- [x] WebDAV DAV 1,2 compliance headers (macOS Finder, Windows Explorer, Nautilus compatible)
- [x] WebDAV routes wired in Caddy reverse proxy
- [x] Delta sync module in agent: content-defined chunking with rolling hash
- [x] SHA-256 per-chunk hashing for dedup and change detection
- [x] Chunk diff algorithm: only changed chunks marked for upload
- [x] 3 delta sync unit tests (deterministic, diff detection, no-change)
- [x] API reference updated to 75+ endpoints

---

## Remaining (Priority Order)

### High Priority
- [ ] Populate SQLx offline query cache (`.sqlx/`) for Docker builds (requires running PostgreSQL)

### Medium Priority
- [ ] Add LAN/P2P discovery for local sync
- [ ] Add OCR text extraction for images/PDFs
- [ ] Add web push notifications (Service Worker + Push API)

### Low Priority / Future
- [ ] Native Flutter apps (Android, iOS, Windows, Linux, macOS)
- [ ] End-to-end encryption (E2EE) with key management
- [ ] SSO/OIDC/SAML integration
- [ ] LDAP/Active Directory support
- [ ] S3-compatible gateway
- [ ] SMB/NFS bridge
- [ ] Plugin system with public SDK
- [ ] Face clustering in photos
- [ ] Video/audio streaming engine
- [ ] Localization (i18n)
- [ ] Accessibility (a11y) audit

### Technical Debt
- [ ] Increase test coverage to 90%+ (currently 39 tests)
- [ ] Add load/stress testing with k6 or similar
