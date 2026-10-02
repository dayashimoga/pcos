# PCOS Device Pairing & Identity Specification

## 1. Zero-Trust Pairing Architecture

PCOS uses **server-authoritative, short-lived, single-use enrollment sessions**. Client-only fake pairing codes and unauthenticated LAN fallbacks have been completely eliminated.

```
Web/PCOS App                            Cloud Control Plane                     Mobile Phone / Node
     |                                          |                                        |
     |--- 1. POST /api/v1/devices/pair -------->|                                        |
     |<-- 2. 6-digit code + QR link + Token ----|                                        |
     |                                          |                                        |
     |                                          |<-- 3. Scan QR / Enter Code ------------|
     |                                          |<-- 4. POST /api/v1/devices/pair/claim -|
     |                                          |    (Device metadata + fingerprint)     |
     |                                          |                                        |
     |<-- 5. WS Push: "Samsung S24 wants" ------|                                        |
     |    (Candidate approval prompt)           |                                        |
     |                                          |                                        |
     |--- 6. POST /devices/pair/approve ------->|                                        |
     |    (User clicks [Approve])               |                                        |
     |                                          |--- 7. WS Push / Poll: APPROVED ------->|
     |                                          |                                        |
     |                                          |<-- 8. POST /devices/pair/redeem -------|
     |                                          |    (Invalidates token immediately)     |
     |<---------------- MUTUAL TRUST ESTABLISHED --------------------------------------->|
```

---

## 2. Security Safeguards

1. **Cryptographically Authoritative**:
   - Pairing codes are 6-digit CSPRNG numeric codes (`100000` to `999999`).
   - Pairing tokens are 32-character hexadecimal cryptographically secure random values.
2. **Short-Lived Expiration**:
   - Pairing sessions expire in 300 seconds (5 minutes). Expired sessions are rejected and pruned.
3. **Brute-Force & Rate-Limit Protection**:
   - Each pairing session permits a maximum of 5 failed attempts before the session is permanently locked and destroyed.
4. **Explicit Owner Authorization**:
   - Devices entering a pairing code do not immediately gain access. The Web/Desktop dashboard prompts the owner with device name, OS, type, and fingerprint: `[Approve Connection] [Decline]`.
5. **Single-Use Consumption & Replay Prevention**:
   - Upon successful redemption, the pairing session record is deleted from both memory (Durable Objects) and database (D1/SQLite). Replayed tokens return `HTTP 401 Unauthorized`.
6. **Token Issuance**:
   - The newly enrolled device receives a scoped JWT access token (15-minute TTL) and a high-entropy refresh token stored in encrypted platform storage (Keychain/Keystore/encrypted TOML).

---

## 3. User Experience

- **Mobile First**:
  - Open PCOS mobile app -> Screen shows `[ Scan QR Code ]` (using native camera with runtime permission handling).
  - Manual 6-digit code entry with instant visual feedback.
  - "Discover Nearby" uses zero-configuration mDNS/UDP discovery.
  - "Advanced: Manual Server" is reserved exclusively for air-gapped or offline private LAN deployments.
- **Node Setup (CLI)**:
  - `pcos-agent enroll --code 856408 --server https://pcos.pages.dev`
  - Automated handshake, interactive wait for approval, and configuration persistence in `~/.pcos/agent.toml`.
