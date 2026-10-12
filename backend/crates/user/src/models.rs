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

/// Request DTO for changing user password.
#[derive(Debug, Deserialize, Validate)]
pub struct ChangePasswordRequest {
    pub current_password: Option<String>,
    pub old_password: Option<String>,
    #[validate(length(min = 8, max = 128, message = "New password must be 8-128 characters"))]
    pub new_password: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_change_password_validation() {
        let req_valid = ChangePasswordRequest {
            current_password: Some("oldpassword123".to_string()),
            old_password: None,
            new_password: "newsecretpassword123".to_string(),
        };
        assert!(req_valid.validate().is_ok());

        let req_too_short = ChangePasswordRequest {
            current_password: Some("oldpassword123".to_string()),
            old_password: None,
            new_password: "short".to_string(),
        };
        assert!(req_too_short.validate().is_err());
    }
}


