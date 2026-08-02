# PCOS TODO

## Next Steps (Priority Order)

### High Priority
- [ ] Integrate Tantivy search index into AppState for full-text search
- [ ] Add streaming file download with Range header support for large files
- [ ] Implement actual backup file copy (currently metadata-only)
- [ ] Add file preview endpoints (image thumbnails, PDF rendering)
- [ ] Add per-user storage quota enforcement (quota table + middleware)

### Medium Priority
- [ ] Add TOTP-based 2FA (two-factor authentication)
- [ ] Add WebDAV compatibility layer
- [ ] Implement delta sync in agent (only upload changed bytes)
- [ ] Add LAN/P2P discovery for local sync
- [ ] Add file versioning (keep N versions)
- [ ] Add OCR text extraction for images/PDFs
- [ ] Add email notifications (SMTP integration)
- [ ] Add web push notifications
- [ ] Implement Grafana dashboard templates

### Low Priority / Future
- [ ] Native Flutter apps (Android, iOS, Windows, Linux, macOS)
- [ ] End-to-end encryption (E2EE) with key management
- [ ] SSO/OIDC/SAML integration
- [ ] LDAP/Active Directory support
- [ ] Multi-tenancy with RBAC
- [ ] S3-compatible gateway
- [ ] SMB/NFS bridge
- [ ] Plugin system with public SDK
- [ ] Face clustering in photos
- [ ] Video/audio streaming engine
- [ ] Localization (i18n)
- [ ] Accessibility (a11y) audit

### Technical Debt
- [ ] Increase test coverage to 90%+ (currently ~24 tests)
- [ ] Add integration tests (test database + API calls end-to-end)
- [ ] Populate SQLx offline query cache for Docker builds
- [ ] Add load/stress testing with k6 or similar
- [ ] Add ADRs (Architecture Decision Records)
- [ ] Create operations runbook
- [ ] Create user guide
