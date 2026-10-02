# PCOS Gap Analysis — Comparison with Production Cloud Platforms

**Date**: 2026-08-04 | **Version**: 1.2.0  
**Benchmark**: Nextcloud, Synology DSM, Google Drive, Dropbox, CasaOS, Immich

---

## Executive Summary

PCOS has a **comprehensive backend** with 75+ API endpoints, 12+ crates, and strong architectural foundations. The primary gaps are in **frontend interactivity** (settings callbacks are no-ops, download doesn't save files), **test compilation** (fixed this sprint), and **deployment simplification**. The backend is significantly more complete than the frontend suggests.

---

## 🔴 Resolved Critical & P0 Architectural Gaps

### 1. Broken Mobile Onboarding (RESOLVED)
- **Previous State**: Mobile required typing `http://192.168.x.x` and optional code; camera QR scanning was missing; pairing generated a local client-only fallback code when backend was offline.
- **Resolution**:
  - Completely eliminated all client-side fake fallback code generation.
  - Implemented authoritative, short-lived (5-min TTL) pairing sessions in Cloudflare Durable Objects (`PairingHub`) and Rust `pcos-device` crate.
  - Added native camera QR code scanning via `mobile_scanner` with runtime permissions and visual scan overlay.
  - Added Candidate Device Approval on Web/Desktop dashboard (`[Approve] [Decline]`), single-use token invalidation, and rate-limiting (max 5 failed attempts lockout).
  - Manual Server/IP configuration moved strictly into `Advanced: Manual Server` for air-gapped deployments.

### 2. Dependency on Localhost / LAN IP Addressing (RESOLVED)
- **Previous State**: System depended on `localhost:8080` or hardcoded LAN IPs (`192.168.0.111`), which failed across different networks or behind container virtual NATs (`10.89.x.x`).
- **Resolution**:
  - Split Control Plane from Data Plane.
  - Deployed always-available Edge Control Plane on Cloudflare (`https://<project>.pages.dev`).
  - Implemented stable logical identity model (`PcosUri`: `pcos://cloud/<id>/device/<id>/node/<id>/file/<id>`).
  - Storage nodes discover true host LAN IP via UDP routing and register outbound to the edge without port forwarding.

### 3. Outbound-Only Node Agent & Connection Manager (RESOLVED)
- **Previous State**: PCs and laptops required inbound port access or complex VPN setups to act as cloud storage.
- **Resolution**:
  - Implemented `pcos-agent` with subcommands `doctor`, `enroll`, `start`, and `status`.
  - Built `ConnectionManager` dynamically resolving optimal routes: Direct LAN (<20ms latency) -> WireGuard P2P -> Encrypted Relay.
  - Added `DevicePresenceHub` Durable Object tracking real-time status and routing `play_on_tv` and `send_to_device` commands without proxying heavy file payloads.

### 4. Zero-Cost / Free-Tier Enforcement (RESOLVED)
- **Previous State**: Risk of unexpected cloud bills or exceeding provider quotas.
- **Resolution**:
  - Built `BudgetGuard` in Cloudflare Worker tracking Workers requests (100k/day), D1 reads (5M/mo), D1 writes (100k/day), DO requests (100k/day), and R2 storage (10GB).
  - Built `FreeTierBudgetCard` widget on Settings page displaying real-time usage percentages and hard budget mode state.
  - Hard budget mode ($0 limit) automatically disables optional cloud caching before limits are reached, guaranteeing zero bills.

### 5. Media Streaming & Availability Policies (RESOLVED)
- **Previous State**: No explicit file availability tier or remote Play-on-TV coordination.
- **Resolution**:
  - Implemented HTTP 206 Partial Content Range streaming with instant seek in Rust `pcos-streaming`.
  - Added `FileAvailabilitySheet` offering: This device only, Any of my devices, Always available remotely, Keep redundant copy, and Archive.
  - Added Play-on-TV remote controller: Phone signals TV to stream directly from storage node; phone never relays video data.


| Feature | PCOS | Nextcloud | Google Drive |
|---------|------|-----------|-------------|
| Self-hosted, no cloud dependency | ✅ | ✅ | ❌ |
| WebDAV + S3 compatibility | ✅ | ✅ (WebDAV) | ❌ |
| Adaptive video streaming (HLS) | ✅ | ❌ | ❌ |
| Delta sync (agent) | ✅ | ❌ | ❌ |
| LAN/P2P discovery | ✅ | ❌ | ❌ |
| AI auto-tagging (Ollama) | ✅ | ❌ | ✅ (cloud) |
| OCR + full-text search | ✅ | ✅ | ✅ |
| E2EE (server-side) | ✅ | ✅ | ❌ |
| Web Push notifications | ✅ | ✅ | ✅ |
| Plugin system | ✅ | ✅ | ❌ |
| i18n (10 locales) | ✅ | ✅ | ✅ |
| 6-platform native apps | ✅ | ✅ | ✅ |
| Kubernetes + Helm | ✅ | ✅ | N/A |
| Prometheus/Grafana | ✅ | Community | N/A |
