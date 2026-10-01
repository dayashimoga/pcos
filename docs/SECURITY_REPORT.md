# PCOS Security Report

**Date**: 2026-10-01  
**Version**: 0.9.0 (Hardened & Audited)

---

## Authentication & Authorization

| Control | Implementation | Status |
|---------|---------------|--------|
| Password Hashing | Argon2id (`argon2` v0.5) | ✅ Verified |
| JWT Access Tokens | `jsonwebtoken` v9, 15-min expiry | ✅ Verified |
| Refresh Token Rotation | SHA-256 hashed, revoked on refresh | ✅ Verified |
| Bootstrap Claim Protection | `PCOS_ADMIN_BOOTSTRAP_TOKEN` required when claiming initial admin role on fresh setups | ✅ Verified |
| WebSocket Header Auth | `Authorization: Bearer` and `Sec-WebSocket-Protocol: bearer, <token>` | ✅ Verified |
| Media Playback Scoped Tokens | 2-hour revocable HMAC-SHA256 token scoped strictly to user, file, and device | ✅ Verified |
| Admin Role Escalation Fixed | Removed legacy `email.starts_with("admin")` bypass; only explicit admin role assignment permitted | ✅ Verified |
| Email Normalization | Lowercase + trim before storage/lookup | ✅ Verified |
| Password Complexity | Min 8 chars, upper/lower/digit/special | ✅ Verified |
| MFA (TOTP) | TOTP-based (`totp-rs`), backup codes supported | ✅ Verified |
| RBAC | Role-based permissions (`admin`, `user`, `viewer`) | ✅ Verified |
| Rate Limiting | `governor` crate on auth and upload endpoints | ✅ Verified |

---

## Resolved Vulnerabilities (Production Audit)

1. **Arbitrary Admin Escalation Removed**: In `backend/crates/auth/src/service.rs`, any user whose email began with `"admin"` was granted full admin privileges. This has been removed. Role assignment is strictly explicit and verified.
2. **Fresh Deployment Bootstrap Race Condition**: On internet-facing deployments, an attacker could register first and claim admin access. PCOS now requires `PCOS_ADMIN_BOOTSTRAP_TOKEN` for the initial admin account creation.
3. **WebSocket JWT Leakage in URL / Logs**: WebSockets previously required tokens in URL query params (`?token=...`). PCOS sync engine now prioritizes standard `Authorization` headers and `Sec-WebSocket-Protocol` subprotocol negotiation.
4. **Default Grafana Admin/Admin Removed**: Docker Compose and setup scripts now auto-generate cryptographically secure passwords for Grafana, Postgres, JWT, and bootstrap tokens.
5. **Direct Media Exposure Blocked**: Remote streaming endpoints no longer expose internal file paths or require permanent credentials; they use short-lived, revocable playback tokens.

