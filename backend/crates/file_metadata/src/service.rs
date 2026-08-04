use crate::models::*;
use crate::storage::StorageEngine;
use pcos_common::error::{AppError, AppResult};
use sqlx::PgPool;
use uuid::Uuid;

/// Create a new folder.
pub async fn create_folder(
    pool: &PgPool,
    user_id: Uuid,
    req: CreateFolderRequest,
) -> AppResult<FileEntryResponse> {
    // Verify parent exists and belongs to user if specified
    if let Some(parent_id) = req.parent_id {
        verify_ownership(pool, user_id, parent_id).await?;
    }

    // Check for duplicate name in same parent
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM file_entries WHERE user_id = $1 AND parent_id IS NOT DISTINCT FROM $2 AND name = $3 AND is_trashed = false)"
    )
    .bind(user_id).bind(req.parent_id).bind(&req.name)
    .fetch_one(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    if exists {
        return Err(AppError::Conflict(format!(
            "An item named '{}' already exists here",
            req.name
        )));
    }

    let entry = sqlx::query_as::<_, FileEntry>(
        r#"INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, size_bytes, is_trashed, created_at, updated_at)
        VALUES ($1, $2, $3, $4, 'folder', 0, false, NOW(), NOW()) RETURNING *"#
    )
    .bind(Uuid::new_v4()).bind(user_id).bind(req.parent_id).bind(&req.name)
    .fetch_one(pool).await?;

    Ok(entry.into())
}

/// List entries in root (no parent).
pub async fn list_root(pool: &PgPool, user_id: Uuid) -> AppResult<FileListResponse> {
    let entries = sqlx::query_as::<_, FileEntry>(
        "SELECT * FROM file_entries WHERE user_id = $1 AND parent_id IS NULL AND is_trashed = false ORDER BY entry_type DESC, name ASC"
    )
    .bind(user_id).fetch_all(pool).await?;

    Ok(FileListResponse {
        total: entries.len() as i64,
        entries: entries.into_iter().map(Into::into).collect(),
        path: vec![BreadcrumbItem {
            id: None,
            name: "Root".to_string(),
        }],
    })
}

/// List entries inside a folder.
pub async fn list_folder(
    pool: &PgPool,
    user_id: Uuid,
    folder_id: Uuid,
) -> AppResult<FileListResponse> {
    verify_ownership(pool, user_id, folder_id).await?;

    let entries = sqlx::query_as::<_, FileEntry>(
        "SELECT * FROM file_entries WHERE user_id = $1 AND parent_id = $2 AND is_trashed = false ORDER BY entry_type DESC, name ASC"
    )
    .bind(user_id).bind(folder_id).fetch_all(pool).await?;

    let path = build_breadcrumb(pool, user_id, Some(folder_id)).await?;

    Ok(FileListResponse {
        total: entries.len() as i64,
        entries: entries.into_iter().map(Into::into).collect(),
        path,
    })
}

/// Upload a file (single request, not chunked).
pub async fn upload_file(
    pool: &PgPool,
    storage: &StorageEngine,
    user_id: Uuid,
    parent_id: Option<Uuid>,
    filename: &str,
    mime_type: &str,
    data: &[u8],
) -> AppResult<FileEntryResponse> {
    if let Some(pid) = parent_id {
        verify_ownership(pool, user_id, pid).await?;
    }

    let file_id = Uuid::new_v4();
    let (storage_path, hash) = storage
        .store_file(user_id, file_id, data)
        .await
        .map_err(|e| AppError::Internal(format!("Storage write failed: {e}")))?;

    let entry = sqlx::query_as::<_, FileEntry>(
        r#"INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, storage_path, is_trashed, created_at, updated_at)
        VALUES ($1, $2, $3, $4, 'file', $5, $6, $7, $8, false, NOW(), NOW()) RETURNING *"#
    )
    .bind(file_id).bind(user_id).bind(parent_id).bind(filename)
    .bind(mime_type).bind(data.len() as i64).bind(&hash).bind(&storage_path)
    .fetch_one(pool).await?;

    tracing::info!(file_id = %file_id, name = %filename, size = data.len(), "File uploaded");
    Ok(entry.into())
}

