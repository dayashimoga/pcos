use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

#[derive(Debug, Clone, sqlx::FromRow, Serialize)]
pub struct ShareLink {
    pub id: Uuid,
    pub user_id: Uuid,
    pub file_entry_id: Uuid,
    pub token: String,
    pub permission: String, // "view" or "download"
    pub password_hash: Option<String>,
    pub expires_at: Option<DateTime<Utc>>,
    pub max_downloads: Option<i32>,
    pub download_count: i32,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, Validate)]
pub struct CreateShareRequest {
    pub file_entry_id: Uuid,
    #[validate(length(min = 1))]
    pub permission: String,
    pub password: Option<String>,
    pub expires_in_hours: Option<i64>,
    pub max_downloads: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateShareRequest {
    pub permission: Option<String>,
    pub password: Option<String>,
    pub expires_in_hours: Option<i64>,
    pub max_downloads: Option<i32>,
    pub is_active: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct ShareResponse {
    pub id: Uuid,
    pub file_entry_id: Uuid,
    pub token: String,
    pub url: String,
    pub permission: String,
    pub has_password: bool,
    pub expires_at: Option<DateTime<Utc>>,
    pub max_downloads: Option<i32>,
    pub download_count: i32,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
}

impl ShareLink {
    pub fn to_response(&self, base_url: &str) -> ShareResponse {
        ShareResponse {
            id: self.id,
            file_entry_id: self.file_entry_id,
            token: self.token.clone(),
            url: format!("{}/shared/{}", base_url, self.token),
            permission: self.permission.clone(),
            has_password: self.password_hash.is_some(),
            expires_at: self.expires_at,
            max_downloads: self.max_downloads,
            download_count: self.download_count,
            is_active: self.is_active,
            created_at: self.created_at,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct SharedFileInfo {
    pub name: String,
    pub entry_type: String,
    pub mime_type: Option<String>,
    pub size_bytes: i64,
    pub permission: String,
}
