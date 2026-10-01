//! S3-compatible API gateway — interoperability layer for rclone, aws-cli, and backup tools.
//!
//! Supports: ListBuckets, ListObjectsV2, GetObject (Range streaming), PutObject, DeleteObject, HeadObject.
//! Bucket = user namespace. Objects = user files.

use axum::{
    body::Body,
    extract::{Path, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use pcos_common::auth::AuthUser;
use pcos_common::{AppError, AppState};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct ListQuery {
    pub prefix: Option<String>,
    #[serde(rename = "max-keys")]
    pub max_keys: Option<i64>,
    #[serde(rename = "continuation-token")]
    pub continuation_token: Option<String>,
}

/// GET /s3/ — ListBuckets (returns user's root as single bucket)
pub async fn list_buckets(auth: AuthUser) -> impl IntoResponse {
    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Owner><ID>{uid}</ID><DisplayName>pcos-user</DisplayName></Owner>
  <Buckets>
    <Bucket><Name>pcos-files</Name><CreationDate>2026-01-01T00:00:00.000Z</CreationDate></Bucket>
  </Buckets>
</ListAllMyBucketsResult>"#,
        uid = auth.claims.sub
    );
    Response::builder()
        .header(header::CONTENT_TYPE, "application/xml")
        .body(Body::from(xml))
        .expect("valid S3 response")
}

/// GET /s3/pcos-files?list-type=2 — ListObjectsV2
pub async fn list_objects(
    State(state): State<AppState>,
    auth: AuthUser,
    Query(params): Query<ListQuery>,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let prefix = params.prefix.unwrap_or_default();
    let max = params.max_keys.unwrap_or(1000);
    let pattern = format!("{}%", prefix);

    let entries: Vec<(String, String, i64, String, Option<String>)> = sqlx::query_as(
        "SELECT name, entry_type, size_bytes, to_char(updated_at, 'YYYY-MM-DD\"T\"HH24:MI:SS\".000Z\"'), sha256_hash FROM file_entries WHERE user_id = $1 AND is_trashed = false AND name LIKE $2 ORDER BY name LIMIT $3"
    ).bind(auth.claims.sub).bind(&pattern).bind(max)
    .fetch_all(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let mut xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>pcos-files</Name>
  <Prefix>{}</Prefix>
  <MaxKeys>{}</MaxKeys>
  <IsTruncated>false</IsTruncated>"#,
        prefix, max
    );

    for (name, etype, size, modified, hash) in &entries {
        if etype == "folder" {
            xml.push_str(&format!(
                "\n  <CommonPrefixes><Prefix>{}/</Prefix></CommonPrefixes>",
                name
            ));
        } else {
            let etag = hash.as_deref().unwrap_or("0000000000000000");
            xml.push_str(&format!(
                "\n  <Contents><Key>{}</Key><Size>{}</Size><LastModified>{}</LastModified><ETag>&quot;{}&quot;</ETag><StorageClass>STANDARD</StorageClass></Contents>",
                name, size, modified, etag
            ));
        }
    }
    xml.push_str("\n</ListBucketResult>");

    Ok(Response::builder()
        .header(header::CONTENT_TYPE, "application/xml")
        .body(Body::from(xml))
        .expect("valid S3 response"))
}

/// GET /s3/pcos-files/*key — GetObject (supports Range streaming)
pub async fn get_object(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(key): Path<String>,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let filename = key.rsplit('/').next().unwrap_or(&key);

    let entry: Option<(Uuid, i64, Option<String>, Option<String>, Option<String>, String)> = sqlx::query_as(
        "SELECT id, size_bytes, mime_type, sha256_hash, storage_path, to_char(updated_at, 'Dy, DD Mon YYYY HH24:MI:SS GMT') FROM file_entries WHERE user_id = $1 AND name = $2 AND is_trashed = false AND entry_type = 'file' LIMIT 1"
    ).bind(auth.claims.sub).bind(filename)
    .fetch_optional(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let (_id, size_bytes, mime, hash, storage_path, modified) = match entry {
        Some(e) => e,
        None => {
            return Ok(Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::empty())
                .expect("valid S3 response"));
        }
    };

    let base_path = PathBuf::from(&state.config.storage.base_path);
    let full_path = match storage_path {
        Some(p) => base_path.join(p),
        None => {
            return Ok(Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::empty())
                .expect("valid S3 response"));
        }
    };

    let data = fs::read(&full_path)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to read file: {e}")))?;

    let content_type = mime.unwrap_or_else(|| "application/octet-stream".to_string());
    let total_size = data.len();
    let etag = format!("\"{}\"", hash.unwrap_or_default());

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
                    .header(header::LAST_MODIFIED, modified)
                    .header(header::ETAG, etag)
                    .body(Body::from(slice))
                    .expect("valid 206 response"));
            }
        }
    }

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CONTENT_LENGTH, size_bytes.to_string())
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::LAST_MODIFIED, modified)
        .header(header::ETAG, etag)
        .body(Body::from(data))
        .expect("valid S3 response"))
}