/// Store a chunk for chunked upload.
pub async fn store_chunk(
    storage: &StorageEngine,
    user_id: Uuid,
    upload_id: Uuid,
    chunk_index: i32,
    data: &[u8],
) -> AppResult<ChunkUploadResponse> {
    storage
        .store_chunk(user_id, upload_id, chunk_index, data)
        .await
        .map_err(|e| AppError::Internal(format!("Chunk storage failed: {e}")))?;

    Ok(ChunkUploadResponse {
        upload_id,
        chunk_index,
        received: true,
    })
}

/// Complete a chunked upload by assembling chunks.
pub async fn complete_chunked_upload(
    pool: &PgPool,
    storage: &StorageEngine,
    user_id: Uuid,
    req: ChunkedUploadRequest,
) -> AppResult<FileEntryResponse> {
    if let Some(pid) = req.parent_id {
        verify_ownership(pool, user_id, pid).await?;
    }

    let file_id = Uuid::new_v4();
    let (storage_path, hash, actual_size) = storage
        .assemble_chunks(user_id, req.upload_id, file_id, req.total_chunks)
        .await
        .map_err(|e| AppError::Internal(format!("Chunk assembly failed: {e}")))?;

    let mime = mime_guess::from_path(&req.filename)
        .first_or_octet_stream()
        .to_string();

    let entry = sqlx::query_as::<_, FileEntry>(
        r#"INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, storage_path, is_trashed, created_at, updated_at)
        VALUES ($1, $2, $3, $4, 'file', $5, $6, $7, $8, false, NOW(), NOW()) RETURNING *"#
    )
    .bind(file_id).bind(user_id).bind(req.parent_id).bind(&req.filename)
    .bind(&mime).bind(actual_size).bind(&hash).bind(&storage_path)
    .fetch_one(pool).await?;

    tracing::info!(file_id = %file_id, name = %req.filename, size = actual_size, "Chunked upload completed");
    Ok(entry.into())
}

/// Get file metadata.
pub async fn get_file_meta(
    pool: &PgPool,
    user_id: Uuid,
    file_id: Uuid,
) -> AppResult<FileEntryResponse> {
    let entry = verify_ownership(pool, user_id, file_id).await?;
    Ok(entry.into())
}

/// Download file data.
pub async fn download_file(
    pool: &PgPool,
    storage: &StorageEngine,
    user_id: Uuid,
    file_id: Uuid,
) -> AppResult<(FileEntry, Vec<u8>)> {
    let entry = verify_ownership(pool, user_id, file_id).await?;
    if entry.entry_type != "file" {
        return Err(AppError::Validation("Cannot download a folder".to_string()));
    }
    let path = entry
        .storage_path
        .as_ref()
        .ok_or_else(|| AppError::Internal("File has no storage path".to_string()))?;

    let data = storage
        .read_file(path)
        .await
        .map_err(|e| AppError::Internal(format!("File read failed: {e}")))?;

    Ok((entry, data))
}

/// Rename a file or folder.
pub async fn rename_item(
    pool: &PgPool,
    user_id: Uuid,
    item_id: Uuid,
    req: RenameRequest,
) -> AppResult<FileEntryResponse> {
    let entry = verify_ownership(pool, user_id, item_id).await?;

    // Check duplicate name in same parent
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM file_entries WHERE user_id = $1 AND parent_id IS NOT DISTINCT FROM $2 AND name = $3 AND id != $4 AND is_trashed = false)"
    )
    .bind(user_id).bind(entry.parent_id).bind(&req.name).bind(item_id)
    .fetch_one(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    if exists {
        return Err(AppError::Conflict(format!(
            "An item named '{}' already exists",
            req.name
        )));
    }

    let updated = sqlx::query_as::<_, FileEntry>(
        "UPDATE file_entries SET name = $1, updated_at = NOW() WHERE id = $2 RETURNING *",
    )
    .bind(&req.name)
    .bind(item_id)
    .fetch_one(pool)
    .await?;

    Ok(updated.into())
}

