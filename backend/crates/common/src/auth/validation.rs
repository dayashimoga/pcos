use crate::error::{AppError, AppResult};

/// Validate password meets complexity requirements.
/// Rules: min 8 chars, max 128, at least 1 uppercase, 1 lowercase, 1 digit.
pub fn validate_password(password: &str) -> AppResult<()> {
    if password.len() < 8 {
        return Err(AppError::Validation("Password must be at least 8 characters".to_string()));
    }
    if password.len() > 128 {
        return Err(AppError::Validation("Password must be at most 128 characters".to_string()));
    }
    if !password.chars().any(|c| c.is_uppercase()) {
        return Err(AppError::Validation("Password must contain at least one uppercase letter".to_string()));
    }
    if !password.chars().any(|c| c.is_lowercase()) {
        return Err(AppError::Validation("Password must contain at least one lowercase letter".to_string()));
    }
    if !password.chars().any(|c| c.is_ascii_digit()) {
        return Err(AppError::Validation("Password must contain at least one digit".to_string()));
    }
    Ok(())
}

/// Validate and sanitize a file/folder name.
/// Prevents path traversal, null bytes, and excessively long names.
pub fn sanitize_filename(name: &str) -> AppResult<String> {
    let trimmed = name.trim();

    if trimmed.is_empty() {
        return Err(AppError::Validation("Name cannot be empty".to_string()));
    }
    if trimmed.len() > 255 {
        return Err(AppError::Validation("Name cannot exceed 255 characters".to_string()));
    }
    if trimmed.contains('\0') {
        return Err(AppError::Validation("Name cannot contain null bytes".to_string()));
    }
    // Block path traversal
    if trimmed.contains("..") || trimmed.contains('/') || trimmed.contains('\\') {
        return Err(AppError::Validation("Name cannot contain path separators or '..'".to_string()));
    }
    // Block names that are just dots
    if trimmed == "." || trimmed == ".." {
        return Err(AppError::Validation("Invalid name".to_string()));
    }
    // Block control characters
    if trimmed.chars().any(|c| c.is_control()) {
        return Err(AppError::Validation("Name cannot contain control characters".to_string()));
    }

    Ok(trimmed.to_string())
}

/// Validate email format (basic check).
pub fn validate_email(email: &str) -> AppResult<()> {
    let trimmed = email.trim();
    if trimmed.len() < 5 || trimmed.len() > 254 {
        return Err(AppError::Validation("Invalid email address".to_string()));
    }
    let at_count = trimmed.chars().filter(|c| *c == '@').count();
    if at_count != 1 {
        return Err(AppError::Validation("Invalid email address".to_string()));
    }
    let parts: Vec<&str> = trimmed.split('@').collect();
    if parts[0].is_empty() || parts[1].is_empty() || !parts[1].contains('.') {
        return Err(AppError::Validation("Invalid email address".to_string()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_password_validation() {
        assert!(validate_password("Abc12345").is_ok());
        assert!(validate_password("short").is_err()); // too short
        assert!(validate_password("alllowercase1").is_err()); // no uppercase
        assert!(validate_password("ALLUPPERCASE1").is_err()); // no lowercase
        assert!(validate_password("NoDigitsHere").is_err()); // no digit
        assert!(validate_password(&"a".repeat(129)).is_err()); // too long
    }

    #[test]
    fn test_filename_sanitization() {
        assert!(sanitize_filename("document.pdf").is_ok());
        assert!(sanitize_filename("my file (1).txt").is_ok());
        assert_eq!(sanitize_filename("  spaced  ").unwrap(), "spaced");
        assert!(sanitize_filename("").is_err());
        assert!(sanitize_filename("..").is_err());
        assert!(sanitize_filename("../etc/passwd").is_err());
        assert!(sanitize_filename("path/traversal").is_err());
        assert!(sanitize_filename("path\\traversal").is_err());
        assert!(sanitize_filename("null\0byte").is_err());
        assert!(sanitize_filename(&"a".repeat(256)).is_err());
    }

    #[test]
    fn test_email_validation() {
        assert!(validate_email("user@example.com").is_ok());
        assert!(validate_email("test@x.co").is_ok());
        assert!(validate_email("bad").is_err());
        assert!(validate_email("no@dot").is_err());
        assert!(validate_email("two@@at.com").is_err());
        assert!(validate_email("@missing.com").is_err());
    }
}
