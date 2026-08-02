# PCOS Changelog

All notable changes to this project will be documented in this file.

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
