use axum::{
    body::Body,
    extract::{Path, State},
    http::{header, HeaderMap, Request, StatusCode},
    response::{IntoResponse, Response},
};
use pcos_common::auth::AuthUser;
use pcos_common::{AppError, AppState};
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

/// WebDAV PROPFIND response builder — generates XML for directory and file listings.
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

/// Helper to resolve a forward-slash separated WebDAV path to parent folder ID and target file/folder entry.
async fn resolve_path(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    raw_path: &str,
) -> Result<
    (
        Option<Uuid>,
        Option<(Uuid, String, String, i64, Option<String>, Option<String>, String)>,
    ),
    AppError,
> {
    let clean = raw_path.trim_matches('/');
    if clean.is_empty() {
        return Ok((None, None));
    }

    let segments: Vec<&str> = clean.split('/').filter(|s| !s.is_empty()).collect();
    let mut current_parent: Option<Uuid> = None;

    for (i, segment) in segments.iter().enumerate() {
        let is_last = i == segments.len() - 1;

        if is_last {
            let row: Option<(Uuid, String, String, i64, Option<String>, Option<String>, String)> = sqlx::query_as(
                "SELECT id, name, entry_type, size_bytes, mime_type, storage_path, to_char(updated_at, 'Dy, DD Mon YYYY HH24:MI:SS GMT') FROM file_entries WHERE user_id = $1 AND name = $2 AND is_trashed = false AND (parent_id = $3 OR (parent_id IS NULL AND $3 IS NULL)) LIMIT 1"
            )
            .bind(user_id)
            .bind(segment)
            .bind(current_parent)
            .fetch_optional(pool)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;

            return Ok((current_parent, row));
        } else {
            let folder: Option<(Uuid,)> = sqlx::query_as(
                "SELECT id FROM file_entries WHERE user_id = $1 AND name = $2 AND entry_type = 'folder' AND is_trashed = false AND (parent_id = $3 OR (parent_id IS NULL AND $3 IS NULL)) LIMIT 1"
            )
            .bind(user_id)
            .bind(segment)
            .bind(current_parent)
            .fetch_optional(pool)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;

            match folder {
                Some((id,)) => current_parent = Some(id),
                None => return Ok((current_parent, None)),
            }
        }
    }

    Ok((current_parent, None))
}

/// PROPFIND — list directory contents (WebDAV equivalent of ls/dir)
pub async fn propfind(
    State(state): State<AppState>,
    auth: AuthUser,
    _headers: HeaderMap,
    path: Option<Path<String>>,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let raw_path = path.as_ref().map(|p| p.0.as_str()).unwrap_or("");
    let (_, target) = resolve_path(pool, auth.claims.sub, raw_path).await?;

    let entries: Vec<(Uuid, String, String, i64, String)> = match target {
        Some((id, _name, entry_type, _size, _, _, _updated)) if entry_type == "folder" => {
            sqlx::query_as(
                "SELECT id, name, entry_type, size_bytes, to_char(updated_at, 'Dy, DD Mon YYYY HH24:MI:SS GMT') FROM file_entries WHERE user_id = $1 AND parent_id = $2 AND is_trashed = false ORDER BY entry_type DESC, name"
            ).bind(auth.claims.sub).bind(id).fetch_all(pool).await
            .map_err(|e| AppError::Internal(e.to_string()))?
        }
        Some((id, name, entry_type, size, _, _, updated)) => {
            vec![(id, name, entry_type, size, updated)]
        }
        None if raw_path.is_empty() => {
            sqlx::query_as(
                "SELECT id, name, entry_type, size_bytes, to_char(updated_at, 'Dy, DD Mon YYYY HH24:MI:SS GMT') FROM file_entries WHERE user_id = $1 AND parent_id IS NULL AND is_trashed = false ORDER BY entry_type DESC, name"
            ).bind(auth.claims.sub).fetch_all(pool).await
            .map_err(|e| AppError::Internal(e.to_string()))?
        }
        None => {
            return Ok(Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::empty())
                .expect("valid 404 response"));
        }
    };

    let xml = propfind_xml(&entries);
    Ok(Response::builder()
        .status(StatusCode::MULTI_STATUS)
        .header(header::CONTENT_TYPE, "application/xml; charset=utf-8")
        .header("DAV", "1, 2")
        .body(Body::from(xml))
        .expect("valid 207 response"))
}

