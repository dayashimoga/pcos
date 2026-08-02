# PCOS Changelog

All notable changes to this project will be documented in this file.

## [0.5.0] - 2026-08-02

### Added
- **Full Docker Containerization**: 13-service production stack — PostgreSQL, Redis, NATS, Ollama (optional), backend, frontend, Caddy, Prometheus, Grafana, node-exporter, postgres-exporter, redis-exporter, backup scheduler. Isolated `pcos-net` network, persistent volumes, health checks, restart policies.
- **One-Command Deployment**: `git clone && cp .env.example .env && docker compose up -d`. Root `.env.example` with all configurable variables.
- **S3-Compatible Gateway**: ListBuckets, ListObjectsV2, HeadObject, DeleteObject with XML responses. Compatible with aws-cli, rclone, s3cmd.
- **Prometheus Monitoring**: Scrapes backend metrics, Caddy, PostgreSQL, Redis, node-exporter. 30-day retention.
- **Grafana Provisioning**: Auto-loads dashboards and Prometheus datasource on startup.
- **Backup Retention Policy**: `POST /api/v1/backups/retention` — auto-delete old backups beyond configurable keep count.
- **Backup Verification**: `GET /api/v1/backups/:id/verify` — manifest integrity, file existence audit, health status.
- **Backup Scheduler Container**: Daily pg_dump with automatic 30-backup retention.
- **Agent Dockerfile**: Multi-stage build, non-root user, syncs to `/data/pcos/sync`.
- **CI Expansion**: Agent build/test, SBOM/license scan (cargo-deny), Docker Compose validation.
- **Release Expansion**: Agent builds for 3 platforms, aarch64 backend cross-compilation, multi-platform Docker images (amd64+arm64), SHA256 checksums.

### Changed
- Ollama moved to optional Docker Compose profile (`docker compose --profile ai up -d`).
- Dev compose updated with Prometheus/Grafana port exposure.
- Caddy updated with S3 and Grafana proxy routes.
- API reference updated to 80+ endpoints.

---

## [0.4.0] - 2026-08-02

### Added
- **WebDAV Compatibility**: PROPFIND (XML directory listing with DAV 1,2 headers), MKCOL (create folder), DELETE (trash), MOVE (rename via Destination header), OPTIONS (capability advertisement). Compatible with macOS Finder, Windows Explorer, Nautilus.
- **Delta Sync (Agent)**: Content-defined chunking with rolling hash for variable-size chunks (64KB–1MB). SHA-256 per-chunk hashing, diff algorithm that identifies only changed chunks for upload. 3 unit tests.
- **Caddy WebDAV Proxy**: `/webdav/*` routes proxied to backend.

### Changed
- API reference updated to 75+ endpoints.

---

## [0.3.0] - 2026-08-02

### Added
- **Tantivy Full-Text Search**: SearchIndex wired into AppState. Search handler tries Tantivy first, falls back to DB ILIKE. Reindex endpoint actually indexes all user files into Tantivy.
- **Real Backup with File Copy**: Backup creates directory, copies all user files, writes `manifest.json` with file metadata, runs `pg_dump` for database state. Restore reads manifest and copies files back. Delete cleans up disk.
- **Email Notifications (SMTP)**: Full async SMTP sender with AUTH PLAIN, MIME multipart messages. Convenience methods for welcome, backup complete, share notification, and MFA enabled emails.
- **Grafana Dashboard Template**: 12-panel dashboard covering HTTP rate/latency, user/file/storage stats, upload/download bandwidth, error rate, DB connection pool, WebSocket connections, background jobs, AI requests.
- **User Guide**: Comprehensive documentation with curl examples for all features — auth, files, search, sharing, MFA, AI, backups, admin, device agent, web UI.
- **Architecture Decision Records**: 8 ADRs documenting key technical decisions (modular monolith, Axum+SQLx, Flutter+BLoC, Argon2id, JWT rotation, filesystem storage, TOTP, Tantivy).

