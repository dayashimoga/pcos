# PCOS Performance Report

**Date**: 2026-08-04  
**Version**: 0.8.0

---

## Build Performance

| Artifact | Build Time | Image Size | Notes |
|----------|-----------|------------|-------|
| Backend Docker (pcos-backend) | ~5-8 min | ~85 MB | Multi-stage, LTO enabled, stripped |
| Frontend Web Docker (pcos-web) | ~3-5 min | ~25 MB | Nginx serving static files |
| Agent Docker (pcos-agent) | ~4-6 min | ~30 MB | Multi-stage, release optimized |
| Android APK | ~8-12 min | ~50 MB | Docker-based Flutter build |
| Android AAB | ~8-12 min | ~24 MB | Docker-based Flutter build |

## Backend Optimizations

| Optimization | Implementation | Impact |
|-------------|---------------|--------|
| Release LTO | `lto = true` in Cargo.toml | ~15% binary size reduction |
| Single Codegen Unit | `codegen-units = 1` | Better optimization at cost of build time |
| Binary Stripping | `strip = true` | ~40% binary size reduction |
| Opt Level 3 | `opt-level = 3` | Maximum runtime performance |
| Connection Pooling | sqlx pool (5-20 connections) | Reduces connection overhead |
| Dependency Caching | Docker layer caching, Swatinem/rust-cache | ~60% CI time reduction |

## Database Performance

| Optimization | Status | Notes |
|-------------|--------|-------|
| Connection Pool | ✅ | 5 min, 20 max connections configurable |
| Index on users.email | ✅ | Implicit via UNIQUE constraint |
| Index on file_entries.user_id | ✅ | Foreign key index |
| Index on file_entries.parent_id | ✅ | Folder listing queries |
| Expired Token Cleanup | ✅ | Background task every hour |
| Trash Auto-Purge | ✅ | Background task every 6 hours |

## Docker Image Optimization

| Technique | Applied | Impact |
|-----------|---------|--------|
| Multi-stage builds | ✅ All Dockerfiles | ~80% size reduction |
| Dependency-only build layer | ✅ Backend Dockerfile | Cached unless Cargo.toml changes |
| Minimal runtime (debian-slim) | ✅ Backend | ~85 MB vs ~1.2 GB with build tools |
| Non-root user | ✅ Backend | Security hardening |
| .dockerignore | ✅ | Faster context transfer |

## Known Performance Considerations

1. **File listing unbounded** — `list_root`/`list_folder` queries return all entries without LIMIT/OFFSET pagination. For users with >1000 files in a folder, this could cause slowdowns.
2. **Tantivy index** — Search index is file-based, stored alongside file storage. May need separate volume for large deployments.
3. **Background tasks** — Token cleanup and trash purge run on fixed intervals. Under high load, these should be rate-limited.
