use axum::extract::{Query, State};
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct SearchQuery {
    pub q: String,
    pub limit: Option<usize>,
}

/// GET /api/v1/search?q=...&limit=...
pub async fn search(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(params): Query<SearchQuery>,
) -> Result<impl IntoResponse, AppError> {
    let limit = params.limit.unwrap_or(50);

    // Try Tantivy index first if available in AppState
    if let Some(ref idx_any) = state.search_index {
        if let Some(idx) = idx_any.downcast_ref::<crate::index::SearchIndex>() {
            match idx.search(auth.claims.sub, &params.q, limit) {
                Ok(results) => {
                    let response: Vec<serde_json::Value> = results.into_iter().map(|r| {
                        serde_json::json!({
                            "id": r.id, "name": r.name, "mime_type": r.mime_type,
                            "entry_type": r.entry_type, "score": r.score, "source": "tantivy"
                        })
                    }).collect();
                    return Ok(Json(serde_json::json!({
                        "results": response, "total": response.len(), "query": params.q, "engine": "tantivy"
                    })));
                }
                Err(e) => tracing::warn!(error = %e, "Tantivy search failed, falling back to DB"),
            }
        }
    }

    // Fallback: database ILIKE search
    let pool = state.db.pool();
    let pattern = format!("%{}%", params.q);
    let db_limit = limit as i64;

    let results: Vec<(uuid::Uuid, String, Option<String>, String, i64)> = sqlx::query_as(
        "SELECT id, name, mime_type, entry_type, size_bytes FROM file_entries WHERE user_id = $1 AND is_trashed = false AND name ILIKE $2 ORDER BY updated_at DESC LIMIT $3"
    )
    .bind(auth.claims.sub)
    .bind(&pattern)
    .bind(db_limit)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let response: Vec<serde_json::Value> = results.into_iter().map(|(id, name, mime, etype, size)| {
        serde_json::json!({
            "id": id, "name": name, "mime_type": mime,
            "entry_type": etype, "size_bytes": size, "source": "database"
        })
    }).collect();

    Ok(Json(serde_json::json!({
        "results": response, "total": response.len(), "query": params.q, "engine": "database"
    })))
}

/// GET /api/v1/search/suggest?q=...
pub async fn suggest(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(params): Query<SearchQuery>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();
    let pattern = format!("{}%", params.q);

    let suggestions: Vec<(String,)> = sqlx::query_as(
        "SELECT DISTINCT name FROM file_entries WHERE user_id = $1 AND is_trashed = false AND name ILIKE $2 ORDER BY name LIMIT 10"
    )
    .bind(auth.claims.sub)
    .bind(&pattern)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "suggestions": suggestions.into_iter().map(|(n,)| n).collect::<Vec<_>>(),
    })))
}

/// POST /api/v1/search/reindex — reindex all files for the authenticated user
pub async fn reindex(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();

    // Fetch all non-trashed files for this user
    let entries: Vec<(uuid::Uuid, String, Option<String>, String)> = sqlx::query_as(
        "SELECT id, name, mime_type, entry_type FROM file_entries WHERE user_id = $1 AND is_trashed = false"
    )
    .bind(auth.claims.sub)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let count = entries.len();
    let mut indexed = 0usize;

    // Index into Tantivy if available
    if let Some(ref idx_any) = state.search_index {
        if let Some(idx) = idx_any.downcast_ref::<crate::index::SearchIndex>() {
            for (id, name, mime, etype) in &entries {
                let mime_str = mime.as_deref().unwrap_or("");
                if let Err(e) = idx.index_document(*id, auth.claims.sub, name, "", mime_str, etype).await {
                    tracing::warn!(file_id = %id, error = %e, "Failed to index document");
                } else {
                    indexed += 1;
                }
            }
        }
    }

    tracing::info!(user_id = %auth.claims.sub, total = count, indexed = indexed, "Reindex completed");

    Ok(Json(serde_json::json!({
        "message": "Reindex completed",
        "user_id": auth.claims.sub,
        "files_found": count,
        "files_indexed": indexed,
        "engine": if indexed > 0 { "tantivy" } else { "none" },
    })))
}

/// POST /api/v1/search/extract/:id — extract text from a file for indexing
pub async fn extract_text(
    State(state): State<AppState>,
    auth: AuthUser,
    axum::extract::Path(file_id): axum::extract::Path<uuid::Uuid>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();

    let entry: Option<(String, Option<String>, Option<String>)> = sqlx::query_as(
        "SELECT name, mime_type, storage_path FROM file_entries WHERE id = $1 AND user_id = $2 AND is_trashed = false"
    ).bind(file_id).bind(auth.claims.sub)
    .fetch_optional(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let (name, mime, storage_path) = entry
        .ok_or_else(|| AppError::NotFound("File not found".to_string()))?;

    let mime_type = mime.unwrap_or_else(|| "application/octet-stream".to_string());
    let base_path = std::env::var("PCOS_STORAGE__BASE_PATH").unwrap_or_else(|_| "/data/pcos/storage".to_string());

    let file_path = if let Some(sp) = storage_path {
        format!("{}/{}", base_path, sp)
    } else {
        return Err(AppError::NotFound("File has no storage path".to_string()));
    };

    let path = std::path::Path::new(&file_path);
    let mut result = crate::extraction::extract_text(path, &mime_type).await?;
    result.file_id = file_id;

    // If Tantivy is available, index the extracted text
    if let Some(ref idx_any) = state.search_index {
        if let Some(idx) = idx_any.downcast_ref::<crate::index::SearchIndex>() {
            let _ = idx.index_document(file_id, auth.claims.sub, &name, &result.text, &mime_type, "file").await;
        }
    }

    Ok(Json(serde_json::json!({
        "file_id": file_id,
        "method": result.method,
        "confidence": result.confidence,
        "page_count": result.page_count,
        "text_length": result.text.len(),
        "text_preview": &result.text[..result.text.len().min(500)],
    })))
}
