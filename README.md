# PCOS — Personal Cloud Operating System

A **self-hosted personal cloud** built with Rust, Flutter, and PostgreSQL. Own your data with zero vendor lock-in.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Flutter Web  │     │ Device Agent│     │   Caddy     │
│   (Dart)     │────▶│   (Rust)    │     │  (Reverse   │
└──────┬───────┘     └──────┬──────┘     │   Proxy)    │
       │                    │            └──────┬──────┘
       ▼                    ▼                   │
┌──────────────────────────────────────────────────────┐
│              PCOS Gateway (Axum)                     │
│  ┌────┐ ┌────┐ ┌──────┐ ┌──────┐ ┌────┐ ┌────────┐ │
│  │Auth│ │User│ │Files │ │Search│ │ AI │ │Sharing │ │
│  ├────┤ ├────┤ ├──────┤ ├──────┤ ├────┤ ├────────┤ │
│  │Sync│ │Note│ │Backup│ │Analyt│ │Jobs│ │Devices │ │
│  └────┘ └────┘ └──────┘ └──────┘ └────┘ └────────┘ │
└──────┬───────────────┬───────────────┬───────────────┘
       │               │               │
  ┌────▼────┐   ┌──────▼──────┐  ┌─────▼─────┐
  │PostgreSQL│   │ File Storage│  │  Ollama   │
  │   16     │   │ (Filesystem)│  │ (Local AI)│
  └──────────┘   └─────────────┘  └───────────┘
```

## Features (90+ API Endpoints)

| Category | Features |
|----------|----------|
| **Files** | Upload (single + chunked), download, Range streaming, preview, folders, trash, versioning, storage stats |
| **Auth** | JWT with rotation, Argon2id, MFA/TOTP, RBAC (admin/user/viewer), audit logging |
| **Sharing** | Password-protected links, expiration, download limits |
| **Sync** | WebSocket with JWT, delta sync (rolling hash), LAN/P2P discovery |
| **AI** | Ollama (zero-cost local AI) — auto-tag, classify, duplicate detection |
| **Search** | Tantivy full-text + DB fallback, OCR text extraction (images/PDFs), EXIF metadata |
| **Compatibility** | WebDAV (PROPFIND/MKCOL/DELETE/MOVE), S3 gateway (ListBuckets/ListObjects/HeadObject/DeleteObject) |
| **Notifications** | In-app CRUD, SMTP email (templates), Web Push (RFC 8030) |
| **Backup** | Create/restore, scheduled, retention policies, verification, encrypted pg_dump |
| **Monitoring** | Prometheus + Grafana (12 panels), node/postgres/redis exporters |
| **Security** | SHA-256 token hashing, configurable CORS, rate limiting, input validation |

## Quick Start

### Prerequisites
- Docker & Docker Compose
- (Optional) Rust 1.79+ for local development
- (Optional) Flutter 3.24+ for frontend development

### Docker (3 commands)
```bash
git clone https://github.com/dayashimoga/pcos.git
cd pcos
cp .env.example .env     # Edit: change PCOS_JWT_SECRET and POSTGRES_PASSWORD
docker compose up -d
```

| Service | URL |
|---------|-----|
| Web UI | http://localhost |
| API | http://localhost/api/v1 |
| WebDAV | http://localhost/webdav |
| S3 | http://localhost/s3 |
| Grafana | http://localhost:3001 |
| Health | http://localhost/health |

### Local Development
```bash
# Backend
cd backend
cp .env.example .env
# Start Postgres: docker compose up -d postgres redis
cargo run --bin pcos-server

# Frontend
cd frontend
flutter pub get
flutter run -d chrome
```

## API

55+ endpoints across 12 services. See [API Reference](docs/API_REFERENCE.md).

```bash
# Register
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"MyPass123","display_name":"You"}'

# Login
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"MyPass123"}'
# → {"user":{...},"tokens":{"access_token":"...","refresh_token":"..."}}

# Upload file
curl -X POST http://localhost:8080/api/v1/files/upload \
  -H "Authorization: Bearer <token>" \
  -F "file=@document.pdf"
```

## Testing

```bash
# Backend unit tests (15 tests)
cd backend && cargo test --all

# Frontend BLoC tests (9 tests)
cd frontend && flutter test

# Integration tests (12 tests — requires running server)
cd backend && cargo test --test integration -- --ignored
```

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/ARCHITECTURE.md) | System design and crate structure |
| [API Reference](docs/API_REFERENCE.md) | All 55+ endpoints |
| [Database Design](docs/DATABASE_DESIGN.md) | 12 tables with schema |
| [Security](docs/SECURITY.md) | Auth, hashing, validation |
| [Deployment](docs/DEPLOYMENT.md) | Docker and bare-metal setup |
| [Operations](docs/OPERATIONS.md) | Runbook, troubleshooting, backup |
| [Implementation](docs/IMPLEMENTATION.md) | Feature checklist by crate |
| [Changelog](docs/CHANGELOG.md) | Version history |
| [TODO](docs/TODO.md) | Roadmap |

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Backend | Rust, Axum, SQLx, Tokio |
| Frontend | Flutter Web, BLoC, Dio |
| Database | PostgreSQL 16 |
| Cache | Redis 7 |
| AI | Ollama (local, zero cost) |
| Proxy | Caddy 2 |
| CI/CD | GitHub Actions |
| Container | Docker, multi-stage builds |

## License

AGPL-3.0
