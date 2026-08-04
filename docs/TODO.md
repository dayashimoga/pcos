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

### v0.8.0 — LDAP, SMB, Service Worker, Production Hardening
- [x] LDAP/Active Directory module: LdapConfig (AD + OpenLDAP presets), authenticate + sync_groups stubs, production implementation notes for `ldap3` crate
- [x] SMB/CIFS bridge module: SmbShareConfig, SmbSession tracking, share registration, protocol stub with SMB2 implementation notes
- [x] Service Worker (frontend): static asset caching for offline support, Web Push notification handler with click-to-open, cache versioning
- [x] All protocol bridges wired into crate routers (smb_bridge in file_metadata, ldap in auth)

### v0.9.0 — Autonomous Production Certification Framework
- [x] `qa/feature_registry.json`: 36 features across 12 modules, machine-readable acceptance criteria, coverage targets, blocker annotations
- [x] `qa/docker-compose.test.yml`: isolated test environment (PostgreSQL, Redis, NATS, backend, Prometheus) with health checks
- [x] `qa/fixtures/seed_data.json`: 3 test users, 4 test files, 4 folders, 2 shares, 2 devices, 5 chaos scenarios, performance thresholds
- [x] `qa/scripts/orchestrator.sh`: autonomous test orchestrator — provisions stack, seeds data, runs 30+ API tests + Rust unit/agent tests, security validation, generates JSON/JUnit/Markdown reports, auto-teardown
- [x] `qa/scripts/certify.sh`: quality gate verifier — reads certification report, enforces gates from feature registry, CI/CD exit codes
- [x] `qa/scripts/self_heal.sh`: self-healing iteration loop (max 5 iterations), failure analysis, blocker identification, auto-retry
- [x] `.github/workflows/certification.yml`: 5-phase CI pipeline — build+test, security scan (cargo-deny + secret scanning), integration tests (live PostgreSQL+Redis), Docker Compose validation, certification report + GitHub Summary
- [x] `qa/README.md`: complete QA documentation — architecture, quick start, feature registry summary, quality gates, test types, CI/CD integration, report formats
- [x] Quality gates enforced: ≥90% overall, ≥95% critical, 100% auth/sync/encryption, 0 critical defects, 0 regressions, 0 placeholders

### v1.0.0 — Native Flutter Apps (All 6 Platforms)
- [x] `build/Dockerfile.android`: Docker-based Android APK/AAB builder (ghcr.io/cirruslabs/flutter, multi-stage, artifact extraction)
- [x] `build/Dockerfile.linux`: Docker-based Linux desktop builder (GTK3/clang/cmake, AppImage directory structure + .desktop file)
- [x] `build/Dockerfile.web`: Docker-based production web builder (CanvasKit renderer, nginx serving)
- [x] `build/build_apps.sh`: build orchestrator script — Docker-only, no local SDK installs, supports android/linux/web/all targets
- [x] `.github/workflows/native_apps.yml`: CI for all 6 platforms — Android/Linux/Web via Docker, iOS/macOS via macos-latest, Windows via windows-latest, SHA256 checksums
- [x] `frontend/android/`: full Android config — AndroidManifest.xml (permissions, deep linking), build.gradle (API 24-34, ProGuard), settings.gradle, gradle.properties
- [x] `frontend/ios/Runner/Info.plist`: iOS config — camera/photo permissions, deep linking via pcos:// scheme
- [x] `frontend/windows/CMakeLists.txt`: Windows desktop CMake config
- [x] `frontend/linux/CMakeLists.txt`: Linux desktop CMake config (GTK3)
- [x] `frontend/macos/CMakeLists.txt`: macOS desktop CMake config
### v1.2.0 — Production Hardening & UI Overhaul
- [x] Consolidated CI: `ci.yml` + `certification.yml` → single `ci.yml` (6 jobs instead of ~15)
- [x] Fixed Windows build: CMakeLists.txt patched for Visual Studio 17 2022
- [x] Removed all `|| true` error suppression from workflows
- [x] Added env var fallbacks (DATABASE_URL, JWT_SECRET) across all CI jobs
- [x] Backend: config-rs `prefix_separator("_")` fix, JWT secret warning, `/api/v1/version`, email normalization
- [x] Backend: WebDAV route collision fix, pool config logging
- [x] Frontend: collapsible sidebar with animation + keyboard shortcuts (Ctrl+1-7)
- [x] Frontend: Material 3 NavigationBar for mobile (5 items), Admin/Settings in app bar
- [x] Frontend: files page skeleton loading, error retry, RefreshIndicator, responsive sliver grid
- [x] Frontend: improved dialogs (icons, FilledButton, keyboard submit), hover effects
- [x] Frontend: API client retry interceptor (2 retries, exponential backoff)
- [x] Docker Compose: backend healthcheck (/health, 30s start period)
- [x] K8s: liveness probes on backend + frontend, PodDisruptionBudget for backend
- [x] Docs: PRODUCTION_READINESS.md, SECURITY_REPORT.md, TEST_REPORT.md, PERFORMANCE_REPORT.md
- [x] Docs: CHANGELOG.md updated with full v1.2.0 entry

