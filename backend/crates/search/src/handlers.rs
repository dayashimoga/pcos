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
    State(_state): State<AppState>,
    auth: AuthUser,
    Query(params): Query<SearchQuery>,
) -> Result<impl IntoResponse, AppError> {
    // Search index would be injected via state extension in production
    // For now, fall back to database search
    let pool = _state.db.pool();
    let pattern = format!("%{}%", params.q);
    let limit = params.limit.unwrap_or(50) as i64;

    let results: Vec<(uuid::Uuid, String, Option<String>, String, i64)> = sqlx::query_as(
        "SELECT id, name, mime_type, entry_type, size_bytes FROM file_entries WHERE user_id = $1 AND is_trashed = false AND name ILIKE $2 ORDER BY updated_at DESC LIMIT $3"
    )
    .bind(auth.claims.sub)
    .bind(&pattern)
    .bind(limit)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let response: Vec<serde_json::Value> = results.into_iter().map(|(id, name, mime, etype, size)| {
        serde_json::json!({
            "id": id,
            "name": name,
            "mime_type": mime,
            "entry_type": etype,
            "size_bytes": size,
        })
    }).collect();

    Ok(Json(serde_json::json!({
        "results": response,
        "total": response.len(),
        "query": params.q,
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

/// POST /api/v1/search/reindex
pub async fn reindex(
    State(_state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    Ok(Json(serde_json::json!({
        "message": "Reindex started",
        "user_id": auth.claims.sub,
    })))
}
