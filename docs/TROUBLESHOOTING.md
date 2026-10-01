# PCOS Troubleshooting & Diagnostics Guide

This guide provides actionable steps for diagnosing, troubleshooting, and resolving issues in PCOS deployments.

---

## 1. PCOS Doctor Diagnostics
Run the PCOS Doctor command to inspect all subsystems:
```bash
# Via script
./doctor.sh        # Linux/macOS
.\doctor.ps1       # Windows

# Or check endpoint
curl -H "Authorization: Bearer <TOKEN>" http://localhost:8080/api/v1/health
```

### Common Doctor Checks:
- **Database (PostgreSQL)**: Confirms connection pool health, query response time, and applied migrations.
- **Cache (Redis)**: Validates ping response, token revocation cache, and session store.
- **Message Broker (NATS)**: Verifies event streaming and worker pub/sub connectivity.
- **Storage**: Checks disk usage, base path write permissions, and temp directory quotas.
- **Search (Tantivy)**: Verifies index directory accessibility and schema locks.
- **FFmpeg & ffprobe**: Checks binary presence in PATH and hardware acceleration modules (`/dev/dri` for VAAPI).

---

## 2. Authentication & Ingress Issues

### First-Time Admin Bootstrap Token
- When deploying an internet-facing PCOS instance, `PCOS_ADMIN_BOOTSTRAP_TOKEN` must match the token provided in the initial setup screen or registration API.
- If registration fails with `403 Forbidden: Invalid or missing bootstrap setup token`:
  - Check the generated token in your `.env` file (`PCOS_ADMIN_BOOTSTRAP_TOKEN`).
  - Pass `"setup_token": "<token>"` in the first user registration request.

### WebSocket Connection Closes Unexpectedly
- WebSocket endpoints require authentication via:
  - Header: `Authorization: Bearer <access_token>`
  - Or Subprotocol: `Sec-WebSocket-Protocol: bearer, <access_token>`
- If connecting via a browser WebSocket client that does not support custom headers, specify the subprotocol:
  ```javascript
  const ws = new WebSocket('ws://localhost:8080/api/v1/sync/ws', ['bearer', token]);
  ```

---

## 3. WebDAV & S3 Gateway Troubleshooting

### Windows Network Drive / WebDAV Connection
- Windows requires Basic auth over SSL unless the `BasicAuthLevel` registry key is enabled.
- For local HTTP development:
  - Connect using Cyberduck, WinSCP, or rclone.
- For production:
  - Ensure Caddy TLS is active (`https://pcos.yourdomain.com/webdav`).

### S3 Access with rclone
- In your `rclone.conf`:
  ```ini
  [pcos-s3]
  type = s3
  provider = Other
  endpoint = https://pcos.yourdomain.com/s3
  access_key_id = <YOUR_USER_ID_OR_TOKEN>
  secret_access_key = <YOUR_PCOS_JWT_TOKEN>
  region = us-east-1
  ```
- Test with: `rclone lsd pcos-s3:`

---

## 4. Media Streaming & Direct Play

### Video Fails to Seek or Starts from the Beginning
- Ensure your reverse proxy (Caddy/Nginx) preserves the `Range` request header and `206 Partial Content` status.
- In Caddy, range headers are preserved by default.

### Revoked or Expired Playback Tokens
- Playback tokens have a 2-hour TTL.
- If a TV or remote player reports `401 Unauthorized`:
  - Request a fresh playback token via `POST /api/v1/streaming/:file_id/token`.
  - Re-initiate playback with `GET /api/v1/streaming/play?token=<new_token>`.

---

## 5. Peer Discovery & Delta Sync

### Local Network Devices Not Auto-Discovered
- PCOS Discovery uses UDP broadcast on port **38472**.
- Check host firewall rules:
  ```bash
  # Linux (ufw)
  sudo ufw allow 38472/udp

  # Windows (PowerShell)
  New-NetFirewallRule -DisplayName "PCOS Peer Discovery" -Direction Inbound -Protocol UDP -LocalPort 38472 -Action Allow
  ```
- Note: Docker containers using default bridge networking cannot receive LAN broadcast packets. In Docker, configure `network_mode: host` or pair devices using QR code pairing in Settings.
