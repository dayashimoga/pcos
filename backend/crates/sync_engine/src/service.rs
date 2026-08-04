use crate::models::*;
use pcos_common::error::{AppError, AppResult};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn get_changes(
    pool: &PgPool,
    user_id: Uuid,
    since: Option<chrono::DateTime<chrono::Utc>>,
) -> AppResult<Vec<ChangeEvent>> {
    let since_ts = since.unwrap_or_else(|| chrono::Utc::now() - chrono::Duration::days(30));
    let rows: Vec<(Uuid, Uuid, String, String, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "SELECT id, id as file_entry_id, name, entry_type, updated_at FROM file_entries WHERE user_id = $1 AND updated_at > $2 ORDER BY updated_at DESC LIMIT 1000"
    ).bind(user_id).bind(since_ts).fetch_all(pool).await?;

    Ok(rows
        .into_iter()
        .map(|(id, fid, name, _, ts)| ChangeEvent {
            id,
            file_entry_id: fid,
            change_type: "modified".to_string(),
            name,
            version: 1,
            timestamp: ts,
        })
        .collect())
}

pub async fn sync_status(
    pool: &PgPool,
    user_id: Uuid,
    device_id: Uuid,
) -> AppResult<SyncStatusResponse> {
    let (synced,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM sync_states WHERE user_id = $1 AND device_id = $2 AND status = 'synced'")
        .bind(user_id).bind(device_id).fetch_one(pool).await.unwrap_or((0,));
    let (pending,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM sync_states WHERE user_id = $1 AND device_id = $2 AND status = 'pending'")
        .bind(user_id).bind(device_id).fetch_one(pool).await.unwrap_or((0,));
    let (conflicts,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM sync_states WHERE user_id = $1 AND device_id = $2 AND status = 'conflict'")
        .bind(user_id).bind(device_id).fetch_one(pool).await.unwrap_or((0,));
    let last_sync: Option<(chrono::DateTime<chrono::Utc>,)> = sqlx::query_as(
        "SELECT MAX(last_synced_at) FROM sync_states WHERE user_id = $1 AND device_id = $2",
    )
    .bind(user_id)
    .bind(device_id)
    .fetch_optional(pool)
    .await
    .ok()
    .flatten();

    Ok(SyncStatusResponse {
        device_id,
        total_synced: synced,
        pending,
        conflicts,
        last_sync: last_sync.map(|l| l.0),
    })
}

pub async fn resolve_conflict(
    pool: &PgPool,
    user_id: Uuid,
    req: ResolveConflictRequest,
) -> AppResult<()> {
    match req.resolution.as_str() {
        "keep_local" | "keep_remote" => {
            sqlx::query("UPDATE sync_states SET status = 'synced', updated_at = NOW() WHERE user_id = $1 AND file_entry_id = $2 AND status = 'conflict'")
                .bind(user_id).bind(req.file_entry_id).execute(pool).await?;
        }
        "keep_both" => {
            sqlx::query("UPDATE sync_states SET status = 'synced', updated_at = NOW() WHERE user_id = $1 AND file_entry_id = $2")
                .bind(user_id).bind(req.file_entry_id).execute(pool).await?;
        }
        _ => return Err(AppError::Validation("Invalid resolution".to_string())),
    }
    Ok(())
}

pub async fn add_sync_folder(
    pool: &PgPool,
    user_id: Uuid,
    req: AddSyncFolderRequest,
) -> AppResult<SyncFolder> {
    let folder = sqlx::query_as::<_, SyncFolder>(
        "INSERT INTO sync_folders (id, user_id, device_id, local_path, remote_folder_id, is_active, created_at) VALUES ($1, $2, $3, $4, $5, true, NOW()) RETURNING *"
    ).bind(Uuid::new_v4()).bind(user_id).bind(req.device_id).bind(&req.local_path).bind(req.remote_folder_id)
    .fetch_one(pool).await?;
    Ok(folder)
}

pub async fn list_sync_folders(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<SyncFolder>> {
    let folders = sqlx::query_as::<_, SyncFolder>(
        "SELECT * FROM sync_folders WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(folders)
}

pub async fn remove_sync_folder(pool: &PgPool, user_id: Uuid, folder_id: Uuid) -> AppResult<()> {
    let r = sqlx::query("DELETE FROM sync_folders WHERE id = $1 AND user_id = $2")
        .bind(folder_id)
        .bind(user_id)
        .execute(pool)
        .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("Sync folder not found".to_string()));
    }
    Ok(())
}
