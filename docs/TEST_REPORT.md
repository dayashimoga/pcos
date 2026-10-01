# PCOS Test Report

**Date**: 2026-10-01  
**Version**: 0.9.0 (Production Verified)

---

## Executable Test Evidence (Zero-Assumption Audit)

| Suite | Target | Tests Passed | Tests Failed | Execution Time | Evidence Status |
|-------|--------|--------------|--------------|----------------|-----------------|
| **Rust Agent** | `agent` | 6 / 6 | 0 | 0.04s | ✅ PASS |
| **Backup DR Engine** | `pcos-backup` | 3 / 3 | 0 | 0.01s | ✅ PASS |
| **Frontend BLoC & Models** | `frontend` | 17 / 17 | 0 | 2.50s | ✅ PASS |
| **Workspace Compilation** | `backend` (all 15 crates) | Clean compile | 0 warnings | 2.83s | ✅ PASS |

---

## Detailed Test Breakdown

### 1. `pcos-backup` (Disaster Recovery & Cryptographic Verification)
- `service::tests::test_backup_verification_healthy`: Creates payloads and manifest with SHA-256 hashes; asserts `healthy == true`, `checksums_verified == 1`, `status == "verified"`.
- `service::tests::test_backup_verification_detects_corruption`: Corrupts byte payload on disk; asserts `healthy == false`, `checksum_mismatches == 1`, `status == "degraded"`.
- `service::tests::test_backup_verification_detects_missing_payload`: Validates manifest missing payload handling; asserts `healthy == false`, `files_missing == 1`.

### 2. `pcos_agent` (Peer Discovery & Content-Defined Delta Sync)
- `discovery::tests::test_peer_list_initially_empty`: Asserts state initialization.
- `discovery::tests::test_peer_tracking`: Validates peer heartbeat, discovery, and IP binding.
- `delta::tests::test_diff_no_changes`: Fast byte-level chunk comparison on unchanged files.
- `delta::tests::test_file_hash`: SHA-256 hash evaluation of source files.
- `delta::tests::test_diff_detects_changes`: Detection of modified chunks in large binaries.
- `delta::tests::test_split_deterministic`: Content-defined rolling chunk split determinism.

### 3. `pcos_frontend` (Auth, File Operations & Unified Transfer Center)
- `auth_bloc_test.dart` (5 tests): Initial state, login success, login failure, logout, unauthenticated state.
- `file_bloc_test.dart` (6 tests): Initial state, root load, folder navigation, folder creation, load failure, delete action.
- `transfer_manager_test.dart` (6 tests): Progress calculation, speed & ETA formatting, active transfer count tracking, pause/resume/cancel lifecycles, mark/clear completed, bandwidth rate-limiting settings.

