# PCOS Cloudflare Edge Control Plane Architecture

## 1. Architectural Philosophy: Edge Brain, Local Body

PCOS separates the **Control Plane** from the **Data Plane**. The Cloudflare-hosted Edge Control Plane acts as the always-available, zero-maintenance coordination brain, while user-owned physical hardware (PCs, laptops, NAS, servers) acts as the high-capacity, private data and compute nodes.

```
                    INTERNET
                       |
             https://<pcos>.pages.dev
                       |
+--------------------------------------------------+
|       CLOUDFLARE EDGE / FREE-FIRST CONTROL       |
|                                                  |
| Pages/Static Assets -> Flutter Web (Wasm/Canvas) |
| Workers            -> API / Auth / Broker        |
| Durable Objects    -> WS / Presence / Pairing    |
| D1                 -> Logical Identities & State |
| KV                 -> Small cache / config ONLY  |
| R2 (Optional)      -> Encrypted Cloud Cache      |
+-------------------------+------------------------+
                          |
                    HTTPS / WSS
                          |
                CONNECTION MANAGER
                          |
       +------------------+------------------+
       |                  |                  |
      LAN             P2P/WireGuard       Tunnel/
    direct               direct           Relay
       |                  |                  |
       +------------------+------------------+
                          |
        +-----------------+-----------------+
        |                 |                 |
     Desktop            Laptop             NAS
    PCOS Agent         PCOS Agent        PCOS Agent
        |                 |                 |
      HDD/SSD           HDD/SSD          HDD/SSD
        +-----------------+-----------------+
                          |
                  USER-OWNED DATA
                          |
       +------------------+------------------+
       |                  |                  |
     Mobile             Tablet              TV
```

### Key Principles
1. **Never Proxy Bulk Data Through Workers**: 20GB video transfers, bulk photo uploads, FFmpeg video transcoding, and Tantivy full-text indexation remain strictly local on PCOS storage nodes.
2. **Always-Available Discovery**: Users access their personal cloud from any browser or mobile app worldwide via `https://<project>.pages.dev` or a custom vanity domain without configuring routers, static IPs, or port forwarding.
3. **Strict Free-Tier Enclosure**: Edge coordination operates 100% within Cloudflare's free tiers (100k Worker requests/day, 5M D1 reads/mo, 100k D1 writes/day, 10GB R2 storage). A hard budget mode ($0 limit) guarantees zero accidental charges.

---

## 2. Component Breakdown

### 2.1 Cloudflare Pages / Static Assets
- Hosts the compiled production Flutter Web application (`build/web`).
- Features immutable asset caching (`Cache-Control: public, max-age=31536000, immutable`), strict Content Security Policy (CSP), permissions policy, and SPA routing rewrites (`/* -> /index.html 200`).

### 2.2 Cloudflare Workers (Routing & API)
- Serves as the central API gateway.
- Handles:
  - User registration, login, and rotating JWT/refresh token lifecycle.
  - Device pairing session initiation, candidate claiming, and owner approval.
  - Connection resolution (`/api/v1/devices/resolve/:id`) providing optimal routing advice.
  - Free-Tier Guard metrics tracking.

### 2.3 Durable Objects
- **`PairingHub`**: Stateful in-memory actor managing short-lived (5-minute TTL) pairing sessions, real-time WebSocket approval notifications, and instant single-use token consumption.
- **`DevicePresenceHub`**: Tracks real-time heartbeats, online/offline status, public and LAN subnet IPs, and routes control commands (`play_on_tv`, `send_to_device`) to target devices without transferring media data.

### 2.4 Cloudflare D1 (Serverless Relational SQLite)
Stores authoritative control plane metadata:
- `users`: User profiles, PBKDF2/SHA-256 password hashes, roles.
- `cloud_identities`: Stable logical cloud IDs (`pcos://cloud/<id>`).
- `device_identities`: Enrolled devices, hardware type, OS, agent version.
- `storage_nodes`: Storage root mappings and capacities.
- `file_locations`: Distributed logical file tracking, availability policies, cloud cache status.
- `pairing_sessions`: Server-authoritative pairing state with attempt counters.
- `refresh_tokens`: Revocable hashed refresh tokens with automatic rotation.
- `free_tier_usage`: Daily/monthly request and byte counters.

### 2.5 Cloudflare R2 (Optional Encrypted Cloud Cache)
- Provides an optional "Always Available" cache for selected critical files.
- Files are encrypted at rest with client-derived keys before upload.
- Hard-capped at 10 GB to maintain zero cost.

---

## 3. Provider Abstractions (No Lock-In)

PCOS defines clear provider interfaces (`IControlPlaneProvider`, `IPairingBroker`, `IPresenceBroker`, `IStorageProvider`) in `cloudflare/src/types.ts`. The control plane can run on Cloudflare Workers, Fastly Compute, Fly.io, or on-premises Docker containers with zero business logic rewrite.
