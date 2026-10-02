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
PCOS implements the `RemoteAccessProvider` abstraction across all clients:

| Provider | Transport | Security | Best For |
|---|---|---|---|
| **Direct LAN** | HTTP/2 or HTTP/1.1 via local IP | mTLS / JWT session | Home network, highest throughput, 0 internet dependency |
| **Direct HTTPS** | TLS 1.3 / HTTP/2 via Caddy | Auto-TLS (Let's Encrypt / ZeroSSL) | Public IP, static DNS or dynamic DNS domains |
| **WireGuard / Headscale P2P** | UDP / WireGuard protocol | Curve25519 + ChaCha20-Poly1305 | Behind NAT / CGNAT, direct encrypted peer-to-peer |
| **NetBird Mesh** | WireGuard + WebRTC ICE/STUN | End-to-end encrypted mesh | Decentralized multi-device mesh topology |
| **Encrypted Relay Tunnel** | TLS WebSocket / QUIC relay | Ephemeral end-to-end encryption | Strict symmetric NAT / firewalled enterprise networks |

### Connection Selection Logic
1. **Probe Local Network**: Broadcasts/checks local endpoints using mDNS / local IP lookup. If reachable and TLS fingerprint matches server identity, switch to **Direct LAN**. Local transfers NEVER route over WAN.
2. **Probe Public Domain**: If public domain is configured with valid TLS certificate and reachable, establish **Direct HTTPS**.
3. **P2P Fallback**: If behind NAT or Carrier-Grade NAT (CGNAT `100.64.0.0/10`), initialize WireGuard/Headscale ICE hole-punching for zero-latency direct connection.
4. **Relay Fallback**: If peer-to-peer is prevented by symmetric NAT, route traffic through encrypted relay tunnels.

## 3. Remote Access Configuration UI
In PCOS Settings and PCOS Doctor, users can select:
- `[● Automatic - Recommended]`: Discovers and switches between Direct LAN when at home, WireGuard/Direct HTTPS when remote.
- `[○ Private devices only]`: WireGuard/Headscale peer-to-peer only; never exposes public HTTP ports.
- `[○ Own domain]`: Uses custom DNS domain with automatic Caddy TLS certificate provisioning.
- `[○ LAN only]`: Completely disables external access; isolates PCOS to trusted home subnet.

## 4. PCOS Doctor Network Diagnostics
The backend exposes `GET /api/v1/doctor/connectivity` which automatically performs:
- **LAN IP Detection**: Identifies local network routing addresses.
- **CGNAT Assessment**: Flags RFC 6598 carrier-grade NAT blocks (`100.64.0.0/10`) to inform users that inbound ports are filtered by ISP.
- **Firewall & Port Availability**: Checks status of ports 80, 443, 51820.
- **TLS Health**: Verifies reverse proxy certificate status.
- **Provider Recommendation**: Evaluates conditions and recommends the fastest, safest connection path.
- **UPnP Rule**: PCOS **never** silently enables UPnP or alters router configuration without explicit user consent.

## 5. One-Scan Device Provisioning
Device pairing is secured with short-lived, rate-limited enrollment tokens:
1. User clicks **Connect Device** on Web Console (`/devices/onboarding`).
2. Server calls `POST /api/v1/devices/pair`, creating an in-memory session with:
   - 6-digit numeric OTP for TV/keyboard input
   - 32-byte cryptographic enrollment token
   - 300-second (5 minute) TTL
   - Rate limit of 5 pairing attempts per minute
3. QR code embeds server URL, enrollment token, OTP, and server identity fingerprint.
4. Mobile or desktop device scans QR, calls `POST /api/v1/devices/pair/redeem`:
   - Validates enrollment token
   - Registers new device identity (`client_type`, `client_name`, `client_version`)
   - Mints initial device-bound JWT token pair
   - Permanently burns enrollment token (one-time use)
5. Device is immediately connected with zero manual URL, IP, or credential entry!
