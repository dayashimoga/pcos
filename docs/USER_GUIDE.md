# PCOS User Guide

## Getting Started

### 1. Register an Account
```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"MyPass123","display_name":"Your Name"}'
```
**Password requirements**: 8-128 chars, at least 1 uppercase, 1 lowercase, 1 digit.

### 2. Login
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"MyPass123"}'
```
Save the `access_token` from the response. Use it in all subsequent requests:
```
Authorization: Bearer <access_token>
```

### 3. Refresh Your Token
Access tokens expire in 15 minutes. Use the refresh token:
```bash
curl -X POST http://localhost:8080/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"<refresh_token>"}'
```

---

## File Management

### Upload a File
```bash
curl -X POST http://localhost:8080/api/v1/files/upload \
  -H "Authorization: Bearer <token>" \
  -F "file=@/path/to/document.pdf"
```

### Upload Large Files (Chunked)
```bash
# Upload chunks
curl -X POST http://localhost:8080/api/v1/files/upload/chunk \
  -H "Authorization: Bearer <token>" \
  -F "upload_id=<uuid>" -F "chunk_index=0" -F "chunk=@chunk0.bin"

# Complete the upload
curl -X POST http://localhost:8080/api/v1/files/upload/complete \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"upload_id":"<uuid>","filename":"bigfile.zip","total_chunks":5}'
```

### Create a Folder
```bash
curl -X POST http://localhost:8080/api/v1/folders \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"My Documents","parent_id":null}'
```

### List Files
```bash
# Root directory
curl http://localhost:8080/api/v1/folders -H "Authorization: Bearer <token>"

# Inside a folder (with breadcrumb path)
curl http://localhost:8080/api/v1/folders/<folder_id> -H "Authorization: Bearer <token>"
```

### Download a File
```bash
curl -O http://localhost:8080/api/v1/files/<file_id>/download \
  -H "Authorization: Bearer <token>"

# Resume a download (Range support)
curl -H "Range: bytes=1000-" http://localhost:8080/api/v1/files/<file_id>/download \
  -H "Authorization: Bearer <token>"
```

### Preview a File
```bash
curl http://localhost:8080/api/v1/files/<file_id>/preview \
  -H "Authorization: Bearer <token>"
```

### Rename / Move / Trash
```bash
# Rename
curl -X PUT http://localhost:8080/api/v1/files/<id> \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" -d '{"name":"new_name.pdf"}'

# Move to folder
curl -X PUT http://localhost:8080/api/v1/files/<id>/move \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" -d '{"target_folder_id":"<folder_id>"}'

# Trash (soft delete)
curl -X DELETE http://localhost:8080/api/v1/files/<id> \
  -H "Authorization: Bearer <token>"

# Restore from trash
curl -X POST http://localhost:8080/api/v1/trash/<id>/restore \
  -H "Authorization: Bearer <token>"
```

### File Versioning
```bash
# List versions
curl http://localhost:8080/api/v1/files/<id>/versions \
  -H "Authorization: Bearer <token>"

# Restore a version
curl -X POST http://localhost:8080/api/v1/files/<file_id>/versions/<version_id>/restore \
  -H "Authorization: Bearer <token>"
```

---

## Search
```bash
# Search files by name
curl "http://localhost:8080/api/v1/search?q=report&limit=20" \
  -H "Authorization: Bearer <token>"

# Get suggestions
curl "http://localhost:8080/api/v1/search/suggest?q=doc" \
  -H "Authorization: Bearer <token>"

# Rebuild search index
curl -X POST http://localhost:8080/api/v1/search/reindex \
  -H "Authorization: Bearer <token>"
```

---

## Sharing
```bash
# Create a share link
curl -X POST http://localhost:8080/api/v1/shares \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"file_entry_id":"<file_id>","permission":"download","password":"optional","expires_in_hours":72,"max_downloads":10}'

# Access shared file (no auth required)
curl http://localhost:8080/api/v1/shared/<token>
curl -O http://localhost:8080/api/v1/shared/<token>/download
```

---

## Security

### Enable Two-Factor Authentication
```bash
# 1. Setup — get secret and QR code URI
curl -X POST http://localhost:8080/api/v1/auth/mfa/setup \
  -H "Authorization: Bearer <token>"
# → {"secret":"ABC...","provisioning_uri":"otpauth://totp/PCOS:..."}

# 2. Add to authenticator app (Google Authenticator, Authy, etc.)
# 3. Verify with 6-digit code
curl -X POST http://localhost:8080/api/v1/auth/mfa/verify \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" -d '{"code":"123456"}'

# Check status
curl http://localhost:8080/api/v1/auth/mfa/status -H "Authorization: Bearer <token>"

# Disable (requires valid code)
curl -X POST http://localhost:8080/api/v1/auth/mfa/disable \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" -d '{"code":"123456"}'
```

---

## AI Features
```bash
# Auto-tag a file
curl -X POST http://localhost:8080/api/v1/ai/tag \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" -d '{"filename":"quarterly_report.pdf","mime_type":"application/pdf"}'

# Smart search
curl "http://localhost:8080/api/v1/ai/smart-search?q=photos from last vacation" \
  -H "Authorization: Bearer <token>"

# Find duplicates
curl http://localhost:8080/api/v1/ai/duplicates -H "Authorization: Bearer <token>"
```

---

## Backups
```bash
# Create backup (copies all files + database)
curl -X POST http://localhost:8080/api/v1/backups \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" -d '{"name":"Weekly Backup"}'

# List backups
curl http://localhost:8080/api/v1/backups -H "Authorization: Bearer <token>"

# Restore
curl -X POST http://localhost:8080/api/v1/backups/<id>/restore \
  -H "Authorization: Bearer <token>"

# Schedule automatic backups
curl -X POST http://localhost:8080/api/v1/backups/schedules \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" -d '{"name":"Daily","cron_expression":"0 2 * * *"}'
```

---

## Admin (Requires admin role)
```bash
# List all users
curl http://localhost:8080/api/v1/admin/users -H "Authorization: Bearer <admin_token>"

# Change user role
curl -X PUT http://localhost:8080/api/v1/admin/users/role \
  -H "Authorization: Bearer <admin_token>" \
  -H "Content-Type: application/json" -d '{"user_id":"<id>","role":"admin"}'
# Roles: admin, user, viewer

# Update storage quota (bytes)
curl -X PUT http://localhost:8080/api/v1/admin/users/quota \
  -H "Authorization: Bearer <admin_token>" \
  -H "Content-Type: application/json" -d '{"user_id":"<id>","storage_quota_bytes":53687091200}'

# System stats
curl http://localhost:8080/api/v1/admin/system -H "Authorization: Bearer <admin_token>"
```

---

## Device Agent
Install the Rust device agent on each machine you want to sync:
```bash
cd agent && cargo build --release
./target/release/pcos-agent --server http://your-server:8080 --token <token> --sync-dir ~/pcos-sync
```
The agent will:
- Register itself as a device
- Send periodic heartbeats
- Watch the sync directory for changes
- Upload new/modified files automatically

---

## Web UI
Access the Flutter web interface at `http://localhost:3000` (or `http://localhost` via Caddy).
- **Dashboard**: Storage stats, recent files, device status
- **Files**: Upload, download, preview, create folders, drag-and-drop
- **Search**: Full-text search with instant results
- **Devices**: View connected devices and online status
- **Trash**: Restore or permanently delete files
- **Admin**: User management, role assignment, system stats (admin only)
- **Settings**: Profile, password, MFA, sync, AI, appearance
