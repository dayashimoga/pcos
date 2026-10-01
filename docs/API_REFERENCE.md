# PCOS API Reference

Base URL: `http://localhost:8080` (direct) or `http://localhost` (via Caddy)

All authenticated endpoints require: `Authorization: Bearer <access_token>`

---

## Health
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | No | Server health + uptime |
| GET | /api/v1/health | No | Same |

---

## Auth
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/auth/register | No | Register (email, display_name, password) |
| POST | /api/v1/auth/login | No | Login (email, password) → tokens |
| POST | /api/v1/auth/refresh | No | Refresh (refresh_token) → new token pair |
| POST | /api/v1/auth/logout | No | Logout (refresh_token) → revoke |
| POST | /api/v1/auth/mfa/setup | Yes | Generate TOTP secret + provisioning URI |
| POST | /api/v1/auth/mfa/verify | Yes | Verify TOTP code → enable MFA |
| POST | /api/v1/auth/mfa/disable | Yes | Disable MFA (requires valid TOTP code) |
| GET | /api/v1/auth/mfa/status | Yes | Check MFA enabled/verified status |

**Password rules**: 8-128 chars, 1+ uppercase, 1+ lowercase, 1+ digit

---

## Users
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/users/me | Yes | Get profile |
| PUT | /api/v1/users/me | Yes | Update profile |
| PUT | /api/v1/users/me/password | Yes | Change password |

---

## Devices
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/devices | Yes | Register device |
| GET | /api/v1/devices | Yes | List devices |
| GET | /api/v1/devices/:id | Yes | Get device |
| DELETE | /api/v1/devices/:id | Yes | Remove device |
| PUT | /api/v1/devices/:id/heartbeat | Yes | Update online status |

---

## Files
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/files/upload | Yes | Upload file (multipart) |
| POST | /api/v1/files/upload/chunk | Yes | Upload chunk |
| POST | /api/v1/files/upload/complete | Yes | Complete chunked upload |
| GET | /api/v1/files/:id | Yes | Get file metadata |
| PUT | /api/v1/files/:id | Yes | Update (rename) |
| DELETE | /api/v1/files/:id | Yes | Trash file |
| GET | /api/v1/files/:id/download | Yes | Download file (supports `Range` header for resume) |
| GET | /api/v1/files/:id/preview | Yes | Preview file (inline content-disposition) |
| PUT | /api/v1/files/:id/move | Yes | Move file |
| PUT | /api/v1/files/:id/favorite | Yes | Toggle favorite star on file/folder |
| POST | /api/v1/files/bulk-delete | Yes | Bulk move items to trash (`{ids: [...]}`) |
| GET | /api/v1/files/:id/versions | Yes | List file versions |
| GET | /api/v1/files/:fid/versions/:vid/download | Yes | Download specific version |
| POST | /api/v1/files/:fid/versions/:vid/restore | Yes | Restore file to specific version |

> **Note**: Download endpoint supports `Range: bytes=START-END` headers for resumable downloads. Returns `206 Partial Content` with `Content-Range` header when Range is specified.

## Folders
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/folders | Yes | Create folder |
| GET | /api/v1/folders | Yes | List root |
| GET | /api/v1/folders/:id | Yes | List folder + breadcrumb |

## Trash
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/trash | Yes | List trashed items |
| POST | /api/v1/trash/:id/restore | Yes | Restore item |
| DELETE | /api/v1/trash/:id | Yes | Permanent delete |
| POST | /api/v1/trash/empty | Yes | Empty trash |

## Storage
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/storage/stats | Yes | User storage stats |

---

## Search
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/search?q= | Yes | Search files |
| GET | /api/v1/search/suggest?q= | Yes | Search suggestions |
| POST | /api/v1/search/reindex | Yes | Reindex all files |

---

## AI
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/ai/tag | Yes | Auto-tag file (filename, mime_type) |
| POST | /api/v1/ai/classify | Yes | Classify file |
| GET | /api/v1/ai/duplicates | Yes | Find duplicate files (hash-based) |
| GET | /api/v1/ai/smart-search?q= | Yes | AI-enhanced search |
| GET | /api/v1/ai/status | Yes | AI provider status |

---

## Sharing
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/shares | Yes | Create share link |
| GET | /api/v1/shares | Yes | List shares |
| GET | /api/v1/shares/:id | Yes | Get share |
| PUT | /api/v1/shares/:id | Yes | Update share |
| DELETE | /api/v1/shares/:id | Yes | Delete share |
| GET | /api/v1/shared/:token | No | Access shared file info |
| GET | /api/v1/shared/:token/download | No | Download shared file |

---

## Sync
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/sync/ws?token= | Token | WebSocket sync connection |
| GET | /api/v1/sync/status | Yes | Sync status per device |
| GET | /api/v1/sync/changes | Yes | List changes since timestamp |
| POST | /api/v1/sync/resolve | Yes | Resolve conflict |
| GET | /api/v1/sync/folders | Yes | List sync folders |
| POST | /api/v1/sync/folders | Yes | Add sync folder |
| DELETE | /api/v1/sync/folders/:id | Yes | Remove sync folder |

---

## Notifications
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/notifications | Yes | Create notification |
| GET | /api/v1/notifications | Yes | List (last 50) |
| PUT | /api/v1/notifications/:id/read | Yes | Mark read |
| POST | /api/v1/notifications/read-all | Yes | Mark all read |
| GET | /api/v1/notifications/unread-count | Yes | Unread count |