/// HEAD /s3/pcos-files/*key — HeadObject (file metadata)
pub async fn head_object(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(key): Path<String>,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let filename = key.rsplit('/').next().unwrap_or(&key);

    let entry: Option<(i64, Option<String>, Option<String>, String)> = sqlx::query_as(
        "SELECT size_bytes, mime_type, sha256_hash, to_char(updated_at, 'Dy, DD Mon YYYY HH24:MI:SS GMT') FROM file_entries WHERE user_id = $1 AND name = $2 AND is_trashed = false AND entry_type = 'file' LIMIT 1"
    ).bind(auth.claims.sub).bind(filename)
    .fetch_optional(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    match entry {
        Some((size, mime, hash, modified)) => Ok(Response::builder()
            .status(StatusCode::OK)
            .header(header::CONTENT_LENGTH, size.to_string())
            .header(
                header::CONTENT_TYPE,
                mime.unwrap_or_else(|| "application/octet-stream".to_string()),
            )
            .header(header::LAST_MODIFIED, modified)
            .header(header::ETAG, format!("\"{}\"", hash.unwrap_or_default()))
            .header(header::ACCEPT_RANGES, "bytes")
            .body(Body::empty())
            .expect("valid S3 response")),
        None => Ok(Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(Body::empty())
            .expect("valid S3 response")),
    }
}

/// PUT /s3/pcos-files/*key — PutObject
pub async fn put_object(
    State(state): State<AppState>,
    auth: AuthUser,
    headers: HeaderMap,
    Path(key): Path<String>,
    body: Body,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let user_id = auth.claims.sub;
    let filename = key
        .trim_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(&key)
        .to_string();

    let bytes = axum::body::to_bytes(body, 10 * 1024 * 1024 * 1024)
        .await
        .map_err(|e| AppError::Validation(format!("Upload body read failed: {e}")))?;

    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    let hash = hex::encode(hasher.finalize());
    let size_bytes = bytes.len() as i64;

    let mime = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .or_else(|| {
            mime_guess::from_path(&filename)
                .first_raw()
                .map(|s| s.to_string())
        });

    let base_path = PathBuf::from(&state.config.storage.base_path);

    // Check if existing file exists
    let existing: Option<(Uuid, Option<String>)> = sqlx::query_as(
        "SELECT id, storage_path FROM file_entries WHERE user_id = $1 AND name = $2 AND is_trashed = false AND entry_type = 'file' LIMIT 1"
    )
    .bind(user_id)
    .bind(&filename)
    .fetch_optional(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    if let Some((existing_id, existing_storage)) = existing {
        let storage_rel = existing_storage.unwrap_or_else(|| {
            let id_str = existing_id.to_string();
            format!("{}/{}/{}", user_id, &id_str[..2], id_str)
        });
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
    } else {
        let file_id = Uuid::new_v4();
        let id_str = file_id.to_string();
        let storage_rel = format!("{}/{}/{}", user_id, &id_str[..2], id_str);
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

        sqlx::query(
            "INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, storage_path, is_trashed, created_at, updated_at) VALUES ($1, $2, NULL, $3, 'file', $4, $5, $6, $7, false, NOW(), NOW())"
        )
        .bind(file_id)
        .bind(user_id)
        .bind(&filename)
        .bind(&mime)
        .bind(size_bytes)
        .bind(&hash)
        .bind(&storage_rel)
        .execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    }

    Ok(Response::builder()
        .status(StatusCode::OK)
        .header(header::ETAG, format!("\"{}\"", hash))
        .body(Body::empty())
        .expect("valid S3 response"))
}

/// DELETE /s3/pcos-files/*key — DeleteObject (trash)
pub async fn delete_object(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(key): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();
    let filename = key.rsplit('/').next().unwrap_or(&key);
    sqlx::query("UPDATE file_entries SET is_trashed = true, updated_at = NOW() WHERE user_id = $1 AND name = $2 AND is_trashed = false")
        .bind(auth.claims.sub).bind(filename)
        .execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(StatusCode::NO_CONTENT)
}
