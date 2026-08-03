use axum::{
    body::Body,
    extract::{Path, State},
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use pcos_common::auth::AuthUser;
use pcos_common::{AppError, AppState};
use uuid::Uuid;

/// WebDAV PROPFIND response builder — generates XML for directory listings.
fn propfind_xml(entries: &[(Uuid, String, String, i64, String)]) -> String {
    let mut xml = String::from(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<D:multistatus xmlns:D=\"DAV:\">\n",
    );
    for (id, name, entry_type, size, updated) in entries {
        let is_dir = entry_type == "folder";
        xml.push_str(&format!(
            "  <D:response>\n    <D:href>/webdav/{name}</D:href>\n    <D:propstat>\n      <D:prop>\n        <D:displayname>{name}</D:displayname>\n        <D:getcontentlength>{size}</D:getcontentlength>\n        <D:getlastmodified>{updated}</D:getlastmodified>\n        <D:resourcetype>{rt}</D:resourcetype>\n        <D:getetag>\"{id}\"</D:getetag>\n      </D:prop>\n      <D:status>HTTP/1.1 200 OK</D:status>\n    </D:propstat>\n  </D:response>\n",
            name = name, size = size, updated = updated, id = id,
            rt = if is_dir { "<D:collection/>" } else { "" },
        ));
    }
    xml.push_str("</D:multistatus>\n");
    xml
}

/// PROPFIND — list directory contents (WebDAV equivalent of ls/dir)
pub async fn propfind(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    path: Option<Path<String>>,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let depth = headers
        .get("Depth")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("1");

    // Resolve parent folder — root if no path
    let entries: Vec<(Uuid, String, String, i64, String)> = if path.is_none()
        || path.as_ref().map(|p| p.0.as_str()) == Some("")
    {
        sqlx::query_as(
            "SELECT id, name, entry_type, size_bytes, to_char(updated_at, 'Dy, DD Mon YYYY HH24:MI:SS GMT') FROM file_entries WHERE user_id = $1 AND parent_id IS NULL AND is_trashed = false ORDER BY entry_type DESC, name"
        ).bind(auth.claims.sub).fetch_all(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?
    } else {
        let folder_name = path.unwrap().0;
        // Find folder by name path
        let folder: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM file_entries WHERE user_id = $1 AND name = $2 AND entry_type = 'folder' AND is_trashed = false LIMIT 1"
        ).bind(auth.claims.sub).bind(&folder_name).fetch_optional(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

        if let Some((folder_id,)) = folder {
            sqlx::query_as(
                "SELECT id, name, entry_type, size_bytes, to_char(updated_at, 'Dy, DD Mon YYYY HH24:MI:SS GMT') FROM file_entries WHERE user_id = $1 AND parent_id = $2 AND is_trashed = false ORDER BY entry_type DESC, name"
            ).bind(auth.claims.sub).bind(folder_id).fetch_all(pool).await
            .map_err(|e| AppError::Internal(e.to_string()))?
        } else {
            return Ok(Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::empty())
                .unwrap());
        }
    };

    let xml = propfind_xml(&entries);
    Ok(Response::builder()
        .status(StatusCode::MULTI_STATUS)
        .header(header::CONTENT_TYPE, "application/xml; charset=utf-8")
        .header("DAV", "1, 2")
        .body(Body::from(xml))
        .unwrap())
}

/// MKCOL — create a folder (WebDAV equivalent of mkdir)
pub async fn mkcol(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(name): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();
    sqlx::query(
        "INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, size_bytes, is_trashed, created_at, updated_at) VALUES ($1, $2, NULL, $3, 'folder', 0, false, NOW(), NOW())"
    ).bind(Uuid::new_v4()).bind(auth.claims.sub).bind(&name)
    .execute(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(StatusCode::CREATED)
}

/// DELETE — delete a file/folder (move to trash)
pub async fn webdav_delete(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(name): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();
    let result = sqlx::query(
        "UPDATE file_entries SET is_trashed = true, updated_at = NOW() WHERE user_id = $1 AND name = $2 AND is_trashed = false"
    ).bind(auth.claims.sub).bind(&name)
    .execute(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    if result.rows_affected() == 0 {
        Ok(StatusCode::NOT_FOUND)
    } else {
        Ok(StatusCode::NO_CONTENT)
    }
}

/// MOVE — rename or move a file/folder
pub async fn webdav_move(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(name): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let destination = headers
        .get("Destination")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.rsplit('/').next())
        .ok_or_else(|| AppError::Validation("Missing Destination header".to_string()))?;

    let pool = state.db.pool();
    let result = sqlx::query(
        "UPDATE file_entries SET name = $3, updated_at = NOW() WHERE user_id = $1 AND name = $2 AND is_trashed = false"
    ).bind(auth.claims.sub).bind(&name).bind(destination)
    .execute(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    if result.rows_affected() == 0 {
        Ok(StatusCode::NOT_FOUND)
    } else {
        Ok(StatusCode::CREATED)
    }
}

/// OPTIONS — advertise WebDAV capabilities
pub async fn options() -> impl IntoResponse {
    Response::builder()
        .status(StatusCode::OK)
        .header("DAV", "1, 2")
        .header(
            "Allow",
            "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, MKCOL, MOVE, COPY",
        )
        .header("MS-Author-Via", "DAV")
        .body(Body::empty())
        .unwrap()
}
