# PCOS Security Report

**Date**: 2026-08-04  
**Version**: 0.8.0

---

## Authentication & Authorization

| Control | Implementation | Status |
|---------|---------------|--------|
| Password Hashing | Argon2id (argon2 v0.5) | ✅ |
| JWT Access Tokens | jsonwebtoken v9, 15-min expiry | ✅ |
| Refresh Token Rotation | SHA-256 hashed, revoked on refresh | ✅ |
| Email Normalization | Lowercase + trim before storage/lookup | ✅ |
| Password Complexity | Min 8 chars, upper/lower/digit/special | ✅ |
| Email Validation | Regex + length check | ✅ |
| MFA (TOTP) | TOTP-based, backup codes supported | ✅ |
| RBAC | Role-based permissions (admin, user) | ✅ |
| Rate Limiting | governor crate on auth endpoints | ✅ |
| Audit Logging | All auth events logged to audit_log table | ✅ |

## Data Protection

| Control | Implementation | Status |
|---------|---------------|--------|
| Server-side Encryption | AES-256-GCM (encryption.rs) | ✅ |
| TLS | Caddy auto-HTTPS (production) | ✅ |
| Database Credentials | Environment variables, never hardcoded | ✅ |
| JWT Secret | Configurable, startup warning if default | ✅ |
| Refresh Token Storage | SHA-256 hash, never stored in plaintext | ✅ |

## Dependency Security

| Tool | Integration | Status |
|------|------------|--------|
| cargo-audit | CI pipeline (ci.yml) | ✅ |
| cargo-deny | CI pipeline (ci.yml, certification.yml) | ✅ |
| Secret Scanning | Regex patterns in certification.yml | ✅ |

## Infrastructure

| Control | Implementation | Status |
|---------|---------------|--------|
| Non-root Container | `USER pcos` (UID 1001) in Dockerfile | ✅ |
| Minimal Base Image | debian:bookworm-slim (runtime) | ✅ |
| Health Checks | Docker HEALTHCHECK on /health | ✅ |
| CORS | Configurable, restrictive in production | ✅ |
| Graceful Shutdown | SIGTERM handler with in-flight completion | ✅ |

## Known Risks

1. **Default JWT Secret**: The default fallback secret in config.rs is logged as a warning. Must be overridden in production via `PCOS_AUTH__JWT_SECRET`.
2. **CORS Allow-All in Development**: When `PCOS_CORS_ORIGINS` is empty or `*`, all origins are allowed. Must be restricted in production.
3. **SQLx Offline Mode**: SQL queries are validated at compile time via `.sqlx/` cache files, not at runtime against the database schema.
