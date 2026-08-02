# PCOS Architecture

## System Overview

PCOS follows a modular monolith architecture for the backend (Sprint 1-3), designed to be split into microservices as scale requires. The system consists of:

1. **Flutter Web Client** — Responsive SPA for file management and administration
2. **Rust Backend** — Axum-based API server with modular crate architecture
3. **Device Agent** — Rust binary running on user devices for file sync (Sprint 3)
4. **Infrastructure** — PostgreSQL, Redis, NATS, Caddy reverse proxy

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Caddy (Reverse Proxy)                │
│                    TLS termination, routing                  │
└─────────┬──────────────────────────────────┬────────────────┘
          │ /api/*                           │ /*
          ▼                                  ▼
┌──────────────────┐              ┌──────────────────────┐
│  Rust Backend    │              │  Flutter Web Client  │
│  (pcos-server)   │              │  (nginx + SPA)       │
│                  │              └──────────────────────┘
│  ┌─────────────┐ │
│  │  Gateway    │ │     ┌──────────┐
│  │  (routes,   │ │────▶│PostgreSQL│
│  │  middleware)│ │     └──────────┘
│  └─────────────┘ │
│  ┌─────────────┐ │     ┌──────────┐
│  │  Auth       │ │────▶│  Redis   │
│  │  User       │ │     └──────────┘
│  │  Device     │ │
│  │  FileMeta   │ │     ┌──────────┐
│  │  Search     │ │────▶│  NATS    │
│  │  ...        │ │     └──────────┘
│  └─────────────┘ │
└──────────────────┘
          ▲
          │ Outbound WebSocket
┌─────────┴────────┐
│  Device Agent    │
│  (Rust binary)   │
│  ┌─────────────┐ │
│  │  SQLite     │ │
│  │  (local     │ │
│  │   cache)    │ │
│  └─────────────┘ │
└──────────────────┘
```

## Backend Crate Structure

```
backend/
├── Cargo.toml          # Workspace root
├── crates/
│   ├── common/         # Shared types, config, auth, DB
│   ├── auth/           # Authentication & authorization
│   ├── user/           # User profile management
│   ├── device/         # Device registration & tracking
│   ├── gateway/        # Main binary, router, middleware
│   └── (future crates for file, search, AI, etc.)
└── migrations/         # SQL migration files
```

## Key Design Decisions

### 1. Modular Monolith
All service modules compile into a single binary (`pcos-server`). This simplifies deployment, debugging, and testing while maintaining clean module boundaries. Services communicate via direct function calls, not network requests.

### 2. Outbound Agent Connections
Device agents connect outbound to the backend via WebSocket. This eliminates the need for port forwarding or VPN on user devices. The backend never initiates connections to agents.

### 3. JWT with Refresh Token Rotation
Access tokens are short-lived (15 min). Refresh tokens are single-use — each refresh generates a new pair and revokes the old. This limits the window of compromise if a token is stolen.

### 4. File System Storage
Files are stored directly on the filesystem (configurable base path). This avoids the complexity of S3/MinIO for self-hosted deployments while supporting volume mounts for Docker.

## Technology Stack

| Component | Technology | Justification |
|-----------|-----------|---------------|
| Backend | Rust + Axum | Performance, memory safety, strong typing |
| Frontend | Flutter Web | Single codebase for web + future mobile/desktop |
| Database | PostgreSQL 16 | ACID compliance, JSON support, mature ecosystem |
| Cache | Redis 7 | Session cache, rate limiting, pub/sub |
| Message Broker | NATS 2 | Lightweight, JetStream for persistence |
| Search | Tantivy (Sprint 5) | Rust-native full-text search |
| Reverse Proxy | Caddy 2 | Automatic HTTPS, simple config |
| Containers | Docker + Compose | Reproducible deployment |
| CI/CD | GitHub Actions | Integrated with repository |
