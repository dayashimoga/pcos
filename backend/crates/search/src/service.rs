use crate::index::SearchIndex;
use pcos_common::error::{AppError, AppResult};
use sqlx::PgPool;
use uuid::Uuid;

/// Search for files matching the query.
pub async fn search(
    index: &SearchIndex,
    user_id: Uuid,
    query: &str,
    limit: usize,
) -> AppResult<Vec<crate::index::SearchResult>> {
    if query.trim().is_empty() {
        return Ok(vec![]);
    }

    index
        .search(user_id, query, limit)
        .map_err(|e| AppError::Internal(format!("Search failed: {e}")))
}

/// Reindex all files for a user from the database.
pub async fn reindex_user(pool: &PgPool, index: &SearchIndex, user_id: Uuid) -> AppResult<usize> {
    let entries: Vec<(Uuid, Uuid, String, Option<String>, String)> = sqlx::query_as(
        "SELECT id, user_id, name, mime_type, entry_type FROM file_entries WHERE user_id = $1 AND is_trashed = false"
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    let count = entries.len();
    for (id, uid, name, mime, etype) in entries {
        let mime_str = mime.unwrap_or_default();
        index
            .index_document(id, uid, &name, "", &mime_str, &etype)
            .await
            .map_err(|e| AppError::Internal(format!("Index failed: {e}")))?;
    }

    tracing::info!(user_id = %user_id, count = count, "Reindexed files");
    Ok(count)
}
