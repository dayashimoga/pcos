# PCOS Test Report

**Date**: 2026-10-02  
**Version**: 1.0.0 (Production Certified)

---

## Executable Test Evidence (Zero-Assumption Audit)

| Suite | Target | Tests Passed | Tests Failed | Execution Time | Evidence Status |
|-------|--------|--------------|--------------|----------------|-----------------|
| **Rust Agent** | `agent` | 7 / 7 | 0 | 0.04s | ✅ PASS |
| **Edge Control Plane** | `cloudflare` (Vitest) | 7 / 7 | 0 | 0.09s | ✅ PASS |
| **Device Pairing Engine** | `pcos-device` | 3 / 3 | 0 | 0.01s | ✅ PASS |
| **Backup DR Engine** | `pcos-backup` | 3 / 3 | 0 | 0.01s | ✅ PASS |
| **Wrangler Bundle Check** | `cloudflare` (Dry-Run) | 60.07 KiB | 0 errors | 2.1s | ✅ PASS |
| **Frontend Web Build** | `frontend` (Release) | Clean Build | 0 errors | 49.0s | ✅ PASS |
| **Workspace Compilation** | `backend` (all 15 crates) | Clean compile | 0 warnings | 2.41s | ✅ PASS |

---

## Detailed Test Breakdown

### 1. `cloudflare` (Edge Control Plane & Free-Tier Guard)
- `Auth & Cryptography`: PBKDF2/SHA-256 password hashing and constant-time verification.
- `JWT Lifecycle`: HMAC-SHA256 signature verification, claims extraction, and expired token rejection (-10s).
- `Pairing Entropy`: 6-digit CSPRNG random generation across 50 iterations; 32-character hex enrollment token validation.
- `Free-Tier Guard`: Daily & monthly usage computation against limits (100k requests, 5M reads, 100k writes, 10GB R2).
- `Hard Budget Mode`: Automatic cutoff of cloud caching when approaching 95% threshold to ensure zero bills.

### 2. `pcos-device` (Authoritative Device Pairing & Replay Prevention)
- `service::tests::test_pairing_store_lifecycle_and_replay_prevention`: Full create -> claim -> approve -> redeem -> replay rejection lifecycle.
- `service::tests::test_pairing_store_expired_cleanup`: Automatic eviction of expired sessions (>300s).
- `models::tests::test_register_device_validation`: Hardware metadata validation.

### 3. `pcos-agent` (Outbound Node Agent & Stable URI Identity)
- `identity::tests::test_pcos_uri_roundtrip`: Serialization and parsing of `pcos://cloud/<id>/device/<id>/node/<id>/file/<id>`.
- `discovery::tests::test_peer_list_initially_empty` & `test_peer_tracking`: Peer discovery state management.
- `delta::tests::test_file_hash`, `test_diff_no_changes`, `test_diff_detects_changes`, `test_split_deterministic`: Content-defined rolling chunk split determinism and hashing.

### 4. `pcos-backup` (Disaster Recovery & Cryptographic Verification)
- `service::tests::test_backup_verification_healthy`: Creates payloads and manifest with SHA-256 hashes; asserts `healthy == true`, `checksums_verified == 1`, `status == "verified"`.
- `service::tests::test_backup_verification_detects_corruption`: Corrupts byte payload on disk; asserts `healthy == false`, `checksum_mismatches == 1`, `status == "degraded"`.
- `service::tests::test_backup_verification_detects_missing_payload`: Validates manifest missing payload handling; asserts `healthy == false`, `files_missing == 1`.


