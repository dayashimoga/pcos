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

### v0.5.0 — Containerization, S3, Monitoring, CI/CD
- [x] Production docker-compose: 13 services (PostgreSQL, Redis, NATS, Ollama, backend, frontend, Caddy, Prometheus, Grafana, node-exporter, postgres-exporter, redis-exporter, backup scheduler)
- [x] Root `.env.example` with all configurable variables for one-command deployment
- [x] Prometheus config: scrapes backend, Caddy, PostgreSQL, Redis, node metrics
- [x] Grafana provisioning: auto-loads dashboards + Prometheus datasource
- [x] Dev docker-compose override: hot reload, debug logging, exposed ports
- [x] Agent Dockerfile: multi-stage build, non-root user
- [x] S3-compatible API gateway: ListBuckets, ListObjectsV2, HeadObject, DeleteObject (XML responses)
- [x] S3 routes wired in Caddy + file_metadata router
- [x] Backup retention policy: auto-delete old backups beyond keep count
- [x] Backup verification: manifest integrity check, file existence audit
- [x] Backup scheduler container: daily pg_dump with 30-backup retention
- [x] CI pipeline expanded: agent build/test, SBOM/license scan (cargo-deny), compose validation
- [x] Release pipeline expanded: agent builds (3 platforms), aarch64 backend, multi-platform Docker (amd64+arm64), SHA256 checksums
- [x] Isolated Docker network (`pcos-net`) for all services
- [x] Ollama moved to optional profile (`--profile ai`)

### v0.6.0 — OCR, Web Push, LAN Discovery, Kubernetes
- [x] LAN/P2P discovery module in agent: UDP broadcast, peer tracking with timeout, 2 unit tests
- [x] OCR text extraction service: plaintext, PDF (BT/ET parser + Tesseract fallback), images (Tesseract OCR)
- [x] EXIF/metadata extraction (exiftool with graceful fallback)
- [x] Text extraction endpoint: `POST /api/v1/search/extract/:id` — extracts + indexes to Tantivy
- [x] Web Push notification service: subscribe, unsubscribe, list, send via Web Push protocol (RFC 8030)
- [x] Auto-cleanup expired push subscriptions (410 Gone)
- [x] Push notification endpoints: subscribe, unsubscribe, list, send
- [x] DB migration: `push_subscriptions` table + `text_extractions` table with GIN full-text index
- [x] Kubernetes manifests: namespace, PostgreSQL StatefulSet, Redis, Backend (2 replicas), Frontend (2 replicas), Storage PVC, Ingress with TLS, Secrets
- [x] Caddy updated with Grafana proxy route

### v0.7.0 — E2EE, SSO/OIDC, Plugin SDK, i18n, Helm
- [x] E2EE module: key derivation (100K-iteration SHA-256), encryption metadata (AES-256-GCM spec), encrypt/decrypt bytes, 3 unit tests
- [x] SSO/OIDC module: OpenID Connect discovery, authorization URL builder, authorization code exchange, user info fetch (Keycloak/Auth0/Okta/Azure AD/Google compatible)
- [x] Plugin SDK: PluginManifest, 8 lifecycle hooks (BeforeUpload/AfterUpload/BeforeDownload/AfterDelete/OnSearch/OnShare/OnNotification/OnSchedule), HookContext, PluginRegistry with dispatch + check_allowed, 1 test
- [x] Localization (i18n): 10 locales (en/es/fr/de/ja/zh/ko/pt/hi/ar), 16 translation keys, Accept-Language header parsing, fallback chain, 5 unit tests
- [x] Helm chart: Chart.yaml, values.yaml (configurable replicas/images/storage/resources/ingress/secrets), deployment template with secrets/backend/frontend/PVC/ingress

---

## Remaining (Priority Order)

### High Priority
- [ ] Populate SQLx offline query cache (`.sqlx/`) for Docker builds (requires running PostgreSQL)

### Low Priority / Future
- [ ] Native Flutter apps (Android, iOS, Windows, Linux, macOS)
- [ ] LDAP/Active Directory support
- [ ] SMB/NFS bridge
- [ ] Face clustering in photos
- [ ] Video/audio streaming engine
- [ ] Accessibility (a11y) audit

### Technical Debt
- [ ] Increase test coverage to 90%+ (currently 57 tests)
- [ ] Add load/stress testing with k6 or similar
