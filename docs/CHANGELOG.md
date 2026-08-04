# PCOS Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-08-04

### Production Hardening

#### CI/CD
- Fixed Windows build: patch generated `CMakeLists.txt` to use `Visual Studio 17 2022` after `flutter create`
- Removed all silent error suppression (`|| true`) from CI workflows; failures now properly surface
- Added `DATABASE_URL` and `JWT_SECRET` direct env var exports alongside `PCOS_` prefixed vars in all test jobs
- Added `continue-on-error: true` for iOS/macOS builds (code signing requires Apple credentials)
- Added `timeout-minutes: 15` to integration test job
- Added `packages: write` permission to release Docker push job
- Added `CARGO_INCREMENTAL: 0` to release builds for reproducibility
- Installed `cargo-audit` with `--locked` flag for deterministic CI

#### Backend
- Added `.prefix_separator("_")` to config-rs environment parser — fixes `PCOS_DATABASE__URL` not being recognized
- Added direct `DATABASE_URL` and `JWT_SECRET` env var fallbacks in `config.rs`
- Added startup warning when default JWT secret is detected
- Added `/api/v1/version` endpoint with build info
- Added database pool configuration logging at startup
- Normalized email to lowercase in register and login (prevents case-sensitive duplicates)
- Fixed Axum router collision between `/webdav/*path` and `/webdav/:name` routes

#### Frontend
- Added retry interceptor with exponential backoff (2 retries for network errors and 5xx)

#### Deployment
- Added healthcheck to backend service in `docker-compose.yml` (curl /health, 30s start period)
- Removed incomplete tracked `frontend/windows/CMakeLists.txt` and `frontend/linux/CMakeLists.txt`

#### Documentation
- Added `PRODUCTION_READINESS.md` — platform matrix, feature completion, deployment checklist
- Added `SECURITY_REPORT.md` — auth controls, data protection, dependency scanning
- Added `TEST_REPORT.md` — test infrastructure, coverage by module, known gaps
- Added `PERFORMANCE_REPORT.md` — build times, optimizations, database tuning

---

## [1.1.0] - 2026-08-03

### Added
- **Video/Audio Adaptive Streaming**: Docker-based FFmpeg transcoding — no local FFmpeg install.
  - `Dockerfile.transcoder`: Alpine + FFmpeg/ffprobe image.
  - `transcode.sh`: HLS adaptive bitrate (360p/720p/1080p with master playlist), audio-only extraction (HLS + MP3 fallback), thumbnail + sprite sheet generation.
  - `probe.sh`: Media metadata extraction (duration, resolution, codec, bitrate) as JSON.
  - Streaming service: queue transcoding jobs, execute via Docker, probe media, serve HLS URLs.
  - 5 new API endpoints: `POST /transcode`, `GET /jobs`, `GET /jobs/:id`, `GET /stream/:id`, `POST /probe/:file_id`.
  - DB migration: `transcode_jobs` table with indexes on user, file, and status.
  - Docker Compose: transcoder service with `transcode` profile.

---

## [1.0.0] - 2026-08-03

### Added
- **Native Flutter Apps (All 6 Platforms)**: Docker-based build system — no local SDK installs required.
  - **Android**: `Dockerfile.android` (APK + AAB via `ghcr.io/cirruslabs/flutter`), `AndroidManifest.xml` (internet/storage/camera permissions, deep linking), `build.gradle` (API 24-34, ProGuard, minify+shrink).
  - **iOS**: `Info.plist` (camera/photo permissions, `pcos://` deep link scheme, local networking).
  - **Windows**: `CMakeLists.txt` for Flutter Windows desktop build.
  - **Linux**: `Dockerfile.linux` (GTK3/clang/cmake, AppImage directory + `.desktop` file), `CMakeLists.txt`.
  - **macOS**: `CMakeLists.txt` for Flutter macOS desktop build.
  - **Web**: `Dockerfile.web` (CanvasKit renderer, nginx serving).
- **Build Orchestrator** (`build/build_apps.sh`): Docker-only script — `bash build/build_apps.sh [android|linux|web|all]`.
- **CI Workflow** (`.github/workflows/native_apps.yml`): 6-platform matrix — Android/Linux/Web via Docker, iOS/macOS via macos-latest, Windows via windows-latest. SHA256 checksums for all artifacts.

