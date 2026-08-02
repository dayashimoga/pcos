# Architecture Decision Records

## ADR-001: Modular Monolith over Microservices
**Date**: 2026-08-02 | **Status**: Accepted

**Context**: Choosing between microservices and monolith for a self-hosted personal cloud.

**Decision**: Modular monolith — single Axum binary with 14 internal crates sharing one DB.

**Rationale**:
- Self-hosted users run on a single machine — microservices add unnecessary operational complexity
- Crate boundaries enforce module separation without network overhead
- Single binary = simple deployment (`docker compose up`)
- Can extract crates into services later if needed (crate boundaries are clean)

---

## ADR-002: Axum + SQLx over Actix + Diesel
**Date**: 2026-08-02 | **Status**: Accepted

**Context**: Selecting Rust web framework and ORM.

**Decision**: Axum (tower-based) + SQLx (async, compile-time checked SQL).

**Rationale**:
- Axum: tower ecosystem, native async, type-safe extractors, excellent middleware composition
- SQLx: zero-cost async, raw SQL with compile-time verification, no ORM overhead
- Both are maintained by the Tokio project — guaranteed ecosystem compatibility

---

## ADR-003: Flutter Web + BLoC over React/Vue
**Date**: 2026-08-02 | **Status**: Accepted

**Context**: Frontend framework for web UI with future native app potential.

**Decision**: Flutter Web with BLoC state management.

**Rationale**:
- Single codebase for web, Android, iOS, Windows, Linux, macOS
- BLoC provides testable, reactive state management
- Dart's type system prevents runtime errors
- Trade-off: larger initial WASM bundle (~2MB) vs. native apps from same codebase

---

## ADR-004: Argon2id for Password Hashing
**Date**: 2026-08-02 | **Status**: Accepted

**Context**: Choosing password hashing algorithm.

**Decision**: Argon2id (winner of Password Hashing Competition).

**Rationale**:
- Memory-hard: resistant to GPU/ASIC attacks
- PHC string format: self-describing hash strings (algorithm + params + salt + hash)
- `argon2` crate: well-maintained, audited Rust implementation
- Rejected: bcrypt (not memory-hard), scrypt (less standard), PBKDF2 (vulnerable to GPU)

---

## ADR-005: JWT with Refresh Token Rotation
**Date**: 2026-08-02 | **Status**: Accepted

**Context**: Stateless auth for API + device agent.

**Decision**: Short-lived JWT access tokens (15min) + single-use refresh tokens with rotation.

**Rationale**:
- Access tokens: stateless verification, no DB lookup per request
- Refresh tokens: stored as SHA-256 hashes in DB, single-use (rotation on each refresh)
- Compromise detection: if a refresh token is reused, all tokens for that user are revoked
- Trade-off: 15-min window of validity if access token is stolen

---

## ADR-006: Filesystem Storage with Hex-Prefix Sharding
**Date**: 2026-08-02 | **Status**: Accepted

**Context**: File storage backend for self-hosted deployment.

**Decision**: Local filesystem with SHA-256 content-addressable hex-prefix directory sharding.

**Rationale**:
- Self-hosted = user's own disks, no cloud storage costs
- Hex-prefix sharding (`ab/cd/abcdef...`) prevents filesystem inode exhaustion
- SHA-256 hashes enable deduplication and integrity verification
- Simple to backup (rsync), migrate, or inspect
- Rejected: S3 (adds cost/dependency), database BLOBs (poor performance at scale)

---

## ADR-007: TOTP over WebAuthn for Initial MFA
**Date**: 2026-08-02 | **Status**: Accepted

**Context**: Adding multi-factor authentication.

**Decision**: TOTP (RFC 6238) as the first MFA method.

**Rationale**:
- Universal compatibility: works with any authenticator app (Google, Authy, 1Password)
- Pure-Rust implementation: no external library dependency (HMAC-SHA1 is simple)
- Offline-capable: no internet required for code generation
- Future: WebAuthn/Passkeys planned as ADR-007b (requires browser API integration)

---

## ADR-008: Tantivy for Full-Text Search
**Date**: 2026-08-02 | **Status**: Accepted

**Context**: Search engine for file metadata indexing.

**Decision**: Tantivy (Rust-native search engine) with PostgreSQL ILIKE fallback.

**Rationale**:
- Tantivy: Lucene-equivalent performance, pure Rust, embedded (no external service)
- Graceful degradation: if Tantivy fails to initialize, search falls back to DB ILIKE
- Schema: indexed fields = name, content, mime_type, entry_type, user_id
- Trade-off: index size on disk (~50MB heap) vs. search speed (sub-millisecond)
