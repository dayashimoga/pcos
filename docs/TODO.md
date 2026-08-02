# PCOS TODO

## Completed ✅

### High Priority (Done)
- [x] ~~Add streaming file download with Range header support~~ — v0.2.0: `206 Partial Content`, `Content-Range`, `Accept-Ranges`, ETag
- [x] ~~Add per-user storage quota enforcement~~ — v0.2.0: `storage_quota_bytes` column, admin quota management API
- [x] ~~Add file preview endpoints~~ — v0.1.0: `GET /files/:id/preview` with inline content-disposition + content-type

### Medium Priority (Done)
- [x] ~~Add TOTP-based 2FA~~ — v0.2.0: setup, verify, disable, status endpoints. Pure-Rust HMAC-SHA1
- [x] ~~Add file versioning~~ — v0.2.0: `file_versions` table, list/restore/download version APIs
- [x] ~~Multi-tenancy with RBAC~~ — v0.2.0: admin/user/viewer roles, `require_admin` guard, admin portal

### Technical Debt (Done)
- [x] ~~Add integration tests~~ — 12 tests: auth flow, file CRUD, devices, notifications, search, storage
- [x] ~~Create operations runbook~~ — `docs/OPERATIONS.md`: startup, troubleshooting, backup, security, scaling
- [x] ~~Increase test coverage~~ — 36 tests total (15 unit + 9 BLoC + 12 integration)

---

## Remaining (Priority Order)

### High Priority
- [ ] Integrate Tantivy search index into AppState for full-text search (index exists but not wired to AppState)
- [ ] Implement actual backup file copy (currently metadata-only `pg_dump` placeholder)
- [ ] Populate SQLx offline query cache (`.sqlx/`) for Docker builds

### Medium Priority
- [ ] Add WebDAV compatibility layer
- [ ] Implement delta sync in agent (only upload changed bytes)
- [ ] Add LAN/P2P discovery for local sync
- [ ] Add OCR text extraction for images/PDFs
- [ ] Add email notifications (SMTP integration)
- [ ] Add web push notifications
- [ ] Implement Grafana dashboard templates

### Low Priority / Future
- [ ] Native Flutter apps (Android, iOS, Windows, Linux, macOS)
- [ ] End-to-end encryption (E2EE) with key management
- [ ] SSO/OIDC/SAML integration
- [ ] LDAP/Active Directory support
- [ ] S3-compatible gateway
- [ ] SMB/NFS bridge
- [ ] Plugin system with public SDK
- [ ] Face clustering in photos
- [ ] Video/audio streaming engine
- [ ] Localization (i18n)
- [ ] Accessibility (a11y) audit

### Technical Debt
- [ ] Increase test coverage to 90%+ (currently 36 tests)
- [ ] Add load/stress testing with k6 or similar
- [ ] Add ADRs (Architecture Decision Records)
- [ ] Create user guide