/// Move a file or folder to another folder.
pub async fn move_item(
    pool: &PgPool,
    user_id: Uuid,
    item_id: Uuid,
    req: MoveRequest,
) -> AppResult<FileEntryResponse> {
    verify_ownership(pool, user_id, item_id).await?;

    if let Some(target_id) = req.target_folder_id {
        let target = verify_ownership(pool, user_id, target_id).await?;
        if target.entry_type != "folder" {
            return Err(AppError::Validation("Target must be a folder".to_string()));
        }
        // Prevent moving a folder into itself or its descendants
        if item_id == target_id {
            return Err(AppError::Validation(
                "Cannot move a folder into itself".to_string(),
            ));
        }
    }

    let updated = sqlx::query_as::<_, FileEntry>(
        "UPDATE file_entries SET parent_id = $1, updated_at = NOW() WHERE id = $2 RETURNING *",
    )
    .bind(req.target_folder_id)
    .bind(item_id)
    .fetch_one(pool)
    .await?;

    Ok(updated.into())
}

/// Soft-delete (move to trash).
pub async fn delete_item(pool: &PgPool, user_id: Uuid, item_id: Uuid) -> AppResult<()> {
    verify_ownership(pool, user_id, item_id).await?;

    // Trash the item and all descendants (for folders)
    sqlx::query(
        r#"WITH RECURSIVE descendants AS (
            SELECT id FROM file_entries WHERE id = $1 AND user_id = $2
            UNION ALL
            SELECT fe.id FROM file_entries fe JOIN descendants d ON fe.parent_id = d.id
        )
        UPDATE file_entries SET is_trashed = true, trashed_at = NOW(), updated_at = NOW()
        WHERE id IN (SELECT id FROM descendants)"#,
    )
    .bind(item_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// List trashed items.
pub async fn list_trash(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<FileEntryResponse>> {
    let entries = sqlx::query_as::<_, FileEntry>(
        "SELECT * FROM file_entries WHERE user_id = $1 AND is_trashed = true ORDER BY trashed_at DESC"
    )
    .bind(user_id).fetch_all(pool).await?;

    Ok(entries.into_iter().map(Into::into).collect())
}

/// Restore an item from trash.
pub async fn restore_from_trash(
    pool: &PgPool,
    user_id: Uuid,
    item_id: Uuid,
) -> AppResult<FileEntryResponse> {
    let entry = verify_ownership(pool, user_id, item_id).await?;
    if !entry.is_trashed {
        return Err(AppError::Validation("Item is not in trash".to_string()));
    }

    // Restore item and all descendants
    sqlx::query(
        r#"WITH RECURSIVE descendants AS (
            SELECT id FROM file_entries WHERE id = $1 AND user_id = $2
            UNION ALL
            SELECT fe.id FROM file_entries fe JOIN descendants d ON fe.parent_id = d.id
        )
        UPDATE file_entries SET is_trashed = false, trashed_at = NULL, updated_at = NOW()
        WHERE id IN (SELECT id FROM descendants)"#,
    )
    .bind(item_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    let restored = sqlx::query_as::<_, FileEntry>("SELECT * FROM file_entries WHERE id = $1")
        .bind(item_id)
        .fetch_one(pool)
        .await?;

    Ok(restored.into())
}

/// Permanently delete an item from trash.
pub async fn permanent_delete(
    pool: &PgPool,
    storage: &StorageEngine,
    user_id: Uuid,
    item_id: Uuid,
) -> AppResult<()> {
    let entry = verify_ownership(pool, user_id, item_id).await?;
    if !entry.is_trashed {
        return Err(AppError::Validation(
            "Item must be in trash to permanently delete".to_string(),
        ));
    }

    // Get all file storage paths for this item and descendants
    let paths: Vec<(Option<String>,)> = sqlx::query_as(
        r#"WITH RECURSIVE descendants AS (
            SELECT id, storage_path FROM file_entries WHERE id = $1 AND user_id = $2
            UNION ALL
            SELECT fe.id, fe.storage_path FROM file_entries fe JOIN descendants d ON fe.parent_id = d.id
        )
        SELECT storage_path FROM descendants WHERE storage_path IS NOT NULL"#
    )
    .bind(item_id).bind(user_id)
    .fetch_all(pool).await?;

    // Delete from storage
    for (path,) in &paths {
        if let Some(p) = path {
            storage.delete_file(p).await.ok();
        }
    }

    // Delete from database (cascade via recursive CTE)
    sqlx::query(
        r#"WITH RECURSIVE descendants AS (
            SELECT id FROM file_entries WHERE id = $1 AND user_id = $2
            UNION ALL
            SELECT fe.id FROM file_entries fe JOIN descendants d ON fe.parent_id = d.id
        )
        DELETE FROM file_entries WHERE id IN (SELECT id FROM descendants)"#,
    )
    .bind(item_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Empty the entire trash.
pub async fn empty_trash(pool: &PgPool, storage: &StorageEngine, user_id: Uuid) -> AppResult<i64> {
    let paths: Vec<(Option<String>,)> = sqlx::query_as(
        "SELECT storage_path FROM file_entries WHERE user_id = $1 AND is_trashed = true AND storage_path IS NOT NULL"
    )
    .bind(user_id).fetch_all(pool).await?;

    for (path,) in &paths {
        if let Some(p) = path {
            storage.delete_file(p).await.ok();
        }
    }

    let result = sqlx::query("DELETE FROM file_entries WHERE user_id = $1 AND is_trashed = true")
        .bind(user_id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() as i64)
}

/// Get storage statistics.
pub async fn storage_stats(pool: &PgPool, user_id: Uuid) -> AppResult<StorageStatsResponse> {
    let (total_files,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false"
    ).bind(user_id).fetch_one(pool).await.unwrap_or((0,));

    let (total_folders,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM file_entries WHERE user_id = $1 AND entry_type = 'folder' AND is_trashed = false"
    ).bind(user_id).fetch_one(pool).await.unwrap_or((0,));

    let (total_size,): (Option<i64>,) = sqlx::query_as(
        "SELECT SUM(size_bytes) FROM file_entries WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false"
    ).bind(user_id).fetch_one(pool).await.unwrap_or((None,));

    let (trashed,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM file_entries WHERE user_id = $1 AND is_trashed = true",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .unwrap_or((0,));

    Ok(StorageStatsResponse {
        total_files,
        total_folders,
        total_size_bytes: total_size.unwrap_or(0),
        trashed_items: trashed,
    })
}

/// Verify the item exists and belongs to the user.
async fn verify_ownership(pool: &PgPool, user_id: Uuid, item_id: Uuid) -> AppResult<FileEntry> {
    sqlx::query_as::<_, FileEntry>("SELECT * FROM file_entries WHERE id = $1 AND user_id = $2")
        .bind(item_id)
        .bind(user_id)
        .fetch_optional(pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Item not found".to_string()))
}

/// Build breadcrumb path from root to the given folder.
async fn build_breadcrumb(
    pool: &PgPool,
    user_id: Uuid,
    folder_id: Option<Uuid>,
) -> AppResult<Vec<BreadcrumbItem>> {
    let mut path = vec![BreadcrumbItem {
        id: None,
        name: "Root".to_string(),
    }];

    let mut current_id = folder_id;
    let mut ancestors = Vec::new();

    while let Some(cid) = current_id {
        let entry = sqlx::query_as::<_, FileEntry>(
            "SELECT * FROM file_entries WHERE id = $1 AND user_id = $2",
        )
        .bind(cid)
        .bind(user_id)
        .fetch_optional(pool)
        .await?;

        if let Some(e) = entry {
            ancestors.push(BreadcrumbItem {
                id: Some(e.id),
                name: e.name,
            });
            current_id = e.parent_id;
        } else {
            break;
        }
    }

    ancestors.reverse();
    path.extend(ancestors);
    Ok(path)
}