/// MKCOL — create a folder (WebDAV equivalent of mkdir)
pub async fn mkcol(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(name): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();
    let (parent_id, existing) = resolve_path(pool, auth.claims.sub, &name).await?;

    if existing.is_some() {
        return Ok(StatusCode::METHOD_NOT_ALLOWED);
    }

    let folder_name = name
        .trim_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(&name)
        .to_string();

    sqlx::query(
        "INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, size_bytes, is_trashed, created_at, updated_at) VALUES ($1, $2, $3, $4, 'folder', 0, false, NOW(), NOW())"
    )
    .bind(Uuid::new_v4())
    .bind(auth.claims.sub)
    .bind(parent_id)
    .bind(&folder_name)
    .execute(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(StatusCode::CREATED)
}

/// GET — download file content over WebDAV
pub async fn webdav_get(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(name): Path<String>,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let (_, entry) = resolve_path(pool, auth.claims.sub, &name).await?;

    let (id, _file_name, entry_type, _size_bytes, mime, storage_path, updated) = match entry {
        Some(e) => e,
        None => {
            return Ok(Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::empty())
                .expect("valid 404 response"));
        }
    };

    if entry_type == "folder" {
        return propfind(State(state), auth, headers, Some(Path(name))).await;
    }

    let base_path = PathBuf::from(&state.config.storage.base_path);
    let full_path = match storage_path {
        Some(p) => base_path.join(p),
        None => {
            return Ok(Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::empty())
                .expect("valid 404 response"));
        }
    };

    let data = fs::read(&full_path)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to read file: {e}")))?;

    let content_type = mime.unwrap_or_else(|| "application/octet-stream".to_string());
    let total_size = data.len();

    // Range support
    if let Some(range_header) = headers.get(header::RANGE).and_then(|v| v.to_str().ok()) {
        if let Some(range) = range_header.strip_prefix("bytes=") {
            let parts: Vec<&str> = range.split('-').collect();
            let start = parts[0].parse::<usize>().unwrap_or(0);
            let end = parts
                .get(1)
                .and_then(|s| s.parse::<usize>().ok())
                .unwrap_or(total_size.saturating_sub(1));

            if start < total_size && start <= end {
                let end = end.min(total_size.saturating_sub(1));
                let slice = data[start..=end].to_vec();
                let length = end - start + 1;

                return Ok(Response::builder()
                    .status(StatusCode::PARTIAL_CONTENT)
                    .header(header::CONTENT_TYPE, content_type)
                    .header(header::CONTENT_LENGTH, length.to_string())
                    .header(
                        header::CONTENT_RANGE,
                        format!("bytes {}-{}/{}", start, end, total_size),
                    )
                    .header(header::ACCEPT_RANGES, "bytes")
                    .header(header::LAST_MODIFIED, updated)
                    .header(header::ETAG, format!("\"{}\"", id))
                    .body(Body::from(slice))
                    .expect("valid 206 response"));
            }
        }
    }

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CONTENT_LENGTH, total_size.to_string())
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::LAST_MODIFIED, updated)
        .header(header::ETAG, format!("\"{}\"", id))
        .body(Body::from(data))
        .expect("valid 200 response"))
}

/// HEAD — file headers over WebDAV
pub async fn webdav_head(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(name): Path<String>,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let (_, entry) = resolve_path(pool, auth.claims.sub, &name).await?;

    let (id, _, entry_type, size_bytes, mime, _, updated) = match entry {
        Some(e) => e,
        None => {
            return Ok(Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::empty())
                .expect("valid 404 response"));
        }
    };

    let content_type = if entry_type == "folder" {
        "httpd/unix-directory".to_string()
    } else {
        mime.unwrap_or_else(|| "application/octet-stream".to_string())
    };

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CONTENT_LENGTH, size_bytes.to_string())
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::LAST_MODIFIED, updated)
        .header(header::ETAG, format!("\"{}\"", id))
        .body(Body::empty())
        .expect("valid HEAD response"))
}

