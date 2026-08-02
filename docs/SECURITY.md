# PCOS Security

## Authentication
- **Password Hashing**: Argon2id with random salts (PHC string format)
- **JWT Tokens**: HS256 signed, short-lived access (15 min), long-lived refresh (7 days)
- **Token Rotation**: Refresh tokens are single-use; each refresh generates a new pair
- **Token Revocation**: Refresh tokens stored as hashes in DB, revoked on logout or rotation

## Authorization
- All API endpoints (except auth and health) require valid JWT Bearer token
- Users can only access their own resources (devices, files, etc.)
- Resource ownership verified in every query with `WHERE user_id = $1`

## Transport Security
- TLS 1.3 via Caddy reverse proxy (automatic HTTPS with Let's Encrypt)
- HSTS headers enforced
- Security headers: X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, Referrer-Policy

## Input Validation
- All request DTOs validated using the `validator` crate (Rust) and form validators (Flutter)
- Email format, password length, field lengths enforced
- SQL injection prevented via parameterized queries (sqlx)
- JSON deserialization with strict typing (serde)

## Rate Limiting
- Authentication endpoints protected by rate limiting (governor crate)
- Per-IP and per-account throttling

## Audit Logging
- All security-relevant actions logged to `audit_log` table
- Events: registration, login, failed login, logout, device changes
- Logs include user ID, action, details, timestamp

## Error Handling
- Internal errors are sanitized before returning to clients
- Database errors and stack traces never exposed in API responses
- Errors logged server-side with full context

## Dependency Security
- `cargo-audit` integrated in CI pipeline
- GitHub Actions checks for known vulnerabilities on every PR

## Secrets Management
- JWT secret loaded from environment variables
- Database credentials via environment variables
- No secrets in source code or configuration files
- `.env` files excluded from version control
