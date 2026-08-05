use crate::models::{
    AuthResponse, LoginRequest, LogoutRequest, RefreshToken, RefreshTokenRequest, RegisterRequest,
    User,
};
use pcos_common::auth::jwt::generate_token_pair;
use pcos_common::auth::password::{hash_password, verify_password};
use pcos_common::error::{AppError, AppResult};
use pcos_common::AppState;
use sqlx::PgPool;
use uuid::Uuid;

/// Register a new user account.
pub async fn register(
    pool: &PgPool,
    state: &AppState,
    req: RegisterRequest,
) -> AppResult<AuthResponse> {
    // Validate and normalize inputs
    let email = req.email.trim().to_lowercase();
    pcos_common::auth::validation::validate_email(&email)?;
    pcos_common::auth::validation::validate_password(&req.password)?;

    if req.display_name.trim().is_empty() || req.display_name.len() > 100 {
        return Err(AppError::Validation(
            "Display name must be 1-100 characters".to_string(),
        ));
    }

    // Check if email already exists
    let existing =
        sqlx::query_scalar::<_, bool>("SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)")
            .bind(&email)
            .fetch_one(pool)
            .await
            .map_err(|e| AppError::Internal(format!("Database query failed: {e}")))?;

    if existing {
        return Err(AppError::Conflict("Email already registered".to_string()));
    }

    // Hash password
    let password_hash = hash_password(&req.password)
        .map_err(|e| AppError::Internal(format!("Password hashing failed: {e}")))?;

    // First user or admin email automatically gets admin role
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
        .fetch_one(pool)
        .await
        .unwrap_or(0);

    let role = if count == 0 || email.starts_with("admin") {
        "admin"
    } else {
        "user"
    };

    // Create user
    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (id, email, display_name, password_hash, role, is_active, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, true, NOW(), NOW())
        RETURNING *
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(&email)
    .bind(&req.display_name)
    .bind(&password_hash)
    .bind(role)
    .fetch_one(pool)
    .await?;

    // Generate tokens
    let tokens = generate_token_pair(user.id, &user.email, &state.config.auth)?;

    // Store refresh token hash
    store_refresh_token(pool, user.id, &tokens.refresh_token).await?;

    // Audit log
    log_audit(
        pool,
        user.id,
        "user.registered",
        &format!("User {} registered", user.email),
    )
    .await;

    tracing::info!(user_id = %user.id, email = %user.email, "User registered");

    Ok(AuthResponse {
        user: user.into(),
        tokens,
    })
}

/// Authenticate a user and return tokens.
pub async fn login(pool: &PgPool, state: &AppState, req: LoginRequest) -> AppResult<AuthResponse> {
    // Find user by email (normalize to lowercase)
    let email = req.email.trim().to_lowercase();
    let user =
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE email = $1 AND is_active = true")
            .bind(&email)
            .fetch_optional(pool)
            .await?
            .ok_or_else(|| AppError::Unauthorized("Invalid email or password".to_string()))?;

    // Verify password
    let valid = verify_password(&req.password, &user.password_hash)
        .map_err(|e| AppError::Internal(format!("Password verification failed: {e}")))?;

    if !valid {
        log_audit(
            pool,
            user.id,
            "auth.login_failed",
            "Invalid password attempt",
        )
        .await;
        return Err(AppError::Unauthorized(
            "Invalid email or password".to_string(),
        ));
    }

    // Generate tokens
    let tokens = generate_token_pair(user.id, &user.email, &state.config.auth)?;

    // Store refresh token
    store_refresh_token(pool, user.id, &tokens.refresh_token).await?;

    // Audit log
    log_audit(pool, user.id, "auth.login", "User logged in").await;

    tracing::info!(user_id = %user.id, "User logged in");

    Ok(AuthResponse {
        user: user.into(),
        tokens,
    })
}

/// Refresh an access token using a valid refresh token.
pub async fn refresh(
    pool: &PgPool,
    state: &AppState,
    req: RefreshTokenRequest,
) -> AppResult<pcos_common::auth::jwt::TokenPair> {
    // Validate the refresh token JWT
    let token_data =
        pcos_common::auth::jwt::validate_token(&req.refresh_token, &state.config.auth.jwt_secret)?;
    let claims = token_data.claims;

    // Check if refresh token is in the database and not revoked
    let token_hash = hash_token(&req.refresh_token);
    let stored = sqlx::query_as::<_, RefreshToken>(
        "SELECT * FROM refresh_tokens WHERE token_hash = $1 AND revoked = false AND expires_at > NOW()"
    )
    .bind(&token_hash)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| AppError::Unauthorized("Invalid or expired refresh token".to_string()))?;

    // Revoke the old refresh token (rotation)
    sqlx::query("UPDATE refresh_tokens SET revoked = true WHERE id = $1")
        .bind(stored.id)
        .execute(pool)
        .await?;

    // Generate new token pair
    let tokens = generate_token_pair(claims.sub, &claims.email, &state.config.auth)?;

    // Store new refresh token
    store_refresh_token(pool, claims.sub, &tokens.refresh_token).await?;

    tracing::info!(user_id = %claims.sub, "Token refreshed");

    Ok(tokens)
}

/// Logout by revoking the refresh token.
pub async fn logout(pool: &PgPool, req: LogoutRequest) -> AppResult<()> {
    let token_hash = hash_token(&req.refresh_token);

    let result = sqlx::query("UPDATE refresh_tokens SET revoked = true WHERE token_hash = $1")
        .bind(&token_hash)
        .execute(pool)
        .await?;

    if result.rows_affected() == 0 {
        tracing::warn!("Logout attempted with unknown refresh token");
    }

    Ok(())
}

/// Store a hashed refresh token in the database.
async fn store_refresh_token(pool: &PgPool, user_id: Uuid, token: &str) -> AppResult<()> {
    let token_hash = hash_token(token);
    let expires_at = chrono::Utc::now() + chrono::Duration::days(7);

    sqlx::query(
        r#"
        INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, revoked, created_at)
        VALUES ($1, $2, $3, $4, false, NOW())
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(&token_hash)
    .bind(expires_at)
    .execute(pool)
    .await?;

    Ok(())
}

/// Create a SHA-256 hash of a token for secure storage.
fn hash_token(token: &str) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    hex::encode(hasher.finalize())
}

/// Write an entry to the audit log (fire-and-forget, errors are logged but not propagated).
async fn log_audit(pool: &PgPool, user_id: Uuid, action: &str, details: &str) {
    let result = sqlx::query(
        "INSERT INTO audit_log (id, user_id, action, details, created_at) VALUES ($1, $2, $3, $4, NOW())"
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(action)
    .bind(details)
    .execute(pool)
    .await;

    if let Err(e) = result {
        tracing::error!(error = %e, action = action, "Failed to write audit log");
    }
}