---

## Jobs
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/jobs | Yes | List jobs |
| GET | /api/v1/jobs/stats | Yes | Job statistics |

---

## Backups
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/backups | Yes | Create backup |
| GET | /api/v1/backups | Yes | List backups |
| GET | /api/v1/backups/:id | Yes | Get backup |
| DELETE | /api/v1/backups/:id | Yes | Delete backup |
| POST | /api/v1/backups/:id/restore | Yes | Restore backup |
| POST | /api/v1/backups/schedules | Yes | Create schedule |
| GET | /api/v1/backups/schedules | Yes | List schedules |
| DELETE | /api/v1/backups/schedules/:id | Yes | Delete schedule |

---

## Analytics
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/analytics/overview | Yes | Dashboard stats |
| GET | /api/v1/analytics/storage | Yes | Storage breakdown |
| GET | /api/v1/analytics/activity | Yes | 30-day activity |
| GET | /api/v1/analytics/file-types | Yes | File type breakdown |
| GET | /api/v1/admin/metrics | No | Prometheus metrics |

**Total: 55+ endpoints**

---

## Admin (RBAC)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/admin/users | Admin | List all users |
| PUT | /api/v1/admin/users/role | Admin | Update user role (admin/user/viewer) |
| PUT | /api/v1/admin/users/quota | Admin | Update storage quota |
| GET | /api/v1/admin/system | Admin | System-wide statistics |

**Total: 70+ endpoints**

---

## WebDAV (RFC 4918 Compatibility Layer)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| PROPFIND | /webdav | Yes | List root directory hierarchy (XML multistatus) |
| PROPFIND | /webdav/*path | Yes | List directory contents or file properties |
| MKCOL | /webdav/*path | Yes | Create folder collection |
| GET | /webdav/*path | Yes | Download file (supports HTTP 206 Range streaming) |
| HEAD | /webdav/*path | Yes | Query file headers (Content-Length, Content-Type, ETag) |
| PUT | /webdav/*path | Yes | Stream file upload with real-time SHA-256 calculation |
| DELETE | /webdav/*path | Yes | Move file or folder collection to trash |
| MOVE | /webdav/*path | Yes | Rename or move file/folder (supports `Destination` header) |
| COPY | /webdav/*path | Yes | Copy file or directory collection (`Destination` header) |
| OPTIONS | /webdav, /webdav/*path | No | Advertise DAV: 1, 2 capabilities and allowed methods |

---

## S3-Compatible Gateway
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /s3 | Yes | ListBuckets (XML) |
| GET | /s3/:bucket | Yes | ListObjectsV2 (XML, prefix/max-keys pagination) |
| GET | /s3/:bucket/*key | Yes | GetObject (supports HTTP 206 Range streaming) |
| PUT | /s3/:bucket/*key | Yes | PutObject (streamed upload with SHA-256 calculation) |
| HEAD | /s3/:bucket/*key | Yes | HeadObject (size, ETag, Content-Type, Last-Modified) |
| DELETE | /s3/:bucket/*key | Yes | DeleteObject (moves object to trash) |

> Compatible with aws-cli, rclone, Cyberduck, and s3cmd.

---

## Media Streaming (Direct Play & Scoped Tokens)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/streaming/:file_id/token | Yes | Issue short-lived (2h) user/file/device-scoped playback token |
| GET | /api/v1/streaming/play?token=... | Scoped Token | Stream media via HTTP 206 Range for TVs/browsers (no leaked user session) |
| GET | /api/v1/streaming/:file_id/stream | Yes | Direct authenticated HTTP 206 Partial Content Range streaming |
| GET | /api/v1/streaming/:file_id/probe | Yes | ffprobe metadata extraction (codecs, bitrate, dimensions, audio tracks) |

---

## OCR / Text Extraction
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/search/extract/:id | Yes | Extract text from file (OCR/PDF/plaintext) + index to Tantivy |

---

## Web Push Notifications
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /api/v1/push/subscribe | Yes | Register browser push subscription |
| POST | /api/v1/push/unsubscribe | Yes | Remove push subscription |
| GET | /api/v1/push/subscriptions | Yes | List push subscriptions |
| POST | /api/v1/push/send | Yes | Send push notification to all subscribed browsers |

---

## Backup & Disaster Recovery (Full System & Payloads)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/v1/backups | Yes | List user backups with metadata |
| POST | /api/v1/backups | Yes | Create full backup (payloads + versions + metadata + manifest) |
| GET | /api/v1/backups/:id | Yes | Get backup details and storage location |
| DELETE | /api/v1/backups/:id | Yes | Delete backup archive and payloads |
| POST | /api/v1/backups/:id/restore | Yes | Full DR restore: payloads, file entries, versions, shares + verification |
| GET | /api/v1/backups/:id/verify | Yes | Cryptographic SHA-256 integrity validation of all backup payloads |
| POST | /api/v1/backups/retention | Yes | Enforce retention policy (keep N most recent backups) |
| GET | /api/v1/backups/schedules | Yes | List automated backup cron schedules |
| POST | /api/v1/backups/schedules | Yes | Create automated backup schedule |
| DELETE | /api/v1/backups/schedules/:id | Yes | Delete backup schedule |

**Total: 100+ endpoints**

