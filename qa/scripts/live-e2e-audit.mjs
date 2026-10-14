// Comprehensive Live E2E Audit for PCOS Control Plane
// Tests complete user journeys, device pairing, storage, security, and edge behaviors.

const baseUrl = (process.env.DEPLOYED_URL || 'https://pcos-control-plane.dayashimoga.workers.dev').replace(/\/$/, '');
const uniqueSuffix = Date.now().toString(36) + Math.random().toString(36).substring(2, 5);
const testEmail = `audit_user_${uniqueSuffix}@example.com`;
const testPassword = `P@ssw0rd_${uniqueSuffix}!`;
const newPassword = `NewP@ssw0rd_${uniqueSuffix}!`;

console.log('================================================================');
console.log('🕵️ PCOS Phase 0 Live Forensic Audit & Baseline Probe');
console.log(`Target: ${baseUrl}`);
console.log(`Test User: ${testEmail}`);
console.log('================================================================\n');

const results = [];

async function step(name, fn) {
  process.stdout.write(`• Testing: ${name}... `);
  try {
    const res = await fn();
    console.log(`✅ PASS`);
    results.push({ name, status: 'PASS', detail: res });
    return res;
  } catch (err) {
    console.log(`❌ FAIL`);
    console.error(`   Error: ${err.message}`);
    results.push({ name, status: 'FAIL', error: err.message });
    return null;
  }
}

