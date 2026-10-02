# PCOS Storage Nodes & Outbound Agent Architecture

## 1. Overview

A PCOS Storage Node is any user-owned device (Windows PC, Linux laptop, macOS workstation, Synology/TrueNAS appliance, or Raspberry Pi) running the lightweight `pcos-agent` daemon.

Storage nodes maintain an **outbound-only TLS/WSS control tunnel** to the Cloudflare Edge Control Plane. Normal users never configure port forwarding, static IPs, dynamic DNS, UPnP, or firewall pinholes.

---

## 2. Stable Logical Identity

PCOS decouples physical IP addresses from device identities. Devices and files are addressed through immutable logical URIs:

```
pcos://cloud/<cloud_id>/device/<device_id>/node/<node_id>/file/<file_id>
```

When a device changes Wi-Fi networks, roams to cellular data, or wakes from sleep, it reconnects its outbound WSS tunnel to the Edge Control Plane and updates its active IP subnets. Existing shares, sessions, and streams continue uninterrupted without re-pairing.

---

## 3. PCOS Node Doctor

The built-in diagnostics utility inspects hardware, storage, network routing, CGNAT, and multimedia accelerators:

```bash
pcos-agent doctor --storage /data/pcos --server https://pcos.pages.dev
```

### Diagnostic Checks
1. **Host Routing & LAN IP**: Discovers true host IP via kernel UDP route probing (bypassing container virtual subnets like `10.89.x.x`).
2. **Carrier-Grade NAT (CGNAT) Detection**: Identifies RFC 6598 carrier addresses (`100.64.0.0/10`) to activate WireGuard P2P tunnels.
3. **Storage Read/Write Verification**: Tests disk read/write permissions and checks storage directory quotas.
4. **DNS Resolution & Latency**: Verifies edge DNS reachability and measures TLS handshake latency (<150ms target).
5. **Control Plane Reachability**: Health probes the Cloudflare Worker control endpoint.
6. **FFmpeg & Hardware Acceleration**: Detects installed transcode engines and hardware accelerators (`cuda`, `qsv`, `vaapi`, `videotoolbox`, `d3d11va`).

---

## 4. One-Command Node Enrollment

Enrolling a new desktop or laptop node takes a single command:

```bash
pcos-agent enroll --code 856408 --server https://pcos.pages.dev
```

1. Claims pairing session with hardware metadata and hostname.
2. Prompts owner on their PCOS Web/Phone screen to approve the connection.
3. Obtains and securely stores JWT authentication tokens.
4. Configures default storage sync folder (`~/PCOS`) and writes `~/.pcos/agent.toml`.

---

## 5. Starting the Node Agent

```bash
# Run in foreground
pcos-agent --daemon

# Or start as a system background service
pcos-agent start --daemon
```

### Active Loops
- **Filesystem Watcher**: Listens for file changes with debounce and notifies peer nodes.
- **Delta Sync Engine**: Computes SHA-256 chunk hashes for resumable block-level file synchronization.
- **Connection Manager**: Maintains WebSocket heartbeat to the Cloudflare `DevicePresenceHub` and dispatches incoming `play_on_tv` and `send_to_device` instructions.
- **LAN P2P Peer Discovery**: Broadcasts and receives local UDP announcements for zero-latency direct transfers.