### Changed
- `AppState` now includes optional `search_index` field (`Option<Arc<dyn Any + Send + Sync>>`).
- Backup `delete` now cleans up files from disk.
- Backup `restore` reads manifest and copies files back to active storage.

---

## [0.2.0] - 2026-08-02

### Added
- **HTTP Range Downloads**: `Range: bytes=START-END` header support for resumable downloads. Returns `206 Partial Content` with `Content-Range` and `Accept-Ranges` headers. ETag support for caching.
- **File Versioning**: `file_versions` table, list/restore/download version API endpoints. Automatic version tracking on file updates.
- **MFA/TOTP**: Complete two-factor authentication — TOTP setup (with provisioning URI for authenticator apps), verify, disable, status. Pure-Rust HMAC-SHA1 implementation with ±1 time step tolerance.
- **RBAC**: Admin/user/viewer roles with `require_admin` guard. Admin endpoints: list users, update roles (with self-demotion prevention), update storage quotas, system-wide statistics.
- **Storage Quotas**: Per-user storage quota (default 10GB) with admin management.
- **Admin Portal**: `/api/v1/admin/users`, `/api/v1/admin/system` endpoints for user and system management.

### Fixed
- **Search Reindex**: Replaced stub handler with real DB-based reindex that queries all user files.
- **Dockerfile**: All 14 crate manifests now copied (was 5 — Docker build would fail).

### Changed
- API reference updated to 70+ endpoints.

---

## [0.1.0] - 2026-08-02

### Added — Backend
- **Auth**: Register, login, refresh (token rotation), logout with Argon2id + JWT
- **Users**: Profile CRUD with password change
- **Devices**: Registration, listing, heartbeat, deletion
- **File Management**: Upload (single + chunked), download, folder CRUD, trash/restore, storage stats
- **Search**: Database-backed search with ILIKE, suggestions, reindex endpoint
- **AI**: Ollama integration for auto-tagging, classification, duplicate detection, smart search
- **Sharing**: Share links with password protection, expiration, download limits, actual file download
- **Sync Engine**: WebSocket with JWT auth, change tracking, conflict resolution, sync folders
- **Notifications**: CRUD with creation endpoint + system notification helper
- **Workers**: Job listing and stats
- **Backups**: Create, list, restore, scheduled backups
- **Analytics**: Overview, storage breakdown, activity timeline, file types, Prometheus metrics
- **Gateway**: All 12 service routers, configurable CORS, body limits, background tasks

### Added — Frontend
- Premium dark theme with responsive layout (desktop/tablet/mobile)
- Auth pages (login, register) with token persistence
- Dashboard with live analytics from API
- File browser (grid/list, breadcrumb, upload, folders, rename, delete)
- Device management page
- Trash page with restore and empty
- Settings page
- Cross-platform file picker (conditional import)

### Added — Device Agent
- CLI with daemon, register, status modes
- Filesystem watcher with SHA-256 indexing
- SQLite local cache with sync log
- Periodic sync loop with multipart upload
- Heartbeat

### Added — Infrastructure
- Docker Compose (Postgres, Redis, NATS, Ollama, backend, frontend, Caddy)
- Multi-stage Dockerfiles
- GitHub Actions CI + Release pipelines
- 10 documentation files

### Security
- SHA-256 refresh token hashing (replaced non-cryptographic DefaultHasher)
- Password complexity validation (8+ chars, upper/lower/digit)
- Filename sanitization (path traversal, null bytes, control chars)
- Email validation
- Configurable CORS origins (PCOS_CORS_ORIGINS)
- WebSocket JWT authentication
- Background token cleanup, trash cleanup, share expiry
- Error response sanitization

### Tests
- 15 backend unit tests (JWT, password, error, storage, validation)
- 9 frontend BLoC tests (auth, files)
