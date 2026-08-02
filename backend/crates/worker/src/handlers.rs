use axum::extract::State;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;

pub async fn list_jobs(State(s): State<AppState>, auth: AuthUser) -> Result<impl IntoResponse, AppError> {
    let rows: Vec<(uuid::Uuid, String, String, String, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "SELECT id, job_type, status, details, created_at FROM jobs WHERE user_id = $1 ORDER BY created_at DESC LIMIT 100"
    ).bind(auth.claims.sub).fetch_all(s.db.pool()).await.unwrap_or_default();

    let jobs: Vec<serde_json::Value> = rows.into_iter().map(|(id, jtype, status, details, ts)| {
        serde_json::json!({ "id": id, "job_type": jtype, "status": status, "details": details, "created_at": ts })
    }).collect();
    Ok(Json(serde_json::json!({ "jobs": jobs, "total": jobs.len() })))
}

pub async fn job_stats(State(s): State<AppState>, auth: AuthUser) -> Result<impl IntoResponse, AppError> {
    let (total,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM jobs WHERE user_id = $1").bind(auth.claims.sub).fetch_one(s.db.pool()).await.unwrap_or((0,));
    let (running,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM jobs WHERE user_id = $1 AND status = 'running'").bind(auth.claims.sub).fetch_one(s.db.pool()).await.unwrap_or((0,));
    let (completed,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM jobs WHERE user_id = $1 AND status = 'completed'").bind(auth.claims.sub).fetch_one(s.db.pool()).await.unwrap_or((0,));
    let (failed,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM jobs WHERE user_id = $1 AND status = 'failed'").bind(auth.claims.sub).fetch_one(s.db.pool()).await.unwrap_or((0,));
    Ok(Json(serde_json::json!({ "total": total, "running": running, "completed": completed, "failed": failed })))
}