---

## [0.9.0] - 2026-08-03

### Added
- **Autonomous QA Framework** (`qa/`): Feature registry (36 features, 12 modules), Docker test environment, test fixtures (users/files/chaos), orchestrator script (30+ API tests + Rust unit tests), quality gate verifier, self-healing iteration loop.
- **Certification CI/CD** (`.github/workflows/certification.yml`): 5-phase pipeline — build+test, security scan (cargo-deny + secret scanning), integration tests (live PostgreSQL+Redis), Docker Compose validation, certification report with GitHub Summary.
- **Quality Gates**: ≥90% overall pass rate, ≥95% critical modules, 100% auth/sync/encryption, 0 critical/high defects, 0 regressions, 0 placeholders — enforced in CI.
- **Reports**: JSON (`certification.json`), JUnit XML (`results.xml`), Markdown (`certification_report.md`) with feature completion matrix, pass/fail status, and remediation guidance.

---

## [0.8.0] - 2026-08-03

### Added
- **LDAP/Active Directory**: `LdapConfig` with Active Directory and OpenLDAP presets, `authenticate` and `sync_groups` stubs with production implementation notes for `ldap3` crate.
- **SMB/CIFS Bridge**: `SmbShareConfig`, `SmbSession` tracking, share registration, protocol stub with SMB2 NEGOTIATE/SESSION_SETUP/TREE_CONNECT flow documentation.
- **Service Worker**: Static asset caching (offline support), Web Push notification handler with `showNotification` + click-to-open, cache versioning with automatic cleanup.

---

## [0.7.0] - 2026-08-03

### Added
- **E2EE Module**: Key derivation (100K-iteration SHA-256), AES-256-GCM encryption metadata, encrypt/decrypt bytes with roundtrip verification. 3 unit tests.
- **SSO/OIDC**: OpenID Connect discovery, authorization URL builder, authorization code exchange, user info fetch. Compatible with Keycloak, Auth0, Okta, Azure AD, Google.
- **Plugin SDK**: `PluginManifest`, 8 lifecycle hooks (`BeforeUpload`/`AfterUpload`/`BeforeDownload`/`AfterDelete`/`OnSearch`/`OnShare`/`OnNotification`/`OnSchedule`), `HookContext`, `PluginRegistry` with dispatch and `check_allowed`. 1 test.
- **Localization (i18n)**: 10 locales (en/es/fr/de/ja/zh/ko/pt/hi/ar), 16 translation keys, `Accept-Language` header parsing, locale fallback chain. 5 unit tests.
- **Helm Chart**: `Chart.yaml`, `values.yaml` (replicas, images, storage, resources, ingress, secrets), deployment template with Secrets, Backend, Frontend, PVC, conditional Ingress+TLS.

---

## [0.6.0] - 2026-08-02

### Added
- **LAN/P2P Discovery**: UDP broadcast peer discovery in agent with auto-timeout. Announces `_pcos` service, tracks peers by IP/hostname. 2 unit tests.
- **OCR Text Extraction**: Plaintext (direct read), PDF (BT/ET text stream parsing with Tesseract fallback), images (Tesseract OCR), EXIF metadata (exiftool). `POST /api/v1/search/extract/:id` extracts + indexes to Tantivy.
- **Web Push Notifications**: Subscribe/unsubscribe browsers, send push notifications via Web Push protocol (RFC 8030), auto-cleanup expired subscriptions (410 Gone). 4 new endpoints.
- **DB Migration**: `push_subscriptions` (unique endpoint, user FK) and `text_extractions` (GIN full-text index) tables.
- **Kubernetes Manifests**: Namespace, PostgreSQL StatefulSet with PVC, Redis, Backend (2 replicas, health checks, resource limits), Frontend (2 replicas), 100Gi Storage PVC, Ingress with TLS + cert-manager, Secrets.

### Changed
- Caddy updated with `/grafana/*` proxy route.
- Search crate now includes extraction module.
- Notification crate now includes web_push module.

---

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
