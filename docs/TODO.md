# PCOS TODO

## Completed ✅

### High Priority (Done)
- [x] ~~Add streaming file download with Range header support~~ — v0.2.0
- [x] ~~Add per-user storage quota enforcement~~ — v0.2.0
- [x] ~~Add file preview endpoints~~ — v0.1.0
- [x] ~~Integrate Tantivy search index into AppState~~ — v0.3.0: SearchIndex in AppState, search/reindex handlers use Tantivy with DB fallback
- [x] ~~Implement actual backup file copy~~ — v0.3.0: copies all user files + manifest.json + pg_dump, restore copies back
- [x] ~~Implement Grafana dashboard templates~~ — v0.3.0: 12-panel dashboard (HTTP, storage, errors, DB pool, WS, jobs, AI)

### Medium Priority (Done)
- [x] ~~Add TOTP-based 2FA~~ — v0.2.0
- [x] ~~Add file versioning~~ — v0.2.0
- [x] ~~Multi-tenancy with RBAC~~ — v0.2.0

### Technical Debt (Done)
- [x] ~~Add integration tests~~ — 12 tests
- [x] ~~Create operations runbook~~ — `docs/OPERATIONS.md`
- [x] ~~Increase test coverage~~ — 36 tests total

---

## Remaining (Priority Order)

### High Priority
- [ ] Populate SQLx offline query cache (`.sqlx/`) for Docker builds (requires running DB)

### Medium Priority
- [ ] Add WebDAV compatibility layer
- [ ] Implement delta sync in agent (only upload changed bytes)
- [ ] Add LAN/P2P discovery for local sync
- [ ] Add OCR text extraction for images/PDFs
- [ ] Add email notifications (SMTP integration)
- [ ] Add web push notifications

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
