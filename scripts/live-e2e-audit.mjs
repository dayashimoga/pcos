// PCOS Live Edge Control Plane Verification Suite
// Tests live deployed worker at https://pcos-control-plane.dayashimoga.workers.dev

const BASE_URL = process.env.PCOS_URL || 'https://pcos-control-plane.dayashimoga.workers.dev';

async function runAudit() {
  console.log(`Starting PCOS Live Edge Control Plane Audit: ${BASE_URL}\n`);
  let passed = 0;
  let failed = 0;

  async function check(name, fn) {
    try {
      await fn();
      console.log(`  [PASS] ${name}`);
      passed++;
    } catch (err) {
      console.error(`  [FAIL] ${name}: ${err.message}`);
      failed++;
    }
  }

  // 1. Health Probe
  await check('GET /health returns healthy 200', async () => {
    const res = await fetch(`${BASE_URL}/health`);
    if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.status !== 'healthy') throw new Error(`Status was ${data.status}`);
  });

  // 2. Livez Probe
  await check('GET /livez returns alive 200', async () => {
    const res = await fetch(`${BASE_URL}/livez`);
    if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
  });

  // 3. Readyz Probe
  await check('GET /readyz returns 200', async () => {
    const res = await fetch(`${BASE_URL}/readyz`);
    if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
  });

  // 4. Version info
  await check('GET /api/v1/version returns version info', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/version`);
    if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (!data.version) throw new Error('Missing version');
  });

  // 5. Connectivity Doctor
  await check('GET /api/v1/doctor/connectivity returns diagnostics', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/doctor/connectivity`);
    if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (!data.storage_healthy || !data.database_healthy) {
      throw new Error(`Storage/DB health issue: storage=${data.storage_healthy}, db=${data.database_healthy}`);
    }
  });

  // 6. Free Tier Budget Guard
  await check('GET /api/v1/usage/budget returns budget metrics', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/usage/budget`);
    if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (typeof data.hard_budget_enabled !== 'boolean') throw new Error('Missing hard_budget_enabled');
    if (!data.worker_requests || typeof data.worker_requests.limit !== 'number') throw new Error('Missing worker_requests.limit');
  });

  // 7. Security: Unauthorized download rejected
  await check('GET /api/v1/files/secret123/download without token returns 401', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/files/secret123/download`);
    if (res.status !== 401) throw new Error(`Expected 401, got ${res.status}`);
  });

  // 8. Security: Unauthorized cluster access rejected
  await check('GET /api/v1/cluster/status without token returns 401', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/cluster/status`);
    if (res.status !== 401) throw new Error(`Expected 401, got ${res.status}`);
  });

  // 9. Security: Unauthorized storage policies rejected
  await check('GET /api/v1/storage/policies without token returns 401', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/storage/policies`);
    if (res.status !== 401) throw new Error(`Expected 401, got ${res.status}`);
  });

  // 10. Security: Unauthorized family clouds rejected
  await check('GET /api/v1/family/clouds without token returns 401', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/family/clouds`);
    if (res.status !== 401) throw new Error(`Expected 401, got ${res.status}`);
  });

  // 11. Security: Unauthorized admin audit rejected
  await check('GET /api/v1/admin/audit/licenses-quotas without token returns 401', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/admin/audit/licenses-quotas`);
    if (res.status !== 401) throw new Error(`Expected 401, got ${res.status}`);
  });

  // 12. Security: Unauthorized data export rejected
  await check('GET /api/v1/admin/export without token returns 401', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/admin/export`);
    if (res.status !== 401) throw new Error(`Expected 401, got ${res.status}`);
  });

  // 13. Security: Emergency recovery requires valid payload
  await check('POST /api/v1/auth/recovery/verify with empty payload returns 400', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/auth/recovery/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    if (res.status !== 400) throw new Error(`Expected 400, got ${res.status}`);
  });

  // 14. CORS Preflight
  await check('OPTIONS /api/v1/health returns proper CORS headers', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/health`, {
      method: 'OPTIONS',
      headers: { Origin: 'http://localhost:3000' },
    });
    const allowOrigin = res.headers.get('Access-Control-Allow-Origin');
    if (!allowOrigin) throw new Error('Missing Access-Control-Allow-Origin');
  });

  // 15. Security: URL Query Parameter Token Leakage Guard (P0)
  await check('GET /api/v1/family/clouds with query param ?token= rejects with 401', async () => {
    const res = await fetch(`${BASE_URL}/api/v1/family/clouds?token=unauthorized_query_param_token_attempt`);
    if (res.status !== 401) throw new Error(`Expected 401, got ${res.status}`);
  });

  // 16. Security: BIP-39 Invalid Checksum Rejection (P0)
  await check('POST /api/v1/auth/recovery/verify with invalid BIP-39 checksum returns 400', async () => {
    // 12 words with invalid checksum
    const badPhrase = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon';
    const res = await fetch(`${BASE_URL}/api/v1/auth/recovery/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'test@example.com',
        recovery_phrase: badPhrase,
        new_password: 'ValidNewPassword123!',
      }),
    });
    if (res.status !== 400 && res.status !== 404) throw new Error(`Expected 400 or 404, got ${res.status}`);
  });

  console.log(`\nAudit Complete: ${passed} passed, ${failed} failed.`);
  if (failed > 0) process.exit(1);
}

runAudit();
