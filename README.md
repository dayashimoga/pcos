# PCOS — Personal Cloud Operating System

[![CI](https://github.com/pcos/pcos/actions/workflows/ci.yml/badge.svg)](https://github.com/pcos/pcos/actions/workflows/ci.yml)

> **A production-grade, self-hosted Personal Cloud Operating System** for secure file management, synchronization, and AI-powered organization across all your devices.

## Features

- 🔐 **Secure Authentication** — JWT with refresh token rotation, Argon2id password hashing
- 📱 **Multi-Device** — Register and manage unlimited devices across all platforms
- 🖥️ **Responsive Web UI** — Premium dark theme, responsive from mobile to desktop
- 🐳 **Docker-First** — One command deployment with Docker Compose
- 🔄 **CI/CD** — Automated testing, building, and release via GitHub Actions
- 📝 **Audit Logging** — Complete security event trail

## Quick Start

```bash
# Clone and start
git clone https://github.com/pcos/pcos.git
cd pcos
cp backend/.env.example .env
# Edit .env — change PCOS_JWT_SECRET!
docker compose up -d
```

Open **http://localhost** and create your account.

## Documentation

| Document | Description |
|----------|-------------|
| [Requirements](docs/REQUIREMENTS.md) | Functional & non-functional requirements |
| [Architecture](docs/ARCHITECTURE.md) | System design and tech stack |
| [API Reference](docs/API_REFERENCE.md) | REST API documentation |
| [Database Design](docs/DATABASE_DESIGN.md) | Schema and ERD |
| [Security](docs/SECURITY.md) | Security measures |
| [Deployment](docs/DEPLOYMENT.md) | Docker deployment guide |
| [Development Guide](docs/DEVELOPMENT_GUIDE.md) | Local development setup |
| [Implementation](docs/IMPLEMENTATION.md) | Sprint progress |
| [Changelog](docs/CHANGELOG.md) | Version history |
| [TODO](docs/TODO.md) | Upcoming work |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Rust, Axum, SQLx, PostgreSQL |
| Frontend | Flutter Web, BLoC, Dio |
| Cache | Redis |
| Messaging | NATS |
| Proxy | Caddy |
| CI/CD | GitHub Actions |
| Containers | Docker, Docker Compose |

## License

AGPL-3.0