/// PUT — upload file content over WebDAV
pub async fn webdav_put(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(name): Path<String>,
    body: Body,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let user_id = auth.claims.sub;
    let (parent_id, existing) = resolve_path(pool, user_id, &name).await?;

    let bytes = axum::body::to_bytes(body, 10 * 1024 * 1024 * 1024)
        .await
        .map_err(|e| AppError::Validation(format!("Upload body read failed: {e}")))?;

    let filename = name
        .trim_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(&name)
        .to_string();

    let mime = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .or_else(|| {
            mime_guess::from_path(&filename)
                .first_raw()
                .map(|s| s.to_string())
        });

    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    let hash = hex::encode(hasher.finalize());
    let size_bytes = bytes.len() as i64;

    let base_path = PathBuf::from(&state.config.storage.base_path);

    if let Some((existing_id, _, _, _, _, existing_storage, _)) = existing {
        // Overwrite existing file
        let storage_rel = if let Some(rel) = existing_storage {
            rel
        } else {
            let id_str = existing_id.to_string();
            let prefix = &id_str[..2];
            format!("{}/{}/{}", user_id, prefix, id_str)
        };

        let full_path = base_path.join(&storage_rel);
        if let Some(p) = full_path.parent() {
            fs::create_dir_all(p)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))?;
        }
        let mut file = fs::File::create(&full_path)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
        file.write_all(&bytes)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
        file.flush()
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;

        sqlx::query(
            "UPDATE file_entries SET size_bytes = $1, sha256_hash = $2, storage_path = $3, mime_type = $4, updated_at = NOW() WHERE id = $5 AND user_id = $6"
        )
        .bind(size_bytes)
        .bind(&hash)
        .bind(&storage_rel)
        .bind(&mime)
        .bind(existing_id)
        .bind(user_id)
        .execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

        Ok(Response::builder()
            .status(StatusCode::NO_CONTENT)
            .header(header::ETAG, format!("\"{}\"", hash))
            .body(Body::empty())
            .expect("valid 204 response"))
    } else {
        // Create new file
        let file_id = Uuid::new_v4();
        let id_str = file_id.to_string();
        let prefix = &id_str[..2];
        let storage_rel = format!("{}/{}/{}", user_id, prefix, id_str);
        let full_path = base_path.join(&storage_rel);

        if let Some(p) = full_path.parent() {
            fs::create_dir_all(p)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))?;
        }
        let mut file = fs::File::create(&full_path)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
        file.write_all(&bytes)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
        file.flush()
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;

        sqlx::query(
            "INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, storage_path, is_trashed, created_at, updated_at) VALUES ($1, $2, $3, $4, 'file', $5, $6, $7, $8, false, NOW(), NOW())"
        )
        .bind(file_id)
        .bind(user_id)
        .bind(parent_id)
        .bind(&filename)
        .bind(&mime)
        .bind(size_bytes)
        .bind(&hash)
        .bind(&storage_rel)
        .execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

        Ok(Response::builder()
            .status(StatusCode::CREATED)
            .header(header::ETAG, format!("\"{}\"", hash))
            .body(Body::empty())
            .expect("valid 201 response"))
    }
}

