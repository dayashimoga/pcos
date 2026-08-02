use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// Response DTO for user profile data.
#[derive(Debug, Serialize)]
pub struct ProfileResponse {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub storage_used_bytes: i64,
    pub device_count: i64,
}

/// Request DTO for updating user profile.
#[derive(Debug, Deserialize, Validate)]
pub struct UpdateProfileRequest {
    #[validate(length(min = 2, max = 100, message = "Display name must be 2-100 characters"))]
    pub display_name: Option<String>,
}
