# PCOS Architecture

## System Overview

PCOS features a hybrid distributed architecture that splits the **Always-Available Edge Control Plane** from the **User-Owned Local Data Plane**:

1. **Cloudflare Edge Control Plane (Production)**:
   - **Flutter Web Client (Pages/Static Assets)**: Global CDN-hosted responsive SPA (`https://<project>.pages.dev`).
   - **Edge Workers**: Low-latency authentication, connection broker, device registry, and free-tier usage tracking.
   - **Durable Objects (`PairingHub`, `DevicePresenceHub`)**: In-memory WebSocket presence, real-time pairing approvals, and command dispatch (`play_on_tv`, `send_to_device`).
   - **D1 Database**: Authoritative logical identity and location metadata.
   - **R2 Cloud Cache (Optional)**: Free-tier enclosed encrypted cloud cache for "Always Available" files.

2. **PCOS Storage Nodes (User Hardware)**:
   - **Outbound Agent (`pcos-agent`)**: Runs on Windows, macOS, Linux, and NAS devices. Establishes outbound TLS/WSS connections to the Control Plane without router port forwarding.
   - **Local Storage & Compute**: Keeps multi-gigabyte files, block-level delta chunking, Tantivy search, OCR, local Ollama AI, and FFmpeg hardware-accelerated transcoding strictly local.

3. **Local Monolith (Self-Hosted / Offline LAN / Dev)**:
   - Axum-based Rust backend (`pcos-server`), PostgreSQL, Redis, NATS, and Caddy reverse proxy for complete air-gapped self-hosting.

## Distributed Architecture Diagram

```
                    INTERNET
                       │
             https://<pcos>.pages.dev
                       │
┌─────────────────────────────────────────────────────────────┐
│          CLOUDFLARE EDGE / FREE-FIRST CONTROL PLANE         │
│                                                             │
│  Pages / Static Assets  ─▶  Flutter Web (Wasm/Canvas)       │
│  Edge Workers           ─▶  Auth / Routing / Token Minting  │
│  Durable Objects        ─▶  WS Presence & Pairing Hub       │
│  D1 Database            ─▶  Logical Identities & Metadata   │
│  R2 Storage (Optional)  ─▶  Encrypted Cloud Cache (<=10GB)  │
└──────────────────────────────┬──────────────────────────────┘
                               │ Outbound TLS/WSS
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     CONNECTION MANAGER                      │
│       Selects Direct LAN ─▶ WireGuard P2P ─▶ Relay Tunnel   │
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
                ▼                             ▼
   ┌──────────────────────────┐  ┌──────────────────────────┐
   │    Desktop PCOS Node     │  │     Laptop PCOS Node     │
   │  ┌────────────────────┐  │  │  ┌────────────────────┐  │
   │  │ FFmpeg / Tantivy   │  │  │  │ Watcher / Delta    │  │
   │  │ Local SSD Storage  │  │  │  │ Local NVMe Storage │  │
   │  └────────────────────┘  │  │  └────────────────────┘  │
   └──────────────────────────┘  └──────────────────────────┘
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
