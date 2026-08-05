use axum::extract::State;
use axum::response::IntoResponse;
use axum::Json;
use pcos_common::auth::middleware::AuthUser;
use pcos_common::error::AppError;
use pcos_common::AppState;

pub async fn overview(
    State(s): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let pool = s.db.pool();
    let uid = auth.claims.sub;
    let (files,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM file_entries WHERE user_id=$1 AND entry_type='file' AND is_trashed=false").bind(uid).fetch_one(pool).await.unwrap_or((0,));
    let (folders,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM file_entries WHERE user_id=$1 AND entry_type='folder' AND is_trashed=false").bind(uid).fetch_one(pool).await.unwrap_or((0,));
    let (size,): (i64,) = sqlx::query_as("SELECT COALESCE(SUM(size_bytes), 0)::BIGINT FROM file_entries WHERE user_id=$1 AND entry_type='file' AND is_trashed=false").bind(uid).fetch_one(pool).await.unwrap_or((0,));
    let (devices,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM devices WHERE user_id=$1")
        .bind(uid)
        .fetch_one(pool)
        .await
        .unwrap_or((0,));
    let (shares,): (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM share_links WHERE user_id=$1 AND is_active=true")
            .bind(uid)
            .fetch_one(pool)
            .await
            .unwrap_or((0,));
    let (backups,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM backups WHERE user_id=$1")
        .bind(uid)
        .fetch_one(pool)
        .await
        .unwrap_or((0,));

    Ok(Json(serde_json::json!({
        "total_files": files, "total_folders": folders, "total_size_bytes": size,
        "total_devices": devices, "active_shares": shares, "total_backups": backups,
        "formatted_size": format_bytes(size)
    })))
}

pub async fn storage_analytics(
    State(s): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let pool = s.db.pool();
    let uid = auth.claims.sub;
    // Top 10 largest files
    let largest: Vec<(uuid::Uuid, String, i64, Option<String>)> = sqlx::query_as(
        "SELECT id, name, size_bytes, mime_type FROM file_entries WHERE user_id=$1 AND entry_type='file' AND is_trashed=false ORDER BY size_bytes DESC LIMIT 10"
    ).bind(uid).fetch_all(pool).await.unwrap_or_default();

    let files: Vec<serde_json::Value> = largest.into_iter().map(|(id, name, size, mime)| {
        serde_json::json!({ "id": id, "name": name, "size_bytes": size, "mime_type": mime, "formatted_size": format_bytes(size) })
    }).collect();

    // Storage by type
    let by_type: Vec<(Option<String>, i64, i64)> = sqlx::query_as(
        "SELECT COALESCE(SPLIT_PART(mime_type,'/',1),'unknown'), COUNT(*), COALESCE(SUM(size_bytes),0)::BIGINT FROM file_entries WHERE user_id=$1 AND entry_type='file' AND is_trashed=false GROUP BY 1 ORDER BY 3 DESC"
    ).bind(uid).fetch_all(pool).await.unwrap_or_default();

    let types: Vec<serde_json::Value> = by_type.into_iter().map(|(t, count, size)| {
        serde_json::json!({ "type": t, "count": count, "size_bytes": size, "formatted_size": format_bytes(size) })
    }).collect();

    Ok(Json(
        serde_json::json!({ "largest_files": files, "storage_by_type": types }),
    ))
}

pub async fn activity_timeline(
    State(s): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let pool = s.db.pool();
    let activity: Vec<(String, i64)> = sqlx::query_as(
        "SELECT TO_CHAR(created_at, 'YYYY-MM-DD') as day, COUNT(*) FROM audit_log WHERE user_id=$1 AND created_at > NOW() - INTERVAL '30 days' GROUP BY 1 ORDER BY 1"
    ).bind(auth.claims.sub).fetch_all(pool).await.unwrap_or_default();

    let timeline: Vec<serde_json::Value> = activity
        .into_iter()
        .map(|(day, count)| serde_json::json!({ "date": day, "actions": count }))
        .collect();
    Ok(Json(
        serde_json::json!({ "timeline": timeline, "period": "30_days" }),
    ))
}

pub async fn file_type_breakdown(
    State(s): State<AppState>,
    auth: AuthUser,
) -> Result<impl IntoResponse, AppError> {
    let pool = s.db.pool();
    let breakdown: Vec<(Option<String>, i64)> = sqlx::query_as(
        "SELECT mime_type, COUNT(*) FROM file_entries WHERE user_id=$1 AND entry_type='file' AND is_trashed=false GROUP BY mime_type ORDER BY 2 DESC LIMIT 20"
    ).bind(auth.claims.sub).fetch_all(pool).await.unwrap_or_default();

    let types: Vec<serde_json::Value> = breakdown.into_iter().map(|(mime, count)| {
        serde_json::json!({ "mime_type": mime.unwrap_or("unknown".to_string()), "count": count })
    }).collect();
    Ok(Json(serde_json::json!({ "file_types": types })))
}

pub async fn prometheus_metrics(State(s): State<AppState>) -> Result<impl IntoResponse, AppError> {
    let pool = s.db.pool();
    let (users,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM users")
        .fetch_one(pool)
        .await
        .unwrap_or((0,));
    let (files,): (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM file_entries WHERE entry_type='file'")
            .fetch_one(pool)
            .await
            .unwrap_or((0,));
    let (devices,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM devices")
        .fetch_one(pool)
        .await
        .unwrap_or((0,));
    let (online,): (i64,) = sqlx::query_as("SELECT COUNT(*) FROM devices WHERE is_online=true")
        .fetch_one(pool)
        .await
        .unwrap_or((0,));

    let metrics = format!(
        "# HELP pcos_users_total Total registered users\n# TYPE pcos_users_total gauge\npcos_users_total {}\n\
         # HELP pcos_files_total Total files stored\n# TYPE pcos_files_total gauge\npcos_files_total {}\n\
         # HELP pcos_devices_total Total registered devices\n# TYPE pcos_devices_total gauge\npcos_devices_total {}\n\
         # HELP pcos_devices_online Currently online devices\n# TYPE pcos_devices_online gauge\npcos_devices_online {}\n",
        users, files, devices, online
    );
    Ok((
        [(
            axum::http::header::CONTENT_TYPE,
            "text/plain; version=0.0.4",
        )],
        metrics,
    ))
}

fn format_bytes(bytes: i64) -> String {
    const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
    let mut size = bytes as f64;
    for unit in UNITS {
        if size < 1024.0 {
            return format!("{:.1} {}", size, unit);
        }
        size /= 1024.0;
    }
    format!("{:.1} PB", size)
}
