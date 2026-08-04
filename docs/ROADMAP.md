# PCOS Development Roadmap

## v1.3.0 — UX Critical Fixes (Current Sprint)

### Must Fix (UX Blockers)
- [x] Fix broken test syntax (auth_bloc_test, file_bloc_test)
- [x] Eliminate production `.unwrap()` calls
- [ ] Wire settings page callbacks (profile, password, version)
- [ ] Add file download action to context menu
- [ ] Add file sharing UI (create/copy share link)
- [ ] Fix hardcoded version string → read from API
- [ ] Add sort options (name, date, size, type)

### Should Fix (Quality)
- [ ] Add download action to search results (actual file save)
- [ ] Remove `formatFileSize` duplication
- [ ] Add upload progress indicator

---

## v1.4.0 — Feature Parity with Nextcloud

### File Management
- [ ] Bulk file selection with toolbar
- [ ] Drag-and-drop upload (web)
- [ ] File info/details side panel
- [ ] Favorites (star files)
- [ ] Recent files view
- [ ] Move/Copy files between folders
- [ ] File sharing dialog (password, expiry, link copy)

### Admin
- [ ] Create user from admin panel
- [ ] Delete user from admin panel
- [ ] System health monitoring card
- [ ] Storage breakdown per user

### Settings
- [ ] Light/dark theme toggle (persist preference)
- [ ] Backup schedule configuration UI
- [ ] Sync folder configuration UI

---

## v1.5.0 — Advanced Features

### Search & AI
- [ ] Global search in app bar (Ctrl+K)
- [ ] Search filters (type, date, size)
- [ ] AI document Q&A ("Ask My Files")
- [ ] Duplicate file finder

### Deployment
- [ ] Setup wizard (first-run configuration)
- [ ] Environment validator ("PCOS Doctor")
- [ ] One-command installer script
- [ ] Auto-update mechanism

### Media
- [ ] Image thumbnail previews in file grid
- [ ] PDF preview panel
- [ ] Video player integration (HLS)
- [ ] Photo gallery view with timeline

---

## v2.0.0 — Platform Expansion

### New Features
- [ ] Collaborative shared workspaces
- [ ] File request links
- [ ] CalDAV/CardDAV (calendar/contacts)
- [ ] Password vault integration
- [ ] Secure notes/wiki
- [ ] Workflow automation engine
- [ ] Plugin marketplace UI
- [ ] QR-based device onboarding

### Platform
- [ ] Mobile camera auto-upload
- [ ] Share extensions (Android/iOS)
- [ ] System tray integration (Windows/macOS/Linux)
- [ ] Offline-first with sync queue
- [ ] REST API explorer UI
- [ ] GraphQL gateway (optional)
- [ ] Public SDK for extensions

---

## Completed Versions

| Version | Theme | Key Features |
|---------|-------|-------------|
| v0.1.0 | Core Platform | Auth, files, search, AI, sync, notifications |
| v0.2.0 | Enterprise Security | 2FA, RBAC, quotas, versioning, admin portal |
| v0.3.0 | Search & Backup | Tantivy, real backup with files, email, Grafana |
| v0.4.0 | Compatibility | WebDAV, delta sync |
| v0.5.0 | Containerization | Docker Compose, S3 API, monitoring |
| v0.6.0 | OCR & K8s | OCR, web push, LAN discovery, K8s manifests |
| v0.7.0 | Enterprise Auth | E2EE, OIDC, plugin SDK, i18n, Helm |
| v0.8.0 | Protocols | LDAP, SMB, service worker |
| v0.9.0 | QA Framework | Test orchestrator, certification pipeline |
| v1.0.0 | Native Apps | 6-platform Flutter builds |
| v1.1.0 | Streaming | HLS adaptive video/audio |
| v1.2.0 | Hardening | CI consolidation, UI overhaul, production fixes |
