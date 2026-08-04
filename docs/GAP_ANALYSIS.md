# PCOS Gap Analysis — Comparison with Production Cloud Platforms

**Date**: 2026-08-04 | **Version**: 1.2.0  
**Benchmark**: Nextcloud, Synology DSM, Google Drive, Dropbox, CasaOS, Immich

---

## Executive Summary

PCOS has a **comprehensive backend** with 75+ API endpoints, 12+ crates, and strong architectural foundations. The primary gaps are in **frontend interactivity** (settings callbacks are no-ops, download doesn't save files), **test compilation** (fixed this sprint), and **deployment simplification**. The backend is significantly more complete than the frontend suggests.

---

## 🔴 High Priority — UX Blockers

### 1. Settings Page Callbacks Are No-Ops
**Gap**: Profile edit, password change, sync settings, storage view, backup settings, AI config — all have `onTap: () {}` (empty callbacks). Users click and nothing happens.  
**Benchmark**: Every cloud platform has working settings pages.  
**Fix**: Wire each settings tile to actual API calls or sub-pages.

### 2. File Download Doesn't Save Files  
**Gap**: Search page shows a download URL in a SnackBar instead of actually downloading the file. Files page has no download action at all.  
**Benchmark**: Google Drive, Dropbox — one-click download.  
**Fix**: Add download action to file context menu; use `url_launcher` or `html.AnchorElement` for web.

### 3. Version String Hardcoded to `v0.2.0`
**Gap**: Settings page shows `PCOS v0.2.0` but we're at v1.2.0.  
**Fix**: Read from `/api/v1/version` endpoint.

### 4. Switches in Settings Are Decorative
**Gap**: Dark mode, auto-tagging, smart search switches have `onChanged: (_) {}` — they toggle visually but don't persist.  
**Benchmark**: All platforms persist settings.

---

## 🟡 Medium Priority — Feature Gaps vs Competitors

### 5. No File Download Action in Files Page
**Gap**: Grid/list context menu only has Rename and Delete. No Download, Share, Move, Copy, or Info.  
**Benchmark**: Nextcloud has Download, Rename, Move, Copy, Delete, Details, Share, Favorite, Tags.

### 6. No Drag-and-Drop Upload
**Gap**: Upload only works via file picker dialog.  
**Benchmark**: Google Drive, Dropbox, Nextcloud — all support drag-and-drop.

### 7. No File/Folder Sharing UI
**Gap**: Backend has full sharing API (password, expiry, download limits) but frontend has no sharing UI.  
**Benchmark**: Core feature of every cloud platform.

### 8. No Favorites/Recent Files
**Gap**: No way to star/favorite files or see recent activity.  
**Benchmark**: Google Drive has Starred, Recent, Shared with me.

### 9. No Upload Progress Indicator
**Gap**: File uploads happen with no visual feedback.  
**Benchmark**: All platforms show progress bar, speed, ETA.

### 10. Admin Page Has No User Create/Delete
**Gap**: Admin page lists users and can edit roles but can't create or delete users.  
**Benchmark**: All admin panels have full user CRUD.

---

## 🟢 Lower Priority — Polish & Features

| # | Gap | Benchmark |
|---|-----|-----------|
| 11 | No light theme option | Most platforms offer both |
| 12 | No file info/details panel | Nextcloud, Google Drive |
| 13 | No bulk selection | All file managers |
| 14 | No sort options (name, date, size, type) | All file managers |
| 15 | No global search in app bar | Nextcloud, Google Drive |
| 16 | `formatFileSize` duplicated in 2 files | Code quality |
| 17 | No onboarding/setup wizard | CasaOS, Synology |
| 18 | No backup schedule UI | Synology, TrueNAS |

---

## ✅ Areas Where PCOS Matches or Exceeds Competitors

| Feature | PCOS | Nextcloud | Google Drive |
|---------|------|-----------|-------------|
| Self-hosted, no cloud dependency | ✅ | ✅ | ❌ |
| WebDAV + S3 compatibility | ✅ | ✅ (WebDAV) | ❌ |
| Adaptive video streaming (HLS) | ✅ | ❌ | ❌ |
| Delta sync (agent) | ✅ | ❌ | ❌ |
| LAN/P2P discovery | ✅ | ❌ | ❌ |
| AI auto-tagging (Ollama) | ✅ | ❌ | ✅ (cloud) |
| OCR + full-text search | ✅ | ✅ | ✅ |
| E2EE (server-side) | ✅ | ✅ | ❌ |
| Web Push notifications | ✅ | ✅ | ✅ |
| Plugin system | ✅ | ✅ | ❌ |
| i18n (10 locales) | ✅ | ✅ | ✅ |
| 6-platform native apps | ✅ | ✅ | ✅ |
| Kubernetes + Helm | ✅ | ✅ | N/A |
| Prometheus/Grafana | ✅ | Community | N/A |