### v1.1.0 — Video/Audio Adaptive Streaming (Docker FFmpeg)
- [x] `build/Dockerfile.transcoder`: Alpine + FFmpeg/ffprobe Docker image for transcoding
- [x] `backend/crates/streaming/scripts/transcode.sh`: HLS adaptive bitrate (360p/720p/1080p master playlist), audio-only (HLS + MP3), thumbnail + sprite generation
- [x] `backend/crates/streaming/scripts/probe.sh`: media metadata extraction via ffprobe (JSON output)
- [x] `backend/crates/streaming/src/service.rs`: queue/execute transcoding via Docker, probe media, list jobs, get HLS URL
- [x] `backend/crates/streaming/src/handlers.rs`: 5 API endpoints (POST transcode, GET jobs, GET job/:id, GET stream/:id, POST probe/:file_id)
- [x] `backend/crates/streaming/src/lib.rs`: crate router with 5 routes
- [x] `backend/crates/streaming/Cargo.toml`: workspace dependencies
- [x] `backend/migrations/20240101000010_transcode_jobs.sql`: transcode_jobs table with indexes
### v1.3.0 — UX Critical Fixes & Admin CRUD
- [x] Test fixes: patched auth_bloc_test and file_bloc_test mock syntax
- [x] Zero panic code: replaced all production `.unwrap()` calls with proper error handling
- [x] Dynamic versioning: API version endpoint wired into Settings page footer
- [x] Settings wiring: User display name edit and password change forms fully functional
- [x] File context menu: added Download and Copy Link quick actions
- [x] File sorting: added sort options (Name, Size, Type) with asc/desc toggle and folders-first rule
- [x] Admin Portal CRUD: full user management (Create User dialog, Role update, Delete user with confirmation)
- [x] Dashboard: Upload Files and Search quick actions

### v1.4.0 — Feature Parity & Design System
- [x] Theme system: full Material 3 Light theme added alongside Dark theme
- [x] Live theme toggle: ValueNotifier-driven theme switcher in Settings page
- [x] File Info dialog: displays complete metadata (MIME, size, ID, dates, quick actions)
- [x] File Move dialog: move files and folders to any target folder ID
- [x] Upload progress: visual spinner snackbar feedback during file uploads
- [x] Search filters: filter chips (All/Files/Folders), sorting (Name/Size/Relevance), copy link action

### v1.5.0 — Advanced Features & Deployment Readiness
- [x] Global search command palette: Ctrl+K overlay with fuzzy page search & keyboard shortcuts
- [x] File preview panel: unified preview for PDF (fullscreen+toolbar), Video (HLS-ready player), Image (zoom), Audio, and Text/Code
- [x] Image thumbnails: inline image previews inside file grid cards
- [x] Photo gallery timeline: `/gallery` page with photos grouped by month, responsive grid, tap-to-preview
- [x] File sharing dialog: `POST /api/v1/shares` with password protection, expiry dropdown, download limits
- [x] Context menu: 8 actions for files (Download, Copy Link, Share..., Info, Move, Rename, Delete)
- [x] Setup wizard: `/setup` 3-step first-run flow (Server check, Admin account, Completion)
- [x] PCOS Doctor: `/doctor` diagnostic suite with 10 automated component health checks
- [x] QR-based device onboarding: `/devices/pair` page with 6-digit code, animated QR display, expiry timer
- [x] One-command installer: `install.sh` bash script with prerequisite checks, auto .env generation, Docker Compose deployment
- [x] Dashboard: Recent Files section with 5 most recent files from API

---

## Remaining (Future Roadmap)

### Requires External Infrastructure
- [ ] Populate SQLx offline query cache (`.sqlx/`) — requires running PostgreSQL instance
- [ ] Face clustering in photos — requires ML model (e.g., dlib/ONNX face embeddings)
- [ ] Full SMB2 protocol — requires `smb2` crate or Samba integration
- [ ] Full LDAP bind — requires `ldap3` crate + LDAP server

### Nice-to-Have
- [ ] Accessibility (a11y) audit + WCAG 2.1 AA compliance
- [ ] Load/stress testing with k6 or similar
- [ ] E2E browser tests (Playwright/Selenium)
- [ ] Client-side E2EE key management (server-side AES-256-GCM implemented)

### Test Coverage
- Current: 57 unit tests + 30+ API tests across 12 versions
- Target: 90%+ (enforced by qa/scripts/certify.sh)
