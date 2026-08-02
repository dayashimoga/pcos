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

## Features

| Category | Features |
|----------|----------|
| **Files** | Upload (single + chunked), download, preview, folders, breadcrumbs, trash, restore, storage stats |
| **Auth** | JWT with rotation, Argon2id passwords, password validation, audit logging |
| **Sharing** | Password-protected links, expiration, download limits, real file download |
| **Sync** | WebSocket with JWT auth, change tracking, conflict resolution |
| **AI** | Ollama integration — auto-tag, classify, duplicate detection, smart search |
| **Search** | Database ILIKE with Tantivy index ready |
| **Devices** | Registration, heartbeat, online status |
| **Notifications** | CRUD with unread count, system notifications |
| **Backup** | Create, restore, scheduled backups |
| **Analytics** | Overview, storage breakdown, activity timeline, Prometheus metrics |
| **Security** | SHA-256 token hashing, filename sanitization, configurable CORS, error sanitization |

## Quick Start

### Prerequisites
- Docker & Docker Compose
- (Optional) Rust 1.79+ for local development
- (Optional) Flutter 3.24+ for frontend development

### Docker (Recommended)
```bash
# Clone
git clone https://github.com/dayashimoga/pcos.git
cd pcos

# Configure
cp backend/.env.example backend/.env
# Edit backend/.env — change JWT_SECRET!

# Start
docker compose up -d

# Verify
curl http://localhost:8080/health
# → {"status":"healthy","version":"0.1.0","uptime_secs":5}

# Access UI
open http://localhost:3000
```

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