async function runAudit() {
  let user = null;
  let tokens = null;
  let pairingSession = null;
  let deviceToken = null;
  let enrolledDeviceId = null;
  let storageNodeId = null;
  let uploadedFileId = null;
  let shareToken = null;

  // 1. Account Creation
  await step('User Registration', async () => {
    const res = await fetch(`${baseUrl}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: testEmail,
        password: testPassword,
        display_name: 'Audit User',
      }),
    });
    if (res.status !== 201) {
      const err = await res.text();
      throw new Error(`HTTP ${res.status}: ${err}`);
    }
    const data = await res.json();
    if (!data.user?.id || !data.tokens?.access_token) {
      throw new Error(`Incomplete response: ${JSON.stringify(data)}`);
    }
    user = data.user;
    tokens = data.tokens;
    return `User ID: ${user.id}`;
  });

  // 2. Duplicate Registration Rejection
  await step('Duplicate Registration Rejection (409)', async () => {
    const res = await fetch(`${baseUrl}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: testEmail,
        password: testPassword,
        display_name: 'Audit User Duplicate',
      }),
    });
    if (res.status !== 409) {
      throw new Error(`Expected HTTP 409, got ${res.status}`);
    }
    return 'Correctly rejected duplicate email';
  });

  // 3. User Login
  await step('User Login & Token Issuance', async () => {
    const res = await fetch(`${baseUrl}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: testEmail,
        password: testPassword,
      }),
    });
    if (res.status !== 200) {
      const err = await res.text();
      throw new Error(`HTTP ${res.status}: ${err}`);
    }
    const data = await res.json();
    if (!data.tokens?.access_token) {
      throw new Error('Missing access_token');
    }
    tokens = data.tokens;
    return 'Authenticated successfully';
  });

  // 4. Token Refresh
  await step('Token Refresh Rotation', async () => {
    const res = await fetch(`${baseUrl}/api/v1/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: tokens.refresh_token }),
    });
    if (res.status !== 200) {
      throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    }
    const data = await res.json();
    if (!data.tokens?.access_token) {
      throw new Error('Refresh failed');
    }
    tokens = data.tokens;
    return 'Token rotated successfully';
  });

  // 5. User Profile Update
  await step('Update Profile Display Name', async () => {
    const res = await fetch(`${baseUrl}/api/v1/users/me`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${tokens.access_token}`,
      },
      body: JSON.stringify({ display_name: 'Updated Audit User' }),
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    if (data.display_name !== 'Updated Audit User') {
      throw new Error(`Display name not updated: ${data.display_name}`);
    }
    return data.display_name;
  });

  // 6. Change Password
  await step('Change Password & Verify Re-login', async () => {
    const res = await fetch(`${baseUrl}/api/v1/users/me/password`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${tokens.access_token}`,
      },
      body: JSON.stringify({
        current_password: testPassword,
        new_password: newPassword,
      }),
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);

    // Verify login with new password
    const loginRes = await fetch(`${baseUrl}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: testEmail,
        password: newPassword,
      }),
    });
    if (loginRes.status !== 200) throw new Error('Could not log in with new password');
    const loginData = await loginRes.json();
    tokens = loginData.tokens;
    return 'Password changed and verified';
  });

  // 7. Device Pairing: Create Session
  await step('Create Device Pairing Session', async () => {
    const res = await fetch(`${baseUrl}/api/v1/devices/pair`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${tokens.access_token}`,
      },
      body: JSON.stringify({ expires_in_seconds: 300 }),
    });
    if (res.status !== 201) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    pairingSession = await res.json();
    if (!pairingSession.pairing_code || !pairingSession.enrollment_token) {
      throw new Error('Missing code or token');
    }
    return `Code: ${pairingSession.pairing_code}`;
  });

  // 8. Device Pairing: Claim Candidate
  await step('Device Candidate Claims Session', async () => {
    const res = await fetch(`${baseUrl}/api/v1/devices/pair/claim`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairing_code: pairingSession.pairing_code,
        device_name: 'Audit Virtual Laptop',
        device_type: 'laptop',
        os: 'windows',
      }),
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    return 'Candidate submitted';
  });

  // 9. Device Pairing: Approve Session
  await step('Owner Approves Device Candidate', async () => {
    const res = await fetch(`${baseUrl}/api/v1/devices/pair/approve`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${tokens.access_token}`,
      },
      body: JSON.stringify({
        pairing_code: pairingSession.pairing_code,
        approved: true,
      }),
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    return 'Approved by owner';
  });

  // 10. Device Pairing: Redeem Token
  await step('Device Redeems Authenticated Credentials', async () => {
    const res = await fetch(`${baseUrl}/api/v1/devices/pair/redeem`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairing_code: pairingSession.pairing_code,
        device_name: 'Audit Virtual Laptop',
      }),
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    if (!data.access_token || !data.device?.id) {
      throw new Error(`Incomplete redeem payload: ${JSON.stringify(data)}`);
    }
    deviceToken = data.access_token;
    enrolledDeviceId = data.device.id;
    return `Enrolled Device ID: ${enrolledDeviceId}`;
  });

  // 11. Single-Use Pair Token Revocation
  await step('Single-Use Token Enforcement (Re-redeem Fails 401)', async () => {
    const res = await fetch(`${baseUrl}/api/v1/devices/pair/redeem`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairing_code: pairingSession.pairing_code,
      }),
    });
    if (res.status !== 401) {
      throw new Error(`Expected 401 on consumed token, got ${res.status}`);
    }
    return 'Correctly rejected replay attempt';
  });

  // 12. Device Heartbeat
  await step('Device Heartbeat Transmission', async () => {
    const res = await fetch(`${baseUrl}/api/v1/devices/${enrolledDeviceId}/heartbeat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${deviceToken}`,
      },
      body: JSON.stringify({
        lan_ip: '192.168.1.150',
        name: 'Audit Virtual Laptop',
      }),
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    if (!data.is_online) throw new Error('Device not reported online');
    return 'Heartbeat acknowledged';
  });

  // 13. Physical Storage Node Advertisement
  await step('Advertise Physical Storage Disks', async () => {
    const res = await fetch(`${baseUrl}/api/v1/agent/storage/advertise`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${deviceToken}`,
      },
      body: JSON.stringify({
        device_id: enrolledDeviceId,
        disks: [
          {
            mount_point: 'D:\\PCOS',
            name: 'Audit High-Speed NVMe Pool',
            fs_type: 'NTFS',
            total_capacity_bytes: 1000000000000,
            available_capacity_bytes: 850000000000,
            capabilities: { ffmpeg: true, ocr: false, tantivy: true, ollama: false },
          },
        ],
      }),
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    if (!data.storage_nodes || data.storage_nodes.length === 0) {
      throw new Error('No storage nodes returned');
    }
    storageNodeId = data.storage_nodes[0].id;
    return `Storage Node ID: ${storageNodeId}`;
  });

  // 14. List Storage Nodes
  await step('Query Storage Nodes from Web/Mobile API', async () => {
    const res = await fetch(`${baseUrl}/api/v1/storage/nodes`, {
      headers: { Authorization: `Bearer ${tokens.access_token}` },
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    const found = (data.storage_nodes || []).find((n) => n.id === storageNodeId);
    if (!found) throw new Error('Advertised storage node not found in user storage nodes');
    return `Found storage node with ${found.total_capacity_bytes} bytes`;
  });

  // 15. Create Folder
  let folderId = null;
  await step('Create Remote Folder in Personal Cloud', async () => {
    const res = await fetch(`${baseUrl}/api/v1/folders`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${tokens.access_token}`,
      },
      body: JSON.stringify({ name: 'Audit Documents' }),
    });
    if (res.status !== 201) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    folderId = data.id;
    return `Folder ID: ${folderId}`;
  });

  // 16. Upload File
  await step('Upload File to Personal Cloud', async () => {
    const formData = new FormData();
    const fileContent = 'PCOS Phase 0 Audit Verification Payload ' + new Date().toISOString();
    const blob = new Blob([fileContent], { type: 'text/plain' });
    formData.append('file', blob, 'audit_report.txt');
    if (folderId) formData.append('parent_id', folderId);

    const res = await fetch(`${baseUrl}/api/v1/files/upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${tokens.access_token}` },
      body: formData,
    });
    if (res.status !== 201) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    uploadedFileId = data.id;
    return `Uploaded File ID: ${uploadedFileId}`;
  });

  // 17. Download File
  await step('Download File and Verify Integrity', async () => {
    const res = await fetch(`${baseUrl}/api/v1/files/${uploadedFileId}/download`, {
      headers: { Authorization: `Bearer ${tokens.access_token}` },
    });
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const text = await res.text();
    if (!text.includes('PCOS Phase 0 Audit Verification Payload')) {
      throw new Error(`Content mismatch: ${text}`);
    }
    return `Downloaded ${text.length} bytes correctly`;
  });

  // 18. Create Expiring Public Share Link
  await step('Create Expiring Share Link', async () => {
    const res = await fetch(`${baseUrl}/api/v1/shares`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${tokens.access_token}`,
      },
      body: JSON.stringify({
        file_id: uploadedFileId,
        is_public: true,
        expires_at: new Date(Date.now() + 3600000).toISOString(),
        max_downloads: 5,
      }),
    });
    if (res.status !== 201) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    shareToken = data.share_token;
    return `Share Token: ${shareToken}`;
  });

  // 19. Public Access Shared File
  await step('Unauthenticated Recipient Accesses Shared File Metadata', async () => {
    const res = await fetch(`${baseUrl}/api/v1/shared/${shareToken}`);
    if (res.status !== 200) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const data = await res.json();
    if (data.file_id && data.file_id !== uploadedFileId) {
      throw new Error(`Shared file ID mismatch: expected ${uploadedFileId}, got ${data.file_id}`);
    }
    if (!data.file_id && data.file_name !== 'audit_report.txt') {
      throw new Error('Shared file name mismatch');
    }
    return `Recipient resolved file: ${data.file_name}`;
  });

  // 20. Negative Security Test: Unauthenticated Access to Private Files
  await step('Negative Test: Reject Unauthenticated File Access', async () => {
    const res = await fetch(`${baseUrl}/api/v1/files/${uploadedFileId}/download`);
    // Should be rejected with 401 or 404!
    if (res.status === 200) {
      throw new Error('SECURITY VULNERABILITY: Unauthenticated request successfully downloaded private file!');
    }
    return `Correctly blocked unauthenticated access (HTTP ${res.status})`;
  });

  console.log('\n================================================================');
  const passCount = results.filter((r) => r.status === 'PASS').length;
  const failCount = results.filter((r) => r.status === 'FAIL').length;
  console.log(`📊 Audit Complete: ${passCount} PASSED, ${failCount} FAILED out of ${results.length} tests.`);
  console.log('================================================================\n');

  if (failCount > 0) {
    console.log('Failures Summary:');
    results.filter((r) => r.status === 'FAIL').forEach((r) => {
      console.log(` - ${r.name}: ${r.error}`);
    });
    process.exit(1);
  }
}

runAudit().catch((err) => {
  console.error('Fatal audit error:', err);
  process.exit(1);
});
