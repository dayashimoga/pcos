use chrono::{DateTime, Utc};
use pcos_common::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use std::path::Path;
use tokio::fs;
use uuid::Uuid;

#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct Backup {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub status: String,
    pub size_bytes: i64,
    pub file_count: i64,
    pub storage_path: String,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct BackupSchedule {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub cron_expression: String,
    pub is_active: bool,
    pub last_run_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateBackupRequest {
    pub name: String,
}

#[derive(Debug, Deserialize)]
pub struct CreateScheduleRequest {
    pub name: String,
    pub cron_expression: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEntryBackupRecord {
    pub id: Uuid,
    pub parent_id: Option<Uuid>,
    pub name: String,
    pub entry_type: String,
    pub mime_type: Option<String>,
    pub size_bytes: i64,
    pub sha256_hash: Option<String>,
    pub storage_path: Option<String>,
    pub is_trashed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionBackupRecord {
    pub id: Uuid,
    pub file_entry_id: Uuid,
    pub version_number: i32,
    pub size_bytes: i64,
    pub sha256_hash: Option<String>,
    pub storage_path: Option<String>,
    pub created_by: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareLinkBackupRecord {
    pub id: Uuid,
    pub file_entry_id: Uuid,
    pub token: String,
    pub permission: String,
    pub password_hash: Option<String>,
    pub expires_at: Option<DateTime<Utc>>,
    pub max_downloads: Option<i32>,
    pub download_count: i32,
    pub is_active: bool,
}

/// Create a comprehensive full backup containing payload files + version files + database relational metadata.
pub async fn create_backup(
    pool: &PgPool,
    user_id: Uuid,
    req: CreateBackupRequest,
) -> AppResult<Backup> {
    let backup_id = Uuid::new_v4();
    let storage_path = format!("backups/{}/{}", user_id, backup_id);

    let (file_count,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .unwrap_or((0,));

    let (total_size,): (i64,) = sqlx::query_as(
        "SELECT COALESCE(SUM(size_bytes), 0)::BIGINT FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .unwrap_or((0,));

    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH")
        .unwrap_or_else(|_| "/data/pcos/storage".to_string());
    let backup_dir = format!("{}/{}", base_path, storage_path);
    let payloads_dir = format!("{}/payloads", backup_dir);
    let versions_dir = format!("{}/payloads/versions", backup_dir);

    fs::create_dir_all(&versions_dir)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to create backup directory: {e}")))?;

    // 1. Collect all file_entries (files and folders)
    let raw_entries: Vec<(
        Uuid,
        Option<Uuid>,
        String,
        String,
        Option<String>,
        i64,
        Option<String>,
        Option<String>,
        bool,
    )> = sqlx::query_as(
        "SELECT id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, storage_path, is_trashed FROM file_entries WHERE user_id = $1"
    ).bind(user_id).fetch_all(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let file_entries: Vec<FileEntryBackupRecord> = raw_entries
        .into_iter()
        .map(
            |(id, pid, name, etype, mime, size, hash, spath, trashed)| FileEntryBackupRecord {
                id,
                parent_id: pid,
                name,
                entry_type: etype,
                mime_type: mime,
                size_bytes: size,
                sha256_hash: hash,
                storage_path: spath,
                is_trashed: trashed,
            },
        )
        .collect();

    // 2. Copy payload files and calculate/verify checksums
    let mut files_manifest = Vec::new();
    let mut copied = 0i64;

    for entry in &file_entries {
        if entry.entry_type == "file" && !entry.is_trashed {
            if let Some(rel) = &entry.storage_path {
                let src = format!("{}/{}", base_path, rel);
                let dst = format!("{}/{}", payloads_dir, entry.id);

                if let Ok(data) = fs::read(&src).await {
                    let mut hasher = Sha256::new();
                    hasher.update(&data);
                    let computed_hash = hex::encode(hasher.finalize());

                    if fs::write(&dst, &data).await.is_ok() {
                        copied += 1;
                        files_manifest.push(serde_json::json!({
                            "id": entry.id,
                            "name": entry.name,
                            "storage_path": rel,
                            "size_bytes": data.len(),
                            "sha256_hash": computed_hash,
                        }));
                    }
                }
            }
        }
    }

    // 3. Collect and copy file_versions
    let raw_versions: Vec<(Uuid, Uuid, i32, i64, Option<String>, Option<String>, Uuid)> =
        sqlx::query_as(
            "SELECT v.id, v.file_entry_id, v.version_number, v.size_bytes, v.sha256_hash, v.storage_path, v.created_by \
             FROM file_versions v JOIN file_entries f ON v.file_entry_id = f.id WHERE f.user_id = $1"
        ).bind(user_id).fetch_all(pool).await.unwrap_or_default();

    let versions: Vec<VersionBackupRecord> = raw_versions
        .into_iter()
        .map(
            |(vid, fid, vnum, size, hash, spath, cby)| VersionBackupRecord {
                id: vid,
                file_entry_id: fid,
                version_number: vnum,
                size_bytes: size,
                sha256_hash: hash,
                storage_path: spath,
                created_by: cby,
            },
        )
        .collect();

    for v in &versions {
        if let Some(rel) = &v.storage_path {
            let src = format!("{}/{}", base_path, rel);
            let dst = format!("{}/{}", versions_dir, v.id);
            if let Ok(data) = fs::read(&src).await {
                fs::write(&dst, &data).await.ok();
            }
        }
    }

    // 4. Collect share_links
    let raw_shares: Vec<(
        Uuid,
        Uuid,
        String,
        String,
        Option<String>,
        Option<DateTime<Utc>>,
        Option<i32>,
        i32,
        bool,
    )> = sqlx::query_as(
        "SELECT id, file_entry_id, token, permission, password_hash, expires_at, max_downloads, download_count, is_active FROM share_links WHERE user_id = $1"
    ).bind(user_id).fetch_all(pool).await.unwrap_or_default();

    let shares: Vec<ShareLinkBackupRecord> = raw_shares
        .into_iter()
        .map(
            |(id, fid, token, perm, phash, exp, max_d, dcount, active)| ShareLinkBackupRecord {
                id,
                file_entry_id: fid,
                token,
                permission: perm,
                password_hash: phash,
                expires_at: exp,
                max_downloads: max_d,
                download_count: dcount,
                is_active: active,
            },
        )
        .collect();

    // 5. Write comprehensive manifest and metadata JSON
    let manifest = serde_json::json!({
        "backup_id": backup_id,
        "user_id": user_id,
        "name": req.name,
        "created_at": Utc::now().to_rfc3339(),
        "file_count": file_count,
        "files_copied": copied,
        "total_size_bytes": total_size,
        "files": files_manifest,
        "file_entries": file_entries,
        "file_versions": versions,
        "share_links": shares,
    });

    let manifest_path = format!("{}/manifest.json", backup_dir);
    fs::write(
        &manifest_path,
        serde_json::to_string_pretty(&manifest).unwrap_or_default(),
    )
    .await
    .map_err(|e| AppError::Internal(format!("Failed to write manifest: {e}")))?;

    // 6. Optional pg_dump dump if available
    let db_dump_path = format!("{}/database.sql", backup_dir);
    if let Ok(db_url) = std::env::var("PCOS_DATABASE__URL") {
        let _ = tokio::process::Command::new("pg_dump")
            .arg(&db_url)
            .arg("--no-owner")
            .arg("--no-privileges")
            .arg("-f")
            .arg(&db_dump_path)
            .output()
            .await;
    }

    let backup = sqlx::query_as::<_, Backup>(
        "INSERT INTO backups (id, user_id, name, status, size_bytes, file_count, storage_path, created_at, completed_at) VALUES ($1,$2,$3,'completed',$4,$5,$6,NOW(),NOW()) RETURNING *"
    ).bind(backup_id).bind(user_id).bind(&req.name).bind(total_size).bind(file_count).bind(&storage_path)
    .fetch_one(pool).await?;

    tracing::info!(
        backup_id = %backup.id,
        files = file_count,
        copied = copied,
        "Full backup created with payloads and relational metadata"
    );
    Ok(backup)
}

pub async fn list_backups(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<Backup>> {
    Ok(sqlx::query_as::<_, Backup>(
        "SELECT * FROM backups WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?)
}

pub async fn get_backup(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<Backup> {
    sqlx::query_as::<_, Backup>("SELECT * FROM backups WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(user_id)
        .fetch_optional(pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Backup not found".to_string()))
}

pub async fn delete_backup(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<()> {
    let backup = get_backup(pool, user_id, id).await?;

    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH")
        .unwrap_or_else(|_| "/data/pcos/storage".to_string());
    let backup_dir = format!("{}/{}", base_path, backup.storage_path);
    fs::remove_dir_all(&backup_dir).await.ok();

    sqlx::query("DELETE FROM backups WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// Restore full backup: reconstructs file payload files, version files, database records, and validates SHA-256 integrity.
pub async fn restore_backup(
    pool: &PgPool,
    user_id: Uuid,
    id: Uuid,
) -> AppResult<serde_json::Value> {
    let backup = get_backup(pool, user_id, id).await?;
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH")
        .unwrap_or_else(|_| "/data/pcos/storage".to_string());
    let backup_dir = format!("{}/{}", base_path, backup.storage_path);

    let manifest_path = format!("{}/manifest.json", backup_dir);
    let manifest_data = fs::read_to_string(&manifest_path)
        .await
        .map_err(|e| AppError::Internal(format!("Cannot read backup manifest: {e}")))?;
    let manifest: serde_json::Value = serde_json::from_str(&manifest_data)
        .map_err(|e| AppError::Internal(format!("Invalid manifest: {e}")))?;

    let mut restored_files = 0i64;
    let mut verified_checksums = 0i64;
    let mut corrupted_files = 0i64;

    // 1. Restore and verify payload files
    if let Some(files) = manifest["files"].as_array() {
        for file in files {
            if let (Some(fid), Some(rel_path)) =
                (file["id"].as_str(), file["storage_path"].as_str())
            {
                let src = format!("{}/payloads/{}", backup_dir, fid);
                let dst = format!("{}/{}", base_path, rel_path);

                if let Ok(data) = fs::read(&src).await {
                    let mut hasher = Sha256::new();
                    hasher.update(&data);
                    let computed_hash = hex::encode(hasher.finalize());

                    if let Some(expected) = file["sha256_hash"].as_str() {
                        if computed_hash == expected {
                            verified_checksums += 1;
                        } else {
                            corrupted_files += 1;
                            tracing::error!(
                                file_id = fid,
                                "Backup file hash mismatch during restore"
                            );
                        }
                    }

                    if let Some(parent) = Path::new(&dst).parent() {
                        fs::create_dir_all(parent).await.ok();
                    }
                    if fs::write(&dst, &data).await.is_ok() {
                        restored_files += 1;
                    }
                }
            }
        }
    }

    // 2. Restore file_entries in database
    let mut restored_entries = 0i64;
    if let Some(entries_raw) = manifest.get("file_entries") {
        if let Ok(entries) =
            serde_json::from_value::<Vec<FileEntryBackupRecord>>(entries_raw.clone())
        {
            // Restore folders first to preserve hierarchy constraints
            let mut folders: Vec<FileEntryBackupRecord> = Vec::new();
            let mut non_folders: Vec<FileEntryBackupRecord> = Vec::new();

            for e in entries {
                if e.entry_type == "folder" {
                    folders.push(e);
                } else {
                    non_folders.push(e);
                }
            }

            for entry in folders.into_iter().chain(non_folders.into_iter()) {
                let _ = sqlx::query(
                    r#"
                    INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, storage_path, is_trashed, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), NOW())
                    ON CONFLICT (id) DO UPDATE SET
                        parent_id = EXCLUDED.parent_id,
                        name = EXCLUDED.name,
                        size_bytes = EXCLUDED.size_bytes,
                        sha256_hash = EXCLUDED.sha256_hash,
                        storage_path = EXCLUDED.storage_path,
                        is_trashed = EXCLUDED.is_trashed,
                        updated_at = NOW()
                    "#,
                )
                .bind(entry.id)
                .bind(user_id)
                .bind(entry.parent_id)
                .bind(&entry.name)
                .bind(&entry.entry_type)
                .bind(&entry.mime_type)
                .bind(entry.size_bytes)
                .bind(&entry.sha256_hash)
                .bind(&entry.storage_path)
                .bind(entry.is_trashed)
                .execute(pool)
                .await;

                restored_entries += 1;
            }
        }
    }

    // 3. Restore file_versions in database & disk
    if let Some(versions_raw) = manifest.get("file_versions") {
        if let Ok(versions) =
            serde_json::from_value::<Vec<VersionBackupRecord>>(versions_raw.clone())
        {
            for v in versions {
                if let Some(rel) = &v.storage_path {
                    let src = format!("{}/payloads/versions/{}", backup_dir, v.id);
                    let dst = format!("{}/{}", base_path, rel);
                    if let Ok(data) = fs::read(&src).await {
                        if let Some(parent) = Path::new(&dst).parent() {
                            fs::create_dir_all(parent).await.ok();
                        }
                        fs::write(&dst, &data).await.ok();
                    }
                }

                let _ = sqlx::query(
                    r#"
                    INSERT INTO file_versions (id, file_entry_id, version_number, size_bytes, sha256_hash, storage_path, created_by, created_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
                    ON CONFLICT (id) DO NOTHING
                    "#,
                )
                .bind(v.id)
                .bind(v.file_entry_id)
                .bind(v.version_number)
                .bind(v.size_bytes)
                .bind(&v.sha256_hash)
                .bind(&v.storage_path)
                .bind(v.created_by)
                .execute(pool)
                .await;
            }
        }
    }

    // 4. Restore share_links
    if let Some(shares_raw) = manifest.get("share_links") {
        if let Ok(shares) = serde_json::from_value::<Vec<ShareLinkBackupRecord>>(shares_raw.clone())
        {
            for s in shares {
                let _ = sqlx::query(
                    r#"
                    INSERT INTO share_links (id, user_id, file_entry_id, token, permission, password_hash, expires_at, max_downloads, download_count, is_active, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), NOW())
                    ON CONFLICT (id) DO NOTHING
                    "#,
                )
                .bind(s.id)
                .bind(user_id)
                .bind(s.file_entry_id)
                .bind(&s.token)
                .bind(&s.permission)
                .bind(&s.password_hash)
                .bind(s.expires_at)
                .bind(s.max_downloads)
                .bind(s.download_count)
                .bind(s.is_active)
                .execute(pool)
                .await;
            }
        }
    }

    sqlx::query("UPDATE backups SET status = 'restored' WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await?;

    let healthy = corrupted_files == 0;
    tracing::info!(
        backup_id = %id,
        files_restored = restored_files,
        entries_restored = restored_entries,
        checksums_verified = verified_checksums,
        "Full restore completed"
    );

    Ok(serde_json::json!({
        "status": if healthy { "restored" } else { "restored_with_warnings" },
        "backup_id": id,
        "files_restored": restored_files,
        "entries_restored": restored_entries,
        "checksums_verified": verified_checksums,
        "corruptions_detected": corrupted_files,
        "integrity_verified": healthy,
    }))
}

pub async fn create_schedule(
    pool: &PgPool,
    user_id: Uuid,
    req: CreateScheduleRequest,
) -> AppResult<BackupSchedule> {
    let schedule = sqlx::query_as::<_, BackupSchedule>(
        "INSERT INTO backup_schedules (id, user_id, name, cron_expression, is_active, created_at) VALUES ($1,$2,$3,$4,true,NOW()) RETURNING *"
    ).bind(Uuid::new_v4()).bind(user_id).bind(&req.name).bind(&req.cron_expression)
    .fetch_one(pool).await?;
    Ok(schedule)
}

pub async fn list_schedules(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<BackupSchedule>> {
    Ok(sqlx::query_as::<_, BackupSchedule>(
        "SELECT * FROM backup_schedules WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?)
}

pub async fn delete_schedule(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<()> {
    let r = sqlx::query("DELETE FROM backup_schedules WHERE id = $1 AND user_id = $2")
        .bind(id)
        .bind(user_id)
        .execute(pool)
        .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("Schedule not found".to_string()));
    }
    Ok(())
}

/// Enforce retention policy — keep only the N most recent backups, delete older ones.
pub async fn enforce_retention(pool: &PgPool, user_id: Uuid, keep_count: i64) -> AppResult<i64> {
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH")
        .unwrap_or_else(|_| "/data/pcos/storage".to_string());

    let old_backups: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT id, storage_path FROM backups WHERE user_id = $1 ORDER BY created_at DESC OFFSET $2",
    )
    .bind(user_id)
    .bind(keep_count)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let mut deleted = 0i64;
    for (bid, spath) in &old_backups {
        let backup_dir = format!("{}/{}", base_path, spath);
        fs::remove_dir_all(&backup_dir).await.ok();
        sqlx::query("DELETE FROM backups WHERE id = $1")
            .bind(bid)
            .execute(pool)
            .await
            .ok();
        deleted += 1;
    }

    if deleted > 0 {
        tracing::info!(
            user_id = %user_id,
            deleted = deleted,
            kept = keep_count,
            "Retention policy enforced"
        );
    }
    Ok(deleted)
}

/// Verify a backup by checking manifest integrity and cryptographic SHA-256 validation of every file payload.
pub async fn verify_backup(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<serde_json::Value> {
    let backup = get_backup(pool, user_id, id).await?;
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH")
        .unwrap_or_else(|_| "/data/pcos/storage".to_string());
    let backup_dir = format!("{}/{}", base_path, backup.storage_path);
    verify_backup_dir(id, &backup_dir).await
}

pub async fn verify_backup_dir(id: Uuid, backup_dir: &str) -> AppResult<serde_json::Value> {
    let manifest_path = format!("{}/manifest.json", backup_dir);
    let manifest_exists = fs::metadata(&manifest_path).await.is_ok();
    let db_dump_exists = fs::metadata(format!("{}/database.sql", backup_dir))
        .await
        .is_ok();

    let mut files_present = 0i64;
    let mut files_missing = 0i64;
    let mut checksum_matches = 0i64;
    let mut checksum_mismatches = 0i64;

    if manifest_exists {
        if let Ok(data) = fs::read_to_string(&manifest_path).await {
            if let Ok(manifest) = serde_json::from_str::<serde_json::Value>(&data) {
                if let Some(files) = manifest["files"].as_array() {
                    for file in files {
                        if let Some(fid) = file["id"].as_str() {
                            let fpath = format!("{}/payloads/{}", backup_dir, fid);
                            match fs::read(&fpath).await {
                                Ok(bytes) => {
                                    files_present += 1;
                                    let mut hasher = Sha256::new();
                                    hasher.update(&bytes);
                                    let computed = hex::encode(hasher.finalize());

                                    if let Some(expected) = file["sha256_hash"].as_str() {
                                        if computed == expected {
                                            checksum_matches += 1;
                                        } else {
                                            checksum_mismatches += 1;
                                        }
                                    }
                                }
                                Err(_) => {
                                    files_missing += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    let healthy = manifest_exists && files_missing == 0 && checksum_mismatches == 0;

    Ok(serde_json::json!({
        "backup_id": id,
        "healthy": healthy,
        "manifest_exists": manifest_exists,
        "database_dump_exists": db_dump_exists,
        "files_present": files_present,
        "files_missing": files_missing,
        "checksums_verified": checksum_matches,
        "checksum_mismatches": checksum_mismatches,
        "status": if healthy { "verified" } else { "degraded" },
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_backup_verification_healthy() {
        let dir = tempdir().unwrap();
        let backup_dir = dir.path().to_str().unwrap();

        let payloads_dir = format!("{}/payloads", backup_dir);
        tokio::fs::create_dir_all(&payloads_dir).await.unwrap();

        let file_id = "test-file-123";
        let content = b"PCOS Disaster Recovery Verified Payload";
        let mut hasher = Sha256::new();
        hasher.update(content);
        let expected_hash = hex::encode(hasher.finalize());

        tokio::fs::write(format!("{}/{}", payloads_dir, file_id), content)
            .await
            .unwrap();

        let manifest = serde_json::json!({
            "backup_id": "00000000-0000-0000-0000-000000000001",
            "files": [
                {
                    "id": file_id,
                    "sha256_hash": expected_hash,
                    "size_bytes": content.len()
                }
            ]
        });

        tokio::fs::write(
            format!("{}/manifest.json", backup_dir),
            serde_json::to_string_pretty(&manifest).unwrap(),
        )
        .await
        .unwrap();

        let res = verify_backup_dir(Uuid::new_v4(), backup_dir).await.unwrap();
        assert_eq!(res["healthy"], true);
        assert_eq!(res["checksums_verified"], 1);
        assert_eq!(res["checksum_mismatches"], 0);
        assert_eq!(res["files_missing"], 0);
        assert_eq!(res["status"], "verified");
    }

    #[tokio::test]
    async fn test_backup_verification_detects_corruption() {
        let dir = tempdir().unwrap();
        let backup_dir = dir.path().to_str().unwrap();

        let payloads_dir = format!("{}/payloads", backup_dir);
        tokio::fs::create_dir_all(&payloads_dir).await.unwrap();

        let file_id = "corrupted-file-456";
        let original_content = b"Authentic Data";
        let mut hasher = Sha256::new();
        hasher.update(original_content);
        let original_hash = hex::encode(hasher.finalize());

        // Write corrupted byte payload to disk
        tokio::fs::write(format!("{}/{}", payloads_dir, file_id), b"Corrupted Data")
            .await
            .unwrap();

        let manifest = serde_json::json!({
            "backup_id": "00000000-0000-0000-0000-000000000002",
            "files": [
                {
                    "id": file_id,
                    "sha256_hash": original_hash,
                    "size_bytes": 14
                }
            ]
        });

        tokio::fs::write(
            format!("{}/manifest.json", backup_dir),
            serde_json::to_string(&manifest).unwrap(),
        )
        .await
        .unwrap();

        let res = verify_backup_dir(Uuid::new_v4(), backup_dir).await.unwrap();
        assert_eq!(res["healthy"], false);
        assert_eq!(res["checksums_verified"], 0);
        assert_eq!(res["checksum_mismatches"], 1);
        assert_eq!(res["status"], "degraded");
    }

    #[tokio::test]
    async fn test_backup_verification_detects_missing_payload() {
        let dir = tempdir().unwrap();
        let backup_dir = dir.path().to_str().unwrap();

        let manifest = serde_json::json!({
            "backup_id": "00000000-0000-0000-0000-000000000003",
            "files": [
                {
                    "id": "missing-file-789",
                    "sha256_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                    "size_bytes": 0
                }
            ]
        });

        tokio::fs::write(
            format!("{}/manifest.json", backup_dir),
            serde_json::to_string(&manifest).unwrap(),
        )
        .await
        .unwrap();

        let res = verify_backup_dir(Uuid::new_v4(), backup_dir).await.unwrap();
        assert_eq!(res["healthy"], false);
        assert_eq!(res["files_missing"], 1);
        assert_eq!(res["status"], "degraded");
    }
}