/// DELETE — delete a file/folder (move to trash)
pub async fn webdav_delete(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(name): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();
    let (_, target) = resolve_path(pool, auth.claims.sub, &name).await?;

    if let Some((id, _, _, _, _, _, _)) = target {
        sqlx::query("UPDATE file_entries SET is_trashed = true, updated_at = NOW() WHERE id = $1 AND user_id = $2")
            .bind(id)
            .bind(auth.claims.sub)
            .execute(pool).await
            .map_err(|e| AppError::Internal(e.to_string()))?;

        Ok(StatusCode::NO_CONTENT)
    } else {
        Ok(StatusCode::NOT_FOUND)
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
    let (_, target) = resolve_path(pool, auth.claims.sub, &name).await?;

    if let Some((id, _, _, _, _, _, _)) = target {
        sqlx::query(
            "UPDATE file_entries SET name = $3, updated_at = NOW() WHERE id = $1 AND user_id = $2",
        )
        .bind(id)
        .bind(auth.claims.sub)
        .bind(destination)
        .execute(pool)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

        Ok(StatusCode::CREATED)
    } else {
        Ok(StatusCode::NOT_FOUND)
    }
}

/// COPY — duplicate file entry and storage content
pub async fn webdav_copy(
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
    let user_id = auth.claims.sub;
    let (parent_id, target) = resolve_path(pool, user_id, &name).await?;

    if let Some((_, _, entry_type, size_bytes, mime, storage_path, _)) = target {
        if entry_type == "folder" {
            // Create target folder
            sqlx::query(
                "INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, size_bytes, is_trashed, created_at, updated_at) VALUES ($1, $2, $3, $4, 'folder', 0, false, NOW(), NOW())"
            )
            .bind(Uuid::new_v4())
            .bind(user_id)
            .bind(parent_id)
            .bind(destination)
            .execute(pool).await
            .map_err(|e| AppError::Internal(e.to_string()))?;
        } else if let Some(src_rel) = storage_path {
            let base_path = PathBuf::from(&state.config.storage.base_path);
            let new_id = Uuid::new_v4();
            let id_str = new_id.to_string();
            let prefix = &id_str[..2];
            let new_rel = format!("{}/{}/{}", user_id, prefix, id_str);

            let src_full = base_path.join(&src_rel);
            let dst_full = base_path.join(&new_rel);

            if let Some(p) = dst_full.parent() {
                fs::create_dir_all(p)
                    .await
                    .map_err(|e| AppError::Internal(e.to_string()))?;
            }
            fs::copy(&src_full, &dst_full)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))?;

            sqlx::query(
                "INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, mime_type, size_bytes, storage_path, is_trashed, created_at, updated_at) VALUES ($1, $2, $3, $4, 'file', $5, $6, $7, false, NOW(), NOW())"
            )
            .bind(new_id)
            .bind(user_id)
            .bind(parent_id)
            .bind(destination)
            .bind(&mime)
            .bind(size_bytes)
            .bind(&new_rel)
            .execute(pool).await
            .map_err(|e| AppError::Internal(e.to_string()))?;
        }

        Ok(StatusCode::CREATED)
    } else {
        Ok(StatusCode::NOT_FOUND)
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
        .expect("valid OPTIONS response")
}

/// Dispatcher for root WebDAV requests (/webdav)
pub async fn dispatch_root(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    req: Request<Body>,
) -> Result<Response, AppError> {
    match req.method().as_str() {
        "OPTIONS" => Ok(options().await.into_response()),
        "PROPFIND" | "GET" => propfind(State(state), auth, headers, None).await,
        _ => Ok(StatusCode::METHOD_NOT_ALLOWED.into_response()),
    }
}

/// Dispatcher for subpath WebDAV requests (/webdav/*path)
pub async fn dispatch_path(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(path): Path<String>,
    req: Request<Body>,
) -> Result<Response, AppError> {
    let method = req.method().as_str().to_string();
    match method.as_str() {
        "OPTIONS" => Ok(options().await.into_response()),
        "PROPFIND" => propfind(State(state), auth, headers, Some(Path(path))).await,
        "MKCOL" => mkcol(State(state), auth, Path(path))
            .await
            .map(|r| r.into_response()),
        "GET" => webdav_get(State(state), auth, headers, Path(path)).await,
        "HEAD" => webdav_head(State(state), auth, Path(path)).await,
        "PUT" => {
            let body = req.into_body();
            webdav_put(State(state), auth, headers, Path(path), body).await
        }
        "DELETE" => webdav_delete(State(state), auth, Path(path))
            .await
            .map(|r| r.into_response()),
        "MOVE" => webdav_move(State(state), auth, headers, Path(path))
            .await
            .map(|r| r.into_response()),
        "COPY" => webdav_copy(State(state), auth, headers, Path(path))
            .await
            .map(|r| r.into_response()),
        _ => Ok(StatusCode::METHOD_NOT_ALLOWED.into_response()),
    }
}
