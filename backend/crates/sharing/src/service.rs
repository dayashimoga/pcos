use crate::models::*;
use pcos_common::auth::password::{hash_password, verify_password};
use pcos_common::error::{AppError, AppResult};
use rand::Rng;
use sqlx::PgPool;
use uuid::Uuid;

fn generate_token() -> String {
    use rand::distributions::Alphanumeric;
    rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(32)
        .map(char::from)
        .collect()
}

pub async fn create_share(
    pool: &PgPool,
    user_id: Uuid,
    req: CreateShareRequest,
) -> AppResult<ShareLink> {
    // Verify file ownership
    let _file =
        sqlx::query_as::<_, (Uuid,)>("SELECT id FROM file_entries WHERE id = $1 AND user_id = $2")
            .bind(req.file_entry_id)
            .bind(user_id)
            .fetch_optional(pool)
            .await?
            .ok_or_else(|| AppError::NotFound("File not found".to_string()))?;

    let token = generate_token();
    let pwd_hash = match &req.password {
        Some(p) => Some(hash_password(p).map_err(|e| AppError::Internal(e.to_string()))?),
        None => None,
    };
    let expires_at = req
        .expires_in_hours
        .map(|h| chrono::Utc::now() + chrono::Duration::hours(h));

    let share = sqlx::query_as::<_, ShareLink>(
        r#"INSERT INTO share_links (id, user_id, file_entry_id, token, permission, password_hash, expires_at, max_downloads, download_count, is_active, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 0, true, NOW(), NOW()) RETURNING *"#
    )
    .bind(Uuid::new_v4()).bind(user_id).bind(req.file_entry_id).bind(&token)
    .bind(&req.permission).bind(&pwd_hash).bind(expires_at).bind(req.max_downloads)
    .fetch_one(pool).await?;

    tracing::info!(share_id = %share.id, file_id = %req.file_entry_id, "Share link created");
    Ok(share)
}

pub async fn list_shares(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<ShareLink>> {
    let shares = sqlx::query_as::<_, ShareLink>(
        "SELECT * FROM share_links WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(shares)
}

pub async fn get_share(pool: &PgPool, user_id: Uuid, share_id: Uuid) -> AppResult<ShareLink> {
    sqlx::query_as::<_, ShareLink>("SELECT * FROM share_links WHERE id = $1 AND user_id = $2")
        .bind(share_id)
        .bind(user_id)
        .fetch_optional(pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Share not found".to_string()))
}

pub async fn update_share(
    pool: &PgPool,
    user_id: Uuid,
    share_id: Uuid,
    req: UpdateShareRequest,
) -> AppResult<ShareLink> {
    let mut share = get_share(pool, user_id, share_id).await?;

    if let Some(perm) = &req.permission {
        share.permission = perm.clone();
    }
    if let Some(active) = req.is_active {
        share.is_active = active;
    }
    if let Some(max) = req.max_downloads {
        share.max_downloads = Some(max);
    }

    let pwd_hash = match &req.password {
        Some(p) => Some(hash_password(p).map_err(|e| AppError::Internal(e.to_string()))?),
        None => share.password_hash.clone(),
    };
    let expires = req
        .expires_in_hours
        .map(|h| chrono::Utc::now() + chrono::Duration::hours(h))
        .or(share.expires_at);

    let updated = sqlx::query_as::<_, ShareLink>(
        "UPDATE share_links SET permission = $1, password_hash = $2, expires_at = $3, max_downloads = $4, is_active = $5, updated_at = NOW() WHERE id = $6 RETURNING *"
    )
    .bind(&share.permission).bind(&pwd_hash).bind(expires).bind(share.max_downloads).bind(share.is_active).bind(share_id)
    .fetch_one(pool).await?;

    Ok(updated)
}

pub async fn delete_share(pool: &PgPool, user_id: Uuid, share_id: Uuid) -> AppResult<()> {
    let result = sqlx::query("DELETE FROM share_links WHERE id = $1 AND user_id = $2")
        .bind(share_id)
        .bind(user_id)
        .execute(pool)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Share not found".to_string()));
    }
    Ok(())
}

pub async fn access_shared(
    pool: &PgPool,
    token: &str,
    password: Option<&str>,
) -> AppResult<SharedFileInfo> {
    let share = sqlx::query_as::<_, ShareLink>(
        "SELECT * FROM share_links WHERE token = $1 AND is_active = true",
    )
    .bind(token)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| AppError::NotFound("Share link not found or expired".to_string()))?;

    // Check expiration
    if let Some(exp) = share.expires_at {
        if chrono::Utc::now() > exp {
            return Err(AppError::Forbidden("Share link has expired".to_string()));
        }
    }
    // Check max downloads
    if let Some(max) = share.max_downloads {
        if share.download_count >= max {
            return Err(AppError::Forbidden("Download limit reached".to_string()));
        }
    }
    // Check password
    if let Some(ref pwd_hash) = share.password_hash {
        let pwd =
            password.ok_or_else(|| AppError::Unauthorized("Password required".to_string()))?;
        if !verify_password(pwd, pwd_hash).map_err(|e| AppError::Internal(e.to_string()))? {
            return Err(AppError::Unauthorized("Invalid password".to_string()));
        }
    }

    let file: (String, String, Option<String>, i64) = sqlx::query_as(
        "SELECT name, entry_type, mime_type, size_bytes FROM file_entries WHERE id = $1",
    )
    .bind(share.file_entry_id)
    .fetch_one(pool)
    .await?;

    Ok(SharedFileInfo {
        name: file.0,
        entry_type: file.1,
        mime_type: file.2,
        size_bytes: file.3,
        permission: share.permission,
    })
}

pub async fn download_shared(pool: &PgPool, token: &str) -> AppResult<(String, Vec<u8>)> {
    let share = sqlx::query_as::<_, ShareLink>("SELECT * FROM share_links WHERE token = $1 AND is_active = true AND permission = 'download'")
        .bind(token).fetch_optional(pool).await?
        .ok_or_else(|| AppError::NotFound("Share not found or no download permission".to_string()))?;

    if let Some(exp) = share.expires_at {
        if chrono::Utc::now() > exp {
            return Err(AppError::Forbidden("Expired".to_string()));
        }
    }
    if let Some(max) = share.max_downloads {
        if share.download_count >= max {
            return Err(AppError::Forbidden("Limit reached".to_string()));
        }
    }

    // Increment download count
    sqlx::query("UPDATE share_links SET download_count = download_count + 1 WHERE id = $1")
        .bind(share.id)
        .execute(pool)
        .await?;

    let (name, storage_path): (String, Option<String>) =
        sqlx::query_as("SELECT name, storage_path FROM file_entries WHERE id = $1")
            .bind(share.file_entry_id)
            .fetch_one(pool)
            .await?;

    let path = storage_path.ok_or_else(|| AppError::Internal("No storage path".to_string()))?;
    // Storage read is handled by the handler layer
    Ok((name, vec![])) // placeholder - handler reads from storage
}
