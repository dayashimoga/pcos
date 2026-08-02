//! S3-compatible API gateway — minimal subset for interoperability.
//!
//! Supports: ListBuckets, ListObjectsV2, GetObject, PutObject, DeleteObject, HeadObject.
//! Bucket = user namespace. Objects = user files.

use axum::{
    body::Body,
    extract::{Path, Query, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
};
use pcos_common::{AppState, AppError};
use pcos_common::auth::AuthUser;
use serde::Deserialize;
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
pub async fn list_buckets(
    auth: AuthUser,
) -> impl IntoResponse {
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
        .unwrap()
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

    let entries: Vec<(String, String, i64, String)> = sqlx::query_as(
        "SELECT name, entry_type, size_bytes, to_char(updated_at, 'YYYY-MM-DD\"T\"HH24:MI:SS\".000Z\"') FROM file_entries WHERE user_id = $1 AND is_trashed = false AND name LIKE $2 ORDER BY name LIMIT $3"
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

    for (name, etype, size, modified) in &entries {
        if etype == "folder" {
            xml.push_str(&format!("\n  <CommonPrefixes><Prefix>{}/</Prefix></CommonPrefixes>", name));
        } else {
            xml.push_str(&format!(
                "\n  <Contents><Key>{}</Key><Size>{}</Size><LastModified>{}</LastModified><StorageClass>STANDARD</StorageClass></Contents>",
                name, size, modified
            ));
        }
    }
    xml.push_str("\n</ListBucketResult>");

    Ok(Response::builder()
        .header(header::CONTENT_TYPE, "application/xml")
        .body(Body::from(xml))
        .unwrap())
}

/// HEAD /s3/pcos-files/:key — HeadObject (file metadata)
pub async fn head_object(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(key): Path<String>,
) -> Result<Response, AppError> {
    let pool = state.db.pool();
    let entry: Option<(i64, Option<String>, String)> = sqlx::query_as(
        "SELECT size_bytes, mime_type, to_char(updated_at, 'Dy, DD Mon YYYY HH24:MI:SS GMT') FROM file_entries WHERE user_id = $1 AND name = $2 AND is_trashed = false AND entry_type = 'file' LIMIT 1"
    ).bind(auth.claims.sub).bind(&key)
    .fetch_optional(pool).await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    match entry {
        Some((size, mime, modified)) => Ok(Response::builder()
            .status(StatusCode::OK)
            .header(header::CONTENT_LENGTH, size.to_string())
            .header(header::CONTENT_TYPE, mime.unwrap_or_else(|| "application/octet-stream".to_string()))
            .header(header::LAST_MODIFIED, modified)
            .body(Body::empty())
            .unwrap()),
        None => Ok(Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(Body::empty())
            .unwrap()),
    }
}

/// DELETE /s3/pcos-files/:key — DeleteObject (trash)
pub async fn delete_object(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(key): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    let pool = state.db.pool();
    sqlx::query("UPDATE file_entries SET is_trashed = true, updated_at = NOW() WHERE user_id = $1 AND name = $2 AND is_trashed = false")
        .bind(auth.claims.sub).bind(&key)
        .execute(pool).await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(StatusCode::NO_CONTENT)
}
