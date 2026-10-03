// Post-Deployment E2E Smoke Test for PCOS Edge Control Plane
// Validates: /livez, /readyz, /health, /api/v1/usage/budget, /api/v1/doctor/connectivity

const baseUrl = (process.env.DEPLOYED_URL || 'https://pcos-control-plane.dayashimoga.workers.dev').replace(/\/$/, '');

console.log('===================================================');
console.log(`🚀 PCOS Edge Live Post-Deploy Smoke Test`);
console.log(`Target: ${baseUrl}`);
console.log('===================================================\n');

let passed = 0;
let failed = 0;

async function checkEndpoint(name, path, expectedStatus, validator) {
  const url = `${baseUrl}${path}`;
  try {
    const res = await fetch(url, {
      method: 'GET',
      headers: { Accept: 'application/json' },
    });

    const isStatusOk = res.status === expectedStatus;
    let data = null;
    try {
      data = await res.json();
    } catch (_) {
      data = null;
    }

    let validationErr = null;
    if (validator && isStatusOk) {
      try {
        validator(data);
      } catch (err) {
        validationErr = err.message;
      }
    }

    if (isStatusOk && !validationErr) {
      console.log(`✓ [PASS] GET ${path} (HTTP ${res.status}) — ${name}`);
      passed++;
      return true;
    } else {
      console.error(`❌ [FAIL] GET ${path} (HTTP ${res.status}, expected ${expectedStatus}) — ${name}`);
      if (validationErr) console.error(`    Validation error: ${validationErr}`);
      if (data) console.error(`    Response body: ${JSON.stringify(data).slice(0, 200)}`);
      failed++;
      return false;
    }
  } catch (err) {
    console.error(`❌ [FAIL] GET ${path} — Connection Error: ${err.message}`);
    failed++;
    return false;
  }
}

async function runSmokeTests() {
  // 1. /livez — process reachable
  await checkEndpoint('Process Liveness', '/livez', 200, (data) => {
    if (data?.status !== 'alive') throw new Error(`Expected status: alive, got ${data?.status}`);
  });

  // 2. /health — basic health & version
  await checkEndpoint('Legacy/Edge Health', '/health', 200, (data) => {
    if (data?.status !== 'healthy') throw new Error(`Expected status: healthy, got ${data?.status}`);
    if (!data?.version) throw new Error('Missing version in health response');
  });

  // 3. /readyz — dependency checks (JWT, D1, DO)
  await checkEndpoint('Dependency Readiness', '/readyz', 200, (data) => {
    if (data?.status !== 'ready') throw new Error(`Status is not ready: ${data?.status}`);
    if (data?.checks?.jwt_config?.status !== 'pass') {
      throw new Error(`JWT config check failed: ${data?.checks?.jwt_config?.detail}`);
    }
  });

  // 4. /api/v1/usage/budget — free-tier budget guard
  await checkEndpoint('Free-Tier Budget Guard', '/api/v1/usage/budget', 200, (data) => {
    if (data?.hard_budget_enabled === undefined) throw new Error('Missing hard_budget_enabled in response');
  });

  // 5. /api/v1/doctor/connectivity — network/connectivity diagnostics
  await checkEndpoint('PCOS Connect Diagnostics', '/api/v1/doctor/connectivity', 200, (data) => {
    if (!data?.recommended_provider) throw new Error('Missing recommended_provider');
  });

  console.log('\n===================================================');
  if (failed === 0) {
    console.log(`🎉 All ${passed} Live Post-Deploy Smoke Checks PASSED!`);
    console.log('===================================================\n');
    process.exit(0);
  } else {
    console.error(`💥 Smoke test FAILED: ${passed} passed, ${failed} failed.`);
    console.error('===================================================\n');
    process.exit(1);
  }
}

// Allow worker cold-start propagation with retry
async function main() {
  const maxAttempts = 3;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      console.log(`--- Smoke Test Attempt ${attempt}/${maxAttempts} ---`);
      await runSmokeTests();
      return;
    } catch (_) {
      if (attempt < maxAttempts) {
        console.log('Retrying in 5 seconds...');
        await new Promise((r) => setTimeout(r, 5000));
        passed = 0;
        failed = 0;
      }
    }
  }
  process.exit(1);
}

main();
