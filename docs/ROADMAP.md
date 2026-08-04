# PCOS Development Roadmap

## v1.3.0 — UX Critical Fixes ✅

- [x] Fix broken test syntax (auth_bloc_test, file_bloc_test)
- [x] Eliminate production `.unwrap()` calls
- [x] Wire settings page callbacks (profile, password, version)
- [x] Add file download action to context menu
- [x] Add file copy link action to context menu
- [x] Fix hardcoded version string → read from API
- [x] Add sort options (name, size, type)
- [x] Admin: Create User dialog
- [x] Admin: Delete User with confirmation
- [x] Dashboard: Upload Files + Search quick actions

---

## v1.4.0 — Feature Parity ✅

### File Management
- [x] File Info dialog (type, MIME, size, ID, dates, quick actions)
- [x] Move files between folders (dialog + API)
- [x] Context menu: 7 actions (Download, Copy Link, Info, Move, Rename, Delete) for files
- [x] Upload progress indicator (spinner snackbar)
- [x] Sort: folders always first, Name/Size/Type with asc/desc toggle

### Search
- [x] Filter chips: All / Files / Folders (re-queries API)
- [x] Sort results: By Name, By Size, or Relevance
- [x] Copy link button in search results

### Dashboard
- [x] Recent Files section (fetches 5 most recent from API)
- [x] "View all" link to files page

### Settings & Theme
- [x] Light theme (full Material 3 light theme data)
- [x] Dark/Light toggle in Settings (persisted via ValueNotifier)

### Admin
- [x] Full user CRUD: create, read, update role, delete

---

## v1.5.0 — Advanced Features ✅

### Search & AI
- [x] Global search in app bar (Ctrl+K command palette)
- [ ] AI document Q&A ("Ask My Files")
- [ ] Duplicate file finder

### File Management
- [ ] Drag-and-drop upload (web)
- [ ] Bulk file selection with toolbar
- [ ] Favorites (star files)
- [x] File sharing dialog (password, expiry, download limits)
- [x] Image thumbnail previews in file grid (for image/* MIME types)

### Deployment
- [x] Setup wizard (first-run configuration) — 3-step: server check → admin account → done
- [x] Environment validator ("PCOS Doctor") — 10 diagnostic checks with pass/fail summary
- [x] One-command installer script — `curl | bash` with prerequisite checks, .env generation, Docker Compose

### Media
- [x] PDF preview panel — full-screen with toolbar, open-in-new-tab
- [x] Video player integration (HLS) — transport controls, play/pause, seek, fullscreen
- [x] Photo gallery view with timeline — grouped by month, responsive grid, tap-to-preview

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
- [x] QR-based device onboarding — 6-digit pairing code, animated QR display, instructions

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
| v1.3.0 | UX Fixes | Settings wired, file actions, sort, admin CRUD |
| v1.4.0 | Feature Parity | File info/move, search filters, theme toggle, recent files |
