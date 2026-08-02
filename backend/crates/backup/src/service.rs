use pcos_common::error::{AppError, AppResult};
use sqlx::PgPool;
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct Backup {
    pub id: Uuid, pub user_id: Uuid, pub name: String, pub status: String,
    pub size_bytes: i64, pub file_count: i64, pub storage_path: String,
    pub created_at: DateTime<Utc>, pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct BackupSchedule {
    pub id: Uuid, pub user_id: Uuid, pub name: String, pub cron_expression: String,
    pub is_active: bool, pub last_run_at: Option<DateTime<Utc>>, pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct CreateBackupRequest { pub name: String }

#[derive(Debug, Deserialize)]
pub struct CreateScheduleRequest { pub name: String, pub cron_expression: String }

pub async fn create_backup(pool: &PgPool, user_id: Uuid, req: CreateBackupRequest) -> AppResult<Backup> {
    let backup_id = Uuid::new_v4();
    let storage_path = format!("backups/{}/{}", user_id, backup_id);

    // Count user's files
    let (file_count,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false")
        .bind(user_id).fetch_one(pool).await.unwrap_or((0,));
    let (total_size,): (Option<i64>,) = sqlx::query_as("SELECT SUM(size_bytes) FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false")
        .bind(user_id).fetch_one(pool).await.unwrap_or((None,));

    // Get base storage path from environment
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or_else(|_| "/data/pcos/storage".to_string());
    let backup_dir = format!("{}/{}", base_path, storage_path);
    tokio::fs::create_dir_all(&backup_dir).await
        .map_err(|e| AppError::Internal(format!("Failed to create backup directory: {e}")))?;

    // Collect file entries with storage paths
    let files: Vec<(Uuid, String, Option<String>, i64)> = sqlx::query_as(
        "SELECT id, name, storage_path, size_bytes FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false AND storage_path IS NOT NULL"
    ).bind(user_id).fetch_all(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    // Copy each file to backup directory
    let mut copied = 0i64;
    for (file_id, _name, storage_rel, _size) in &files {
        if let Some(rel) = storage_rel {
            let src = format!("{}/{}", base_path, rel);
            let dst = format!("{}/{}", backup_dir, file_id);
            match tokio::fs::copy(&src, &dst).await {
                Ok(_) => copied += 1,
                Err(e) => tracing::warn!(file_id = %file_id, error = %e, "Failed to copy file to backup"),
            }
        }
    }

    // Write manifest JSON with file metadata
    let manifest = serde_json::json!({
        "backup_id": backup_id,
        "user_id": user_id,
        "created_at": chrono::Utc::now().to_rfc3339(),
        "file_count": file_count,
        "files_copied": copied,
        "total_size_bytes": total_size.unwrap_or(0),
        "files": files.iter().map(|(id, name, path, size)| {
            serde_json::json!({"id": id, "name": name, "storage_path": path, "size_bytes": size})
        }).collect::<Vec<_>>(),
    });
    let manifest_path = format!("{}/manifest.json", backup_dir);
    tokio::fs::write(&manifest_path, serde_json::to_string_pretty(&manifest).unwrap_or_default()).await
        .map_err(|e| AppError::Internal(format!("Failed to write manifest: {e}")))?;

    // Try pg_dump for database backup (optional — may not have pg_dump binary)
    let db_dump_path = format!("{}/database.sql", backup_dir);
    if let Ok(db_url) = std::env::var("PCOS_DATABASE__URL") {
        match tokio::process::Command::new("pg_dump")
            .arg(&db_url)
            .arg("--no-owner")
            .arg("--no-privileges")
            .arg("-f").arg(&db_dump_path)
            .output().await
        {
            Ok(output) if output.status.success() => {
                tracing::info!(backup_id = %backup_id, "Database dump completed");
            }
            _ => {
                tracing::warn!(backup_id = %backup_id, "pg_dump not available, skipping database backup");
            }
        }
    }

    let backup = sqlx::query_as::<_, Backup>(
        "INSERT INTO backups (id, user_id, name, status, size_bytes, file_count, storage_path, created_at, completed_at) VALUES ($1,$2,$3,'completed',$4,$5,$6,NOW(),NOW()) RETURNING *"
    ).bind(backup_id).bind(user_id).bind(&req.name).bind(total_size.unwrap_or(0)).bind(file_count).bind(&storage_path)
    .fetch_one(pool).await?;

    tracing::info!(backup_id = %backup.id, files = file_count, copied = copied, "Backup created with file copy");
    Ok(backup)
}

pub async fn list_backups(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<Backup>> {
    Ok(sqlx::query_as::<_, Backup>("SELECT * FROM backups WHERE user_id = $1 ORDER BY created_at DESC")
        .bind(user_id).fetch_all(pool).await?)
}

pub async fn get_backup(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<Backup> {
    sqlx::query_as::<_, Backup>("SELECT * FROM backups WHERE id = $1 AND user_id = $2")
        .bind(id).bind(user_id).fetch_optional(pool).await?
        .ok_or_else(|| AppError::NotFound("Backup not found".to_string()))
}

pub async fn delete_backup(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<()> {
    let backup = get_backup(pool, user_id, id).await?;

    // Delete backup files from disk
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or_else(|_| "/data/pcos/storage".to_string());
    let backup_dir = format!("{}/{}", base_path, backup.storage_path);
    if let Err(e) = tokio::fs::remove_dir_all(&backup_dir).await {
        tracing::warn!(error = %e, "Failed to remove backup directory (may not exist)");
    }

    sqlx::query("DELETE FROM backups WHERE id = $1 AND user_id = $2").bind(id).bind(user_id).execute(pool).await?;
    Ok(())
}

pub async fn restore_backup(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<String> {
    let backup = get_backup(pool, user_id, id).await?;
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or_else(|_| "/data/pcos/storage".to_string());
    let backup_dir = format!("{}/{}", base_path, backup.storage_path);

    // Read manifest to know which files to restore
    let manifest_path = format!("{}/manifest.json", backup_dir);
    let manifest_data = tokio::fs::read_to_string(&manifest_path).await
        .map_err(|e| AppError::Internal(format!("Cannot read backup manifest: {e}")))?;
    let manifest: serde_json::Value = serde_json::from_str(&manifest_data)
        .map_err(|e| AppError::Internal(format!("Invalid manifest: {e}")))?;

    // Copy backup files back to active storage
    let mut restored = 0i64;
    if let Some(files) = manifest["files"].as_array() {
        for file in files {
            if let (Some(id), Some(path)) = (file["id"].as_str(), file["storage_path"].as_str()) {
                let src = format!("{}/{}", backup_dir, id);
                let dst = format!("{}/{}", base_path, path);
                if let Some(parent) = std::path::Path::new(&dst).parent() {
                    tokio::fs::create_dir_all(parent).await.ok();
                }
                match tokio::fs::copy(&src, &dst).await {
                    Ok(_) => restored += 1,
                    Err(e) => tracing::warn!(file_id = id, error = %e, "Failed to restore file"),
                }
            }
        }
    }

    sqlx::query("UPDATE backups SET status = 'restored' WHERE id = $1").bind(id).execute(pool).await?;
    tracing::info!(backup_id = %id, restored = restored, "Backup restore completed");
    Ok(format!("Restored {} files", restored))
}

pub async fn create_schedule(pool: &PgPool, user_id: Uuid, req: CreateScheduleRequest) -> AppResult<BackupSchedule> {
    let schedule = sqlx::query_as::<_, BackupSchedule>(
        "INSERT INTO backup_schedules (id, user_id, name, cron_expression, is_active, created_at) VALUES ($1,$2,$3,$4,true,NOW()) RETURNING *"
    ).bind(Uuid::new_v4()).bind(user_id).bind(&req.name).bind(&req.cron_expression)
    .fetch_one(pool).await?;
    Ok(schedule)
}

pub async fn list_schedules(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<BackupSchedule>> {
    Ok(sqlx::query_as::<_, BackupSchedule>("SELECT * FROM backup_schedules WHERE user_id = $1 ORDER BY created_at DESC")
        .bind(user_id).fetch_all(pool).await?)
}

pub async fn delete_schedule(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<()> {
    let r = sqlx::query("DELETE FROM backup_schedules WHERE id = $1 AND user_id = $2").bind(id).bind(user_id).execute(pool).await?;
    if r.rows_affected() == 0 { return Err(AppError::NotFound("Schedule not found".to_string())); }
    Ok(())
}

/// Enforce retention policy — keep only the N most recent backups, delete older ones.
pub async fn enforce_retention(pool: &PgPool, user_id: Uuid, keep_count: i64) -> AppResult<i64> {
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or_else(|_| "/data/pcos/storage".to_string());

    let old_backups: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT id, storage_path FROM backups WHERE user_id = $1 ORDER BY created_at DESC OFFSET $2"
    ).bind(user_id).bind(keep_count).fetch_all(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let mut deleted = 0i64;
    for (bid, spath) in &old_backups {
        let backup_dir = format!("{}/{}", base_path, spath);
        tokio::fs::remove_dir_all(&backup_dir).await.ok();
        sqlx::query("DELETE FROM backups WHERE id = $1").bind(bid).execute(pool).await.ok();
        deleted += 1;
    }

    if deleted > 0 {
        tracing::info!(user_id = %user_id, deleted = deleted, kept = keep_count, "Retention policy enforced");
    }
    Ok(deleted)
}

/// Verify a backup by checking manifest integrity and file existence.
pub async fn verify_backup(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<serde_json::Value> {
    let backup = get_backup(pool, user_id, id).await?;
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or_else(|_| "/data/pcos/storage".to_string());
    let backup_dir = format!("{}/{}", base_path, backup.storage_path);

    let manifest_path = format!("{}/manifest.json", backup_dir);
    let manifest_exists = tokio::fs::metadata(&manifest_path).await.is_ok();
    let db_dump_exists = tokio::fs::metadata(format!("{}/database.sql", backup_dir)).await.is_ok();

    let mut files_present = 0i64;
    let mut files_missing = 0i64;

    if manifest_exists {
        if let Ok(data) = tokio::fs::read_to_string(&manifest_path).await {
            if let Ok(manifest) = serde_json::from_str::<serde_json::Value>(&data) {
                if let Some(files) = manifest["files"].as_array() {
                    for file in files {
                        if let Some(fid) = file["id"].as_str() {
                            let fpath = format!("{}/{}", backup_dir, fid);
                            if tokio::fs::metadata(&fpath).await.is_ok() {
                                files_present += 1;
                            } else {
                                files_missing += 1;
                            }
                        }
                    }
                }
            }
        }
    }

    let healthy = manifest_exists && files_missing == 0;

    Ok(serde_json::json!({
        "backup_id": id,
        "healthy": healthy,
        "manifest_exists": manifest_exists,
        "database_dump_exists": db_dump_exists,
        "files_present": files_present,
        "files_missing": files_missing,
        "status": if healthy { "verified" } else { "degraded" },
    }))
}
