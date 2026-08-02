# PCOS Database Design

## Schema Diagram

```
users (1) ──→ (N) refresh_tokens
  │ ──→ (N) devices
  │ ──→ (N) audit_log
  │ ──→ (N) file_entries ──→ (N) file_tags
  │                       ──→ (N) share_links
  │                       ──→ (N) sync_states
  │                       ──→ (N) file_versions
  │ ──→ (N) sync_folders
  │ ──→ (N) notifications
  │ ──→ (N) jobs
  │ ──→ (N) backups
  │ ──→ (N) backup_schedules
```

## Tables

### users
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| email | VARCHAR(255) | UNIQUE, NOT NULL |
| display_name | VARCHAR(100) | NOT NULL |
| password_hash | TEXT | Argon2id PHC format |
| avatar_url | TEXT | Nullable |
| role | VARCHAR(20) | Default 'user' (admin/user/viewer) |
| totp_secret | TEXT | Nullable, Base32 TOTP secret |
| totp_enabled | BOOLEAN | Default false |
| totp_verified_at | TIMESTAMPTZ | Nullable |
| storage_quota_bytes | BIGINT | Default 10 GB |
| is_active | BOOLEAN | Default true |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

### refresh_tokens
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id | UUID FK→users | CASCADE |
| token_hash | VARCHAR(255) | SHA-256 hash |
| expires_at | TIMESTAMPTZ | |
| revoked | BOOLEAN | Default false |
| created_at | TIMESTAMPTZ | |

**Indexes**: user_id, token_hash (unique, where not revoked)

### devices
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id | UUID FK→users | CASCADE |
| name | VARCHAR(255) | |
| device_type | VARCHAR(50) | desktop/phone/tablet/server/nas |
| os | VARCHAR(50) | |
| os_version | VARCHAR(50) | |
| agent_version | VARCHAR(50) | |
| is_online | BOOLEAN | |
| last_seen_at | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | |

### audit_log
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id | UUID FK→users | CASCADE |
| action | VARCHAR(100) | e.g. user.registered, auth.login |
| details | TEXT | |
| ip_address | VARCHAR(45) | Nullable |
| created_at | TIMESTAMPTZ | |

### file_entries
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id | UUID FK→users | CASCADE |
| parent_id | UUID FK→file_entries | Self-referential, nullable |
| name | VARCHAR(255) | |
| entry_type | VARCHAR(10) | 'file' or 'folder' |
| mime_type | VARCHAR(255) | Nullable |
| size_bytes | BIGINT | Default 0 |
| sha256_hash | VARCHAR(64) | Nullable |
| storage_path | TEXT | Relative to base_path |
| is_trashed | BOOLEAN | Soft delete |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

**Indexes**: (user_id, parent_id) where not trashed, user_id where trashed, sha256_hash

### file_versions
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| file_entry_id | UUID FK→file_entries | CASCADE |
| version_number | INTEGER | UNIQUE per file |
| size_bytes | BIGINT | |
| sha256_hash | VARCHAR(64) | Nullable |
| storage_path | TEXT | Previous version's storage |
| created_by | UUID FK→users | Who created this version |
| created_at | TIMESTAMPTZ | |

**Indexes**: file_entry_id, UNIQUE(file_entry_id, version_number)

### share_links
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id | UUID FK→users | CASCADE |
| file_entry_id | UUID FK→file_entries | CASCADE |
| token | VARCHAR(64) | UNIQUE |
| permission | VARCHAR(20) | 'view' or 'download' |
| password_hash | TEXT | Nullable (Argon2id) |
| expires_at | TIMESTAMPTZ | Nullable |
| max_downloads | INTEGER | Nullable |
| download_count | INTEGER | Default 0 |
| is_active | BOOLEAN | Default true |
| created_at | TIMESTAMPTZ | |
| updated_at | TIMESTAMPTZ | |

### sync_states
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id | UUID FK | |
| device_id | UUID FK | |
| file_entry_id | UUID FK | |
| version | BIGINT | Default 1 |
| status | VARCHAR(20) | synced/pending/conflict |
| last_synced_at | TIMESTAMPTZ | |
| UNIQUE | (device_id, file_entry_id) | |

### sync_folders
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id / device_id | UUID FK | |
| local_path | TEXT | |
| remote_folder_id | UUID FK | Nullable |
| is_active | BOOLEAN | |

### notifications
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | gen_random_uuid() |
| user_id | UUID FK | |
| title | VARCHAR(255) | |
| body | TEXT | |
| is_read | BOOLEAN | Default false |
| created_at | TIMESTAMPTZ | |

### jobs
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id | UUID FK | |
| job_type | VARCHAR(50) | |
| status | VARCHAR(20) | queued/running/completed/failed |
| details / result | TEXT | |

### backups / backup_schedules / file_tags
See migration files for complete schema.

## Migration Order
1. `20240101000001_users.sql`
2. `20240101000002_refresh_tokens.sql`
3. `20240101000003_devices.sql`
4. `20240101000004_audit_log.sql`
5. `20240101000005_file_entries.sql`
6. `20240101000006_share_links.sql`
7. `20240101000007_remaining_tables.sql`
8. `20240101000008_versioning_rbac_mfa.sql`
9. `20240101000009_push_and_extraction.sql`

---

## New Tables (v0.6.0)

### push_subscriptions
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| user_id | UUID FK | → users(id) CASCADE |
| endpoint | TEXT | UNIQUE, Web Push endpoint URL |
| p256dh_key | TEXT | ECDH public key |
| auth_key | TEXT | Auth secret |
| user_agent | TEXT | Nullable |
| created_at | TIMESTAMPTZ | |

**Indexes**: `idx_push_subs_user(user_id)`, `idx_push_subs_endpoint(endpoint)`

### text_extractions
| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| file_id | UUID FK | → file_entries(id) CASCADE |
| extracted_text | TEXT | OCR/parsed text content |
| method | VARCHAR(50) | plaintext/pdf-parse/tesseract-ocr |
| confidence | REAL | 0.0–1.0 |
| page_count | INT | Nullable |
| created_at | TIMESTAMPTZ | |

**Indexes**: `idx_text_extract_file(file_id)`, GIN full-text index on `extracted_text`

**Total: 16 tables, 9 migrations**
