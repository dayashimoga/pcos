# PCOS Media Streaming Architecture & Implementation

## 1. Overview
PCOS provides a secure, resource-efficient media streaming pipeline designed for direct play, HTTP 206 Partial Content Range streaming, hardware-accelerated transcoding, and revocable device-scoped token authentication for Smart TVs, web browsers, and native mobile clients.

---

## 2. Core Architecture

```
[ Client / Smart TV / Mobile ]
            │
            │  1. Request Playback Token (Authorization: Bearer <user_jwt>)
            ▼
   POST /api/v1/streaming/:file_id/token
            │
            │  Returns: short-lived, device-scoped playback_token (2h validity)
            ▼
[ Client / Smart TV / Native Player ]
            │
            │  2. Direct Play Request: GET /api/v1/streaming/play?token=<playback_token>
            │     Header: Range: bytes=0-1048575
            ▼
   ┌─────────────────────────────────────────────────────────────┐
   │ pcos-streaming Service                                      │
   │                                                             │
   │ 1. Cryptographically verify playback_token                  │
   │ 2. Validate file_id and user_id match claim                 │
   │ 3. Check file existence in active storage                   │
   │ 4. Probe container and codec via ffprobe / metadata cache   │
   │ 5. Parse HTTP Range header (start, end, total)              │
   │ 6. Stream byte chunk asynchronously via tokio::io           │
   │ 7. Respond with HTTP 206 Partial Content                    │
   └─────────────────────────────────────────────────────────────┘
```

---

## 3. Scoped Playback Token Security
- **No Token Leakage**: Primary user credentials and long-lived access tokens are **never** passed in video streaming URLs or logged by reverse proxies.
- **Strict Scope**: Playback tokens are signed with HMAC-SHA256 and encapsulate:
  - `sub`: User ID
  - `file_id`: Exactly one authorized media file UUID
  - `device_id`: Client identifier
  - `exp`: 2-hour expiration window
- **Validation**: Any request to `/api/v1/streaming/play` with an invalid signature, expired timestamp, or mismatched `file_id` is rejected immediately with `401 Unauthorized` or `403 Forbidden`.

---

## 4. Range Streaming & Direct Play
- Direct Play uses standard RFC 7233 HTTP 206 Range requests.
- When seeking in a 4K or 1080p video file, the client requests specific byte ranges (`bytes=10485760-20971519`).
- PCOS handles:
  - Open file handle asynchronously.
  - Seek to `start` offset.
  - Stream exactly `end - start + 1` bytes without reading the whole file into RAM.
  - Set `Content-Range: bytes START-END/TOTAL`.
  - Set `Accept-Ranges: bytes`.

---

## 5. ffprobe Probing & Hardware Acceleration
- Probing dynamically checks container headers using `ffprobe` with JSON output.
- Hardware acceleration (`VAAPI`, `NVENC`, `QuickSync`) is auto-detected:
  - If source video is H.264/AAC in an MP4 container, Direct Play is selected (0% CPU overhead).
  - If source requires transcoding (e.g. HEVC 10-bit on legacy browser, AVI, or DTS audio), FFmpeg transcodes into adaptive HLS with cached segments.

---

## 6. Endpoints Reference
| Endpoint | Method | Security | Function |
|----------|--------|----------|----------|
| `/api/v1/streaming/:file_id/token` | POST | Bearer JWT | Generate 2-hour revocable playback token |
| `/api/v1/streaming/play?token=...` | GET | Playback Token | HTTP 206 Partial Content Range direct play |
| `/api/v1/streaming/:file_id/stream` | GET | Bearer JWT | Direct authenticated range streaming |
| `/api/v1/streaming/:file_id/probe` | GET | Bearer JWT | Retrieve audio/video codecs and dimensions |
