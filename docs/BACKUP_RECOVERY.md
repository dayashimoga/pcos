# PCOS Backup & Disaster Recovery (DR) Architecture

## 1. Ground Principle: Beyond pg_dump
In personal cloud operating systems, `pg_dump` alone does **not** constitute a backup:
- A database dump contains metadata rows but zero actual binary payloads (documents, videos, images).
- Restoring a DB dump without files results in broken dangling references and 404 errors.
- Conversely, copying disk files without DB state loses folder hierarchies, permissions, tags, version histories, and share links.

PCOS provides a **Unified Full Disaster Recovery Engine** in the `pcos-backup` crate that archives:
1. All physical payload files (`payloads/{file_id}`)
2. All historical version payloads
3. Relational state from `file_entries`, `file_versions`, and `share_links`
4. Cryptographic SHA-256 hashes of every file in `manifest.json`
5. An optional PostgreSQL schema/data dump (`database.sql`)

---

## 2. Backup Archive Structure
When a full backup is created (`POST /api/v1/backups`), PCOS generates the following on the backup storage target:

```
backups/{backup_id}/
├── manifest.json         # Full catalog with SHA-256 checksums, metadata, and ACLs
├── database.sql          # (Optional) PostgreSQL SQL dump
└── payloads/
    ├── {file_id_1}       # Byte-for-byte binary content of active files
    ├── {file_id_2}
    └── {version_file_id} # Historic version payloads
```

### Manifest Schema (`manifest.json`)
```json
{
  "backup_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "user_id": "11111111-2222-3333-4444-555555555555",
  "name": "Production Backup 2026-10-01",
  "created_at": "2026-10-01T22:30:00Z",
  "file_count": 1420,
  "files_copied": 1420,
  "total_size_bytes": 10737418240,
  "files": [
    {
      "id": "file_uuid",
      "sha256_hash": "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e",
      "size_bytes": 1048576,
      "storage_path": "active_path"
    }
  ],
  "file_entries": [ ... ],
  "file_versions": [ ... ],
  "share_links": [ ... ]
}
```

---

## 3. Cryptographic Verification Engine
PCOS exposes `GET /api/v1/backups/:id/verify`, which evaluates:
1. **Manifest Existence**: Validates that `manifest.json` is intact and parseable.
2. **Payload Completeness**: Verifies that every file listed in the manifest exists on the backup disk (`files_missing == 0`).
3. **Cryptographic SHA-256 Match**: Reads each payload, calculates its SHA-256 hash using streaming crypto primitives, and asserts equality against the recorded hash (`checksum_mismatches == 0`).
4. **Health Status**: Returns `"status": "verified"` and `"healthy": true` only if all checksums match with zero missing files. If a single byte has been corrupted, it marks the backup `"degraded"`.

---

## 4. Disaster Recovery & Clean Restoration
To recover from total server destruction:
1. Deploy a clean PCOS instance (`./spinup.ps1` or `./spinup.sh`).
2. Attach the external backup volume.
3. Trigger restoration via API: `POST /api/v1/backups/:id/restore`.
4. The restore service:
   - Reads `manifest.json`.
   - Restores each payload back to active storage directory.
   - Re-inserts all `file_entries` preserving original folder hierarchies, parent references, sizes, and MIME types.
   - Re-inserts `file_versions` and `share_links`.
   - Re-verifies SHA-256 hashes of restored files on active disk.
   - Updates backup status to `'restored'`.

---

## 5. Retention Policies & Automated Scheduling
- **Retention**: `POST /api/v1/backups/retention` enforces keep-counts (e.g. keep latest 7 daily backups, delete older payloads and records).
- **Scheduling**: `POST /api/v1/backups/schedules` configures standard cron expressions (e.g. `0 2 * * *` for 2:00 AM daily full backups).
