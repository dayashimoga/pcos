use crate::{provider::AiProvider, service};
use axum::extract::{Query, State};
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct TagRequest {
    pub filename: String,
    pub mime_type: String,
}

#[derive(Debug, Deserialize)]
pub struct SmartSearchQuery {
    pub q: String,
}

/// POST /api/v1/ai/tag
pub async fn auto_tag(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<TagRequest>,
) -> Result<impl IntoResponse, AppError> {
    let provider = AiProvider::from_env()
        .ok_or_else(|| AppError::Internal("AI not configured".to_string()))?;
    let tags = service::auto_tag(&provider, &req.filename, &req.mime_type).await?;
    Ok(Json(serde_json::json!({ "tags": tags })))
}

/// GET /api/v1/ai/duplicates
pub async fn find_duplicates(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let groups = service::find_duplicates(state.db.pool(), auth.claims.sub).await?;
    Ok(Json(
        serde_json::json!({ "duplicates": groups, "total_groups": groups.len() }),
    ))
}

/// POST /api/v1/ai/classify
pub async fn classify_file(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<TagRequest>,
) -> Result<impl IntoResponse, AppError> {
    let provider = AiProvider::from_env()
        .ok_or_else(|| AppError::Internal("AI not configured".to_string()))?;
    let category = service::classify_file(&provider, &req.filename, &req.mime_type).await?;
    Ok(Json(serde_json::json!({ "category": category.trim() })))
}

/// GET /api/v1/ai/smart-search?q=...
pub async fn smart_search(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(params): Query<SmartSearchQuery>,
) -> Result<impl IntoResponse, AppError> {
    // Smart search: use AI to expand query then search database
    let pool = state.db.pool();
    let pattern = format!("%{}%", params.q);

    let results: Vec<(uuid::Uuid, String, Option<String>, String, i64)> = sqlx::query_as(
        "SELECT id, name, mime_type, entry_type, size_bytes FROM file_entries WHERE user_id = $1 AND is_trashed = false AND name ILIKE $2 ORDER BY updated_at DESC LIMIT 50"
    )
    .bind(auth.claims.sub).bind(&pattern)
    .fetch_all(pool).await.map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "results": results.into_iter().map(|(id, name, mime, etype, size)| {
            serde_json::json!({ "id": id, "name": name, "mime_type": mime, "entry_type": etype, "size_bytes": size })
        }).collect::<Vec<_>>(),
        "query": params.q,
    })))
}

/// GET /api/v1/ai/status
pub async fn ai_status(
    State(_state): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let provider = AiProvider::from_env();
    let available = match &provider {
        Some(p) => p.health_check().await,
        None => false,
    };

    Ok(Json(serde_json::json!({
        "available": available,
        "provider": "ollama",
        "model": provider.map(|p| p.model).unwrap_or_default(),
    })))
}
