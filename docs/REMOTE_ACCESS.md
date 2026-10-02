# PCOS Connect — Zero-Config Remote Access Architecture

## 1. Overview & Vision
PCOS Connect delivers effortless personal cloud connectivity: **install once → scan QR → securely access/share/sync/stream everything from phone, tablet, laptop, desktop, browser, or TV anywhere** without requiring users to configure port forwarding, dynamic DNS, VPN servers, NAT hairpinning, TLS certificates, or reverse proxies.

```
                  Client Device
                        │
                  Same LAN?
                   /         \
                 YES          NO
                  │            │
             Direct LAN   Direct HTTPS?
                            /         \
                          YES          NO
                           │            │
                         HTTPS    WireGuard P2P?
                                    /         \
                                  YES          NO
                                   │            │
                                  P2P      Tunnel / Relay
```

## 2. Pluggable Connection Engine (`ConnectionManager`)
PCOS implements the `ConnectionManager` abstraction across all clients and node agents:

| Route | Transport | Security | Best For |
|---|---|---|---|
| **Direct LAN** | Direct TCP/HTTP/2 via host LAN IP | Local TLS / Token auth | Home network, highest throughput, 0 internet dependency (<20ms latency) |
| **Direct HTTPS** | TLS 1.3 / HTTP/2 via Cloudflare Pages or Caddy | Automated Edge TLS | Always-available Web access, worldwide edge CDN |
| **WireGuard / Headscale P2P** | UDP / WireGuard protocol | Curve25519 + ChaCha20-Poly1305 | Behind NAT / CGNAT, direct encrypted peer-to-peer |
| **Encrypted Relay Tunnel** | WSS to Durable Object broker | Ephemeral end-to-end encryption | Strict symmetric NAT / firewalled enterprise networks |

### Connection Selection Logic
1. **Control Plane Handshake**: Devices connect outbound via WSS to the Cloudflare `DevicePresenceHub`.
2. **Route Resolution (`GET /api/v1/devices/resolve/:id`)**: The edge evaluates caller IP, target IP, and LAN subnets:
   - If both devices share the same public IP or local subnet -> **Direct LAN** (<20ms latency check).
   - If peer has active WireGuard keys -> **P2P WireGuard**.
   - Otherwise -> **Encrypted Relay Tunnel**.
3. **Data Plane vs Control Plane Separation**: Media streams and 20GB file transfers transfer directly between devices. Only lightweight coordination commands (e.g. `play_on_tv`) flow through Cloudflare.

## 3. Remote Control: Play-on-TV & Send-to-Device
- **Play-on-TV**: The mobile phone sends a lightweight command to the Control Plane:
  `POST /api/v1/control/commands { targetDeviceId: tvId, command: "play_on_tv", payload: { file_id } }`
  The TV receives the command over its open WebSocket tunnel and streams directly from the storage node. The phone never proxies video data.
- **Send-to-Device**: Instantly transfers files between enrolled devices with automatic resume, checksum verification, and integrity checks.

## 4. One-Scan Device Provisioning & Approval
1. Web Console initiates an authoritative pairing session via `POST /api/v1/devices/pair`.
2. Mobile scans the real camera QR code or enters the 6-digit code.
3. Mobile claims the session via `POST /api/v1/devices/pair/claim`.
4. Web Console prompts the owner: "Samsung S24 Ultra wants to connect" `[Approve] [Decline]`.
5. Upon user approval, mutual trust is established, single-use tokens are consumed, and the device is enrolled.

