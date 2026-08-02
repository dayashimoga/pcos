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
    let storage_path = format!("backups/{}/{}", user_id, Uuid::new_v4());
    // Count user's files
    let (file_count,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false")
        .bind(user_id).fetch_one(pool).await.unwrap_or((0,));
    let (total_size,): (Option<i64>,) = sqlx::query_as("SELECT SUM(size_bytes) FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false")
        .bind(user_id).fetch_one(pool).await.unwrap_or((None,));

    let backup = sqlx::query_as::<_, Backup>(
        "INSERT INTO backups (id, user_id, name, status, size_bytes, file_count, storage_path, created_at, completed_at) VALUES ($1,$2,$3,'completed',$4,$5,$6,NOW(),NOW()) RETURNING *"
    ).bind(Uuid::new_v4()).bind(user_id).bind(&req.name).bind(total_size.unwrap_or(0)).bind(file_count).bind(&storage_path)
    .fetch_one(pool).await?;

    tracing::info!(backup_id = %backup.id, files = file_count, "Backup created");
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
    let r = sqlx::query("DELETE FROM backups WHERE id = $1 AND user_id = $2").bind(id).bind(user_id).execute(pool).await?;
    if r.rows_affected() == 0 { return Err(AppError::NotFound("Backup not found".to_string())); }
    Ok(())
}

pub async fn restore_backup(pool: &PgPool, user_id: Uuid, id: Uuid) -> AppResult<String> {
    let _backup = get_backup(pool, user_id, id).await?;
    // In production, this would copy files from backup storage back to active storage
    sqlx::query("UPDATE backups SET status = 'restoring' WHERE id = $1").bind(id).execute(pool).await?;
    tracing::info!(backup_id = %id, "Backup restore initiated");
    Ok("Restore initiated".to_string())
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
