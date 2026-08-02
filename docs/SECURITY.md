# PCOS Security

## Authentication
- **Password Hashing**: Argon2id with random salts (PHC string format)
- **JWT Tokens**: HS256 signed, short-lived access (15 min), long-lived refresh (7 days)
- **Token Rotation**: Refresh tokens are single-use; each refresh generates a new pair
- **Token Revocation**: Refresh tokens stored as hashes in DB, revoked on logout or rotation

## Multi-Factor Authentication (MFA)
- **TOTP (RFC 6238)**: Time-based One-Time Passwords with 6-digit codes, 30-second step
- **Setup Flow**: Server generates 160-bit secret → returns Base32 secret + `otpauth://` provisioning URI
- **Verification**: Code must match current or adjacent time step (±1 for clock skew tolerance)
- **Disable**: Requires valid TOTP code to prevent unauthorized disablement
- **Implementation**: Pure-Rust HMAC-SHA1, no external TOTP library dependency
- **Storage**: TOTP secret stored in `users.totp_secret` (encrypted at rest recommended)

## Authorization & RBAC
- All API endpoints (except auth and health) require valid JWT Bearer token
- Users can only access their own resources (devices, files, etc.)
- Resource ownership verified in every query with `WHERE user_id = $1`
- **Roles**: `admin`, `user`, `viewer` — stored in `users.role`
- **Admin Guard**: `require_admin()` check on admin-only endpoints
- **Self-demotion prevention**: Admins cannot remove their own admin role
- **Storage Quotas**: Per-user configurable quota with admin management

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
