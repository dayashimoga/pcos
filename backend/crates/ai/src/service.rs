use crate::provider::AiProvider;
use pcos_common::error::{AppError, AppResult};
use sqlx::PgPool;
use uuid::Uuid;

/// Find duplicate files by SHA-256 hash.
pub async fn find_duplicates(pool: &PgPool, user_id: Uuid) -> AppResult<Vec<DuplicateGroup>> {
    let rows: Vec<(String, i64, i64)> = sqlx::query_as(
        r#"SELECT sha256_hash, COUNT(*) as cnt, SUM(size_bytes) as total_size
        FROM file_entries
        WHERE user_id = $1 AND entry_type = 'file' AND is_trashed = false AND sha256_hash IS NOT NULL
        GROUP BY sha256_hash HAVING COUNT(*) > 1
        ORDER BY total_size DESC"#
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Internal(e.to_string()))?;

    let mut groups = Vec::new();
    for (hash, count, total_size) in rows {
        let files: Vec<(Uuid, String, i64)> = sqlx::query_as(
            "SELECT id, name, size_bytes FROM file_entries WHERE user_id = $1 AND sha256_hash = $2 AND is_trashed = false"
        )
        .bind(user_id)
        .bind(&hash)
        .fetch_all(pool)
        .await?;

        groups.push(DuplicateGroup {
            hash,
            count,
            total_wasted_bytes: total_size - files.first().map(|f| f.2).unwrap_or(0),
            files: files
                .into_iter()
                .map(|(id, name, size)| DuplicateFile {
                    id,
                    name,
                    size_bytes: size,
                })
                .collect(),
        });
    }

    Ok(groups)
}

/// Auto-tag a file using AI.
pub async fn auto_tag(
    provider: &AiProvider,
    filename: &str,
    mime_type: &str,
) -> AppResult<Vec<String>> {
    provider.suggest_tags(filename, mime_type).await
}

/// Classify a file into a category.
pub async fn classify_file(
    provider: &AiProvider,
    filename: &str,
    mime_type: &str,
) -> AppResult<String> {
    let prompt = format!(
        "Classify the file '{}' (type: {}) into ONE of these categories: Document, Image, Video, Audio, Archive, Code, Spreadsheet, Presentation, Other. Respond with only the category name.",
        filename, mime_type
    );
    provider.generate(&prompt).await
}

#[derive(Debug, serde::Serialize)]
pub struct DuplicateGroup {
    pub hash: String,
    pub count: i64,
    pub total_wasted_bytes: i64,
    pub files: Vec<DuplicateFile>,
}

#[derive(Debug, serde::Serialize)]
pub struct DuplicateFile {
    pub id: Uuid,
    pub name: String,
    pub size_bytes: i64,
}
