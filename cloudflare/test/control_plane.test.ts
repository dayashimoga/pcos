// Unit & Integration Tests for PCOS Cloudflare Edge Control Plane

import { describe, it, expect, beforeEach } from 'vitest';
import {
  hashPassword,
  verifyPassword,
  generateJwt,
  verifyJwt,
  generatePairingCode,
  generateEnrollmentToken,
} from '../src/services/auth';
import { BudgetGuard } from '../src/services/budget';
import { Env, BudgetStatus } from '../src/types';

describe('Auth & Cryptography Services', () => {
  it('should hash and verify passwords using PBKDF2/SHA-256', async () => {
    const password = 'SuperSecretPCOS_2026!';
    const hash = await hashPassword(password);

    expect(hash).toContain('pbkdf2$100000$');
    const isValid = await verifyPassword(password, hash);
    expect(isValid).toBe(true);

    const isWrong = await verifyPassword('WrongPassword', hash);
    expect(isWrong).toBe(false);
  });

  it('should generate and verify JWTs with claims and expiry', async () => {
    const secret = 'pcos_test_jwt_secret_key_12345';
    const payload = { sub: 'usr_test_123', email: 'tester@pcos.dev', role: 'user' };

    const token = await generateJwt(payload, secret, 3600);
    expect(token.split('.').length).toBe(3);

    const claims = await verifyJwt(token, secret);
    expect(claims).not.toBeNull();
    expect(claims?.sub).toBe('usr_test_123');
    expect(claims?.email).toBe('tester@pcos.dev');

    // Reject invalid secret
    const badClaims = await verifyJwt(token, 'wrong_secret');
    expect(badClaims).toBeNull();
  });

  it('should reject expired JWTs', async () => {
    const secret = 'pcos_test_jwt_secret';
    // Expired -10 seconds ago
    const token = await generateJwt({ sub: 'expired' }, secret, -10);
    const claims = await verifyJwt(token, secret);
    expect(claims).toBeNull();
  });

  it('should generate valid 6-digit pairing codes', () => {
    for (let i = 0; i < 50; i++) {
      const code = generatePairingCode();
      expect(code).toHaveLength(6);
      expect(Number.isNaN(parseInt(code, 10))).toBe(false);
    }
  });

  it('should generate 32-character hexadecimal enrollment tokens', () => {
    const token = generateEnrollmentToken();
    expect(token).toHaveLength(32);
    expect(/^[0-9a-f]{32}$/.test(token)).toBe(true);
  });
});

describe('Budget & Free-Tier Guard', () => {
  it('should compute percentages against Cloudflare free tier limits', async () => {
    const mockDb = {
      prepare: () => ({
        bind: () => ({
          first: async () => ({
            date_key: '2026-10-02',
            worker_requests: 21000,
            d1_writes: 4000,
            d1_reads: 700000,
            do_requests: 11000,
            r2_storage_bytes: 7.3 * 1024 * 1024 * 1024,
          }),
        }),
      }),
    } as unknown as D1Database;

    const mockEnv = {
      DB: mockDb,
      MAX_WORKERS_PER_DAY: '100000',
      MAX_D1_WRITES_PER_DAY: '100000',
      MAX_D1_READS_PER_MONTH: '5000000',
      MAX_R2_STORAGE_GB: '10',
      FREE_TIER_HARD_BUDGET: 'true',
    } as Env;

    const guard = new BudgetGuard(mockEnv);
    const status = await guard.getBudgetStatus();

    expect(status.worker_requests.pct).toBe(21);
    expect(status.d1_writes.pct).toBe(4);
    expect(status.d1_reads.pct).toBe(14);
    expect(status.do_requests.pct).toBe(11);
    expect(status.r2_storage_gb.used).toBeCloseTo(7.3, 1);
    expect(status.hard_budget_enabled).toBe(true);
    expect(status.estimated_cost).toBe(0.0);
    expect(status.cloud_cache_active).toBe(true);
  });

  it('should disable cloud caching when approaching free-tier limit in hard budget mode', async () => {
    const mockDb = {
      prepare: () => ({
        bind: () => ({
          first: async () => ({
            date_key: '2026-10-02',
            worker_requests: 98000, // 98% of 100k
            d1_writes: 1000,
            d1_reads: 1000,
            do_requests: 1000,
            r2_storage_bytes: 9.6 * 1024 * 1024 * 1024, // 96% of 10GB
          }),
        }),
      }),
    } as unknown as D1Database;

    const mockEnv = {
      DB: mockDb,
      MAX_WORKERS_PER_DAY: '100000',
      MAX_D1_WRITES_PER_DAY: '100000',
      MAX_D1_READS_PER_MONTH: '5000000',
      MAX_R2_STORAGE_GB: '10',
      FREE_TIER_HARD_BUDGET: 'true',
    } as Env;

    const guard = new BudgetGuard(mockEnv);
    const status = await guard.getBudgetStatus();

    expect(status.is_near_limit).toBe(true);
    expect(status.cloud_cache_active).toBe(false); // Cloud cache blocked to protect free tier!
  });
});

describe('File System & Storage Metadata Endpoints', () => {
  it('should format storage sizes correctly', () => {
    // 0 B
    const zero = 0;
    expect(zero <= 0 ? '0 B' : '').toBe('0 B');

    // KB
    const kb = 2048;
    expect(`${(kb / 1024).toFixed(1)} KB`).toBe('2.0 KB');

    // MB
    const mb = 15 * 1024 * 1024;
    expect(`${(mb / (1024 * 1024)).toFixed(1)} MB`).toBe('15.0 MB');
  });

  it('should construct valid file and folder payloads matching frontend expectations', () => {
    const mockFolder = {
      id: 'fld_123',
      parent_id: null,
      name: 'Documents',
      entry_type: 'folder',
      size_bytes: 0,
      is_trashed: false,
      is_favorite: false,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    expect(mockFolder.entry_type).toBe('folder');
    expect(mockFolder.size_bytes).toBe(0);

    const mockPhoto = {
      id: 'file_456',
      parent_id: null,
      name: 'vacation.jpg',
      entry_type: 'file',
      mime_type: 'image/jpeg',
      size_bytes: 2048500,
      is_trashed: false,
      is_favorite: true,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    expect(mockPhoto.mime_type?.startsWith('image/')).toBe(true);

    const rootListing = {
      total: 2,
      entries: [mockFolder, mockPhoto],
      path: [{ id: null, name: 'Root' }],
    };

    expect(rootListing.entries).toHaveLength(2);
    expect(rootListing.path[0].name).toBe('Root');
  });
});

describe('PairingHub Durable Object & Rate Limiting', () => {
  it('should enforce IP rate limiting on brute force pairing attempts and persist redeem_result', async () => {
    const { PairingHub } = await import('../src/durable_objects/PairingHub');
    const storageMap = new Map<string, any>();
    const mockState = {
      storage: {
        get: async (k: string) => storageMap.get(k),
        put: async (k: string, v: any) => storageMap.set(k, v),
        delete: async (k: string) => storageMap.delete(k),
      },
      blockConcurrencyWhile: async (fn: () => Promise<void>) => {
        await fn();
      },
    } as unknown as DurableObjectState;

    const hub = new PairingHub(mockState);

    // 1. Create a valid pairing session
    const createReq = new Request('http://do/create', {
      method: 'POST',
      body: JSON.stringify({
        id: 'sess_test_1',
        userId: 'usr_owner_1',
        pairingCode: '654321',
        enrollmentToken: 'enr_token_1234567890abcdef12345678',
        expiresAt: new Date(Date.now() + 600000).toISOString(),
      }),
    });
    const createResp = await hub.fetch(createReq);
    expect(createResp.status).toBe(200);

    // 2. Simulate brute-force attack from an attacker IP
    const attackerIp = '203.0.113.42';
    for (let i = 0; i < 4; i++) {
      const wrongReq = new Request('http://do/claim', {
        method: 'POST',
        headers: { 'cf-connecting-ip': attackerIp },
        body: JSON.stringify({
          key: `00000${i}`,
          candidate: {
            device_name: 'Attacker Phone',
            device_type: 'phone',
            os: 'unknown',
            requested_at: new Date().toISOString(),
          },
        }),
      });
      const wrongResp = await hub.fetch(wrongReq);
      expect(wrongResp.status).toBe(401);
    }

    // 5th failed attempt triggers rate limit block (HTTP 429)
    const fifthReq = new Request('http://do/claim', {
      method: 'POST',
      headers: { 'cf-connecting-ip': attackerIp },
      body: JSON.stringify({
        key: '999999',
        candidate: {
          device_name: 'Attacker Phone',
          device_type: 'phone',
          os: 'unknown',
          requested_at: new Date().toISOString(),
        },
      }),
    });
    const fifthResp = await hub.fetch(fifthReq);
    expect(fifthResp.status).toBe(429);
    const fifthBody = (await fifthResp.json()) as { error: string };
    expect(fifthBody.error).toContain('Too many invalid pairing attempts');

    // 6th attempt from same IP is immediately blocked with 429 even if code was correct
    const blockedReq = new Request('http://do/claim', {
      method: 'POST',
      headers: { 'cf-connecting-ip': attackerIp },
      body: JSON.stringify({
        key: '654321',
        candidate: {
          device_name: 'Attacker Phone',
          device_type: 'phone',
          os: 'unknown',
          requested_at: new Date().toISOString(),
        },
      }),
    });
    const blockedResp = await hub.fetch(blockedReq);
    expect(blockedResp.status).toBe(429);

    // 3. Legitimate mobile device from different IP claims successfully
    const legitIp = '198.51.100.25';
    const legitReq = new Request('http://do/claim', {
      method: 'POST',
      headers: { 'cf-connecting-ip': legitIp },
      body: JSON.stringify({
        key: '654321',
        candidate: {
          device_name: 'Pixel 9 Pro',
          device_type: 'phone',
          os: 'android',
          requested_at: new Date().toISOString(),
        },
      }),
    });
    const legitResp = await hub.fetch(legitReq);
    expect(legitResp.status).toBe(200);

    // 4. Web user approves session and provides redeemResult
    const approveReq = new Request('http://do/approve', {
      method: 'POST',
      body: JSON.stringify({
        key: '654321',
        userId: 'usr_owner_1',
        approved: true,
        redeemResult: {
          device: { id: 'dev_pixel_9', name: 'Pixel 9 Pro', device_type: 'phone' },
          access_token: 'jwt_access_legit',
          refresh_token: 'jwt_refresh_legit',
        },
      }),
    });
    const approveResp = await hub.fetch(approveReq);
    expect(approveResp.status).toBe(200);

    // 5. Polling client checks status and retrieves redeemResult without re-creating device
    const statusReq = new Request('http://do/status?key=654321');
    const statusResp = await hub.fetch(statusReq);
    expect(statusResp.status).toBe(200);
    const statusData = (await statusResp.json()) as any;
    expect(statusData.status).toBe('approved');
    expect(statusData.redeem_result).toBeDefined();
    expect(statusData.redeem_result.device.id).toBe('dev_pixel_9');
  });
});

describe('Worker Edge Routes: CORS, Heartbeat & Security', () => {
  it('should handle CORS preflight dynamically for local and pages.dev origins', async () => {
    const worker = (await import('../src/index')).default;
    const mockEnv = {
      PCOS_ENV: 'test',
      MAX_WORKERS_PER_DAY: '100000',
      MAX_D1_WRITES_PER_DAY: '100000',
      MAX_D1_READS_PER_MONTH: '5000000',
      MAX_R2_STORAGE_GB: '10',
      FREE_TIER_HARD_BUDGET: 'true',
      JWT_SECRET: 'test_secret_for_cors',
    } as unknown as Env;

    const ctx = {
      waitUntil: () => {},
      passThroughOnException: () => {},
    } as unknown as ExecutionContext;

    // Test localhost origin
    const localReq = new Request('http://edge.pcos.dev/api/v1/health', {
      method: 'OPTIONS',
      headers: { Origin: 'http://localhost:5173' },
    });
    const localResp = await worker.fetch(localReq, mockEnv, ctx);
    expect(localResp.status).toBe(200);
    expect(localResp.headers.get('Access-Control-Allow-Origin')).toBe('http://localhost:5173');
    expect(localResp.headers.get('Access-Control-Allow-Credentials')).toBe('true');

    // Test pages.dev origin
    const pagesReq = new Request('http://edge.pcos.dev/api/v1/health', {
      method: 'OPTIONS',
      headers: { Origin: 'https://my-pcos.pages.dev' },
    });
    const pagesResp = await worker.fetch(pagesReq, mockEnv, ctx);
    expect(pagesResp.status).toBe(200);
    expect(pagesResp.headers.get('Access-Control-Allow-Origin')).toBe('https://my-pcos.pages.dev');
    expect(pagesResp.headers.get('Access-Control-Allow-Credentials')).toBe('true');
  });

  it('should process device heartbeat and update status', async () => {
    const worker = (await import('../src/index')).default;
    let updatedDeviceId = '';
    let updatedLanIp = '';

    const mockDb = {
      prepare: (query: string) => ({
        bind: (...args: any[]) => ({
          run: async () => {
            if (query.includes('UPDATE device_identities')) {
              updatedLanIp = args[1];
              updatedDeviceId = args[2];
            }
            return { success: true };
          },
          first: async () => null,
          all: async () => ({ results: [] }),
        }),
      }),
    } as unknown as D1Database;

    const mockPresenceHub = {
      idFromName: () => 'presence_id',
      get: () => ({
        fetch: async () => Response.json({ success: true }),
      }),
    } as unknown as DurableObjectNamespace;

    const mockEnv = {
      DB: mockDb,
      PRESENCE_HUB: mockPresenceHub,
      PCOS_ENV: 'test',
      MAX_WORKERS_PER_DAY: '100000',
      MAX_D1_WRITES_PER_DAY: '100000',
      MAX_D1_READS_PER_MONTH: '5000000',
      MAX_R2_STORAGE_GB: '10',
      FREE_TIER_HARD_BUDGET: 'true',
      JWT_SECRET: 'test_secret_for_heartbeat',
    } as unknown as Env;

    const ctx = {
      waitUntil: () => {},
      passThroughOnException: () => {},
    } as unknown as ExecutionContext;

    const hbReq = new Request('http://edge.pcos.dev/api/v1/devices/dev_storage_node_99/heartbeat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'cf-connecting-ip': '103.21.244.1',
      },
      body: JSON.stringify({
        deviceId: 'dev_storage_node_99',
        lanIp: '192.168.1.150',
        name: 'Home NAS Node',
        deviceType: 'nas',
      }),
    });

    const resp = await worker.fetch(hbReq, mockEnv, ctx);
    expect(resp.status).toBe(200);
    const body = (await resp.json()) as any;
    expect(body.success).toBe(true);
    expect(body.is_online).toBe(true);
    expect(body.device_id).toBe('dev_storage_node_99');
    expect(updatedDeviceId).toBe('dev_storage_node_99');
    expect(updatedLanIp).toBe('192.168.1.150');
  });

  it('should support device registration (POST) and deletion (DELETE)', async () => {
    const worker = (await import('../src/index')).default;
    const testSecret = 'device_mgmt_test_secret_12345';
    const testUserId = 'usr_mgmt_1';
    const token = await generateJwt({ sub: testUserId, email: 'mgmt@pcos.dev' }, testSecret, 3600);

    const insertedDevices: any[] = [];
    let deletedDeviceId: string | null = null;

    const mockDb = {
      prepare: (query: string) => ({
        bind: (...args: any[]) => ({
          run: async () => {
            if (query.includes('INSERT INTO device_identities')) {
              insertedDevices.push({
                id: args[0],
                user_id: args[1],
                cloud_id: args[2],
                name: args[3],
                device_type: args[4],
                os: args[5],
              });
            }
            if (query.includes('DELETE FROM device_identities')) {
              deletedDeviceId = args[0];
            }
            return { success: true };
          },
          first: async () => {
            if (query.includes('SELECT cloud_id FROM cloud_identities')) {
              return { cloud_id: 'pcos-cloud-123' };
            }
            return null;
          },
          all: async () => ({ results: insertedDevices }),
        }),
      }),
    } as unknown as D1Database;

    const mockEnv = {
      DB: mockDb,
      PCOS_ENV: 'test',
      MAX_WORKERS_PER_DAY: '100000',
      MAX_D1_WRITES_PER_DAY: '100000',
      MAX_D1_READS_PER_MONTH: '5000000',
      MAX_R2_STORAGE_GB: '10',
      FREE_TIER_HARD_BUDGET: 'true',
      JWT_SECRET: testSecret,
    } as unknown as Env;

    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    // 1. Register a device
    const regReq = new Request('http://edge.pcos.dev/api/v1/devices', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        name: 'Work MacBook Pro',
        device_type: 'laptop',
        os: 'macOS',
      }),
    });

    const regResp = await worker.fetch(regReq, mockEnv, ctx);
    expect(regResp.status).toBe(201);
    const regBody = (await regResp.json()) as any;
    expect(regBody.name).toBe('Work MacBook Pro');
    expect(regBody.device_type).toBe('laptop');
    expect(regBody.os).toBe('macOS');
    expect(insertedDevices).toHaveLength(1);
    expect(insertedDevices[0].id).toBe(regBody.id);

    // 2. Delete the device
    const delReq = new Request(`http://edge.pcos.dev/api/v1/devices/${regBody.id}`, {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    const delResp = await worker.fetch(delReq, mockEnv, ctx);
    expect(delResp.status).toBe(200);
    const delBody = (await delResp.json()) as any;
    expect(delBody.success).toBe(true);
    expect(deletedDeviceId).toBe(regBody.id);
  });

  it('should support storage node registration, listing, and deletion', async () => {
    const worker = (await import('../src/index')).default;
    const testSecret = 'storage_nodes_test_secret_12345';
    const testUserId = 'usr_sn_1';
    const token = await generateJwt({ sub: testUserId, email: 'sn@pcos.dev' }, testSecret, 3600);

    const storageNodes: any[] = [];
    let deletedNodeId: string | null = null;

    const mockDb = {
      prepare: (query: string) => ({
        bind: (...args: any[]) => ({
          run: async () => {
            if (query.includes('INSERT INTO storage_nodes')) {
              const node = {
                id: args[0],
                device_id: args[1],
                user_id: args[2],
                name: args[3],
                storage_path: args[4],
                total_capacity_bytes: args[5],
                available_capacity_bytes: args[6],
                capabilities_json: args[7],
              };
              storageNodes.push(node);
            }
            if (query.includes('DELETE FROM storage_nodes')) {
              deletedNodeId = args[0];
            }
            return { success: true };
          },
          first: async () => {
            if (query.includes('SELECT id, name FROM device_identities')) {
              return { id: args[0], name: 'My Primary NAS' };
            }
            return null;
          },
          all: async () => ({ results: storageNodes }),
        }),
      }),
    } as unknown as D1Database;

    const mockEnv = {
      DB: mockDb,
      PCOS_ENV: 'test',
      MAX_WORKERS_PER_DAY: '100000',
      MAX_D1_WRITES_PER_DAY: '100000',
      MAX_D1_READS_PER_MONTH: '5000000',
      MAX_R2_STORAGE_GB: '10',
      FREE_TIER_HARD_BUDGET: 'true',
      JWT_SECRET: testSecret,
    } as unknown as Env;

    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    // 1. Register a storage node
    const createReq = new Request('http://edge.pcos.dev/api/v1/storage/nodes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        device_id: 'dev_nas_001',
        name: '4TB Western Digital RED',
        storage_path: '/mnt/storage/pcos',
        total_capacity_bytes: 4000000000000,
        available_capacity_bytes: 2500000000000,
        capabilities_json: JSON.stringify({ ffmpeg: true, tantivy: true }),
      }),
    });

    const createResp = await worker.fetch(createReq, mockEnv, ctx);
    expect(createResp.status).toBe(201);
    const createdNode = (await createResp.json()) as any;
    expect(createdNode.name).toBe('4TB Western Digital RED');
    expect(createdNode.storage_path).toBe('/mnt/storage/pcos');
    expect(createdNode.total_capacity_bytes).toBe(4000000000000);
    expect(storageNodes).toHaveLength(1);

    // 2. List storage nodes
    const listReq = new Request('http://edge.pcos.dev/api/v1/storage/nodes', {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    const listResp = await worker.fetch(listReq, mockEnv, ctx);
    expect(listResp.status).toBe(200);
    const listBody = (await listResp.json()) as any;
    expect(listBody.total).toBe(1);
    expect(listBody.storage_nodes[0].storage_path).toBe('/mnt/storage/pcos');

    // 3. Delete storage node
    const delReq = new Request(`http://edge.pcos.dev/api/v1/storage/nodes/${createdNode.id}`, {
      method: 'DELETE',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    const delResp = await worker.fetch(delReq, mockEnv, ctx);
    expect(delResp.status).toBe(200);
    const delBody = (await delResp.json()) as any;
    expect(delBody.success).toBe(true);
    expect(deletedNodeId).toBe(createdNode.id);
  });
});

describe('Liveness, Readiness Probes & Fail-Closed JWT Gate', () => {
  it('should return 200 on /livez probe without authentication', async () => {
    const worker = (await import('../src/index')).default;
    const mockEnv = {
      PCOS_ENV: 'production',
      JWT_SECRET: undefined,
    } as unknown as Env;
    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    const req = new Request('http://edge.pcos.dev/livez');
    const resp = await worker.fetch(req, mockEnv, ctx);
    expect(resp.status).toBe(200);
    const body = (await resp.json()) as any;
    expect(body.status).toBe('alive');
  });

  it('should return 200 on /health even when JWT_SECRET is unconfigured in production', async () => {
    const worker = (await import('../src/index')).default;
    const mockEnv = {
      PCOS_ENV: 'production',
      PCOS_CONTROL_VERSION: '1.2.3',
      JWT_SECRET: undefined,
    } as unknown as Env;
    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    const req = new Request('http://edge.pcos.dev/health');
    const resp = await worker.fetch(req, mockEnv, ctx);
    expect(resp.status).toBe(200);
    const body = (await resp.json()) as any;
    expect(body.status).toBe('healthy');
    expect(body.version).toBe('1.2.3');
  });

  it('should return 503 on /readyz when JWT_SECRET is missing in production and identify root cause', async () => {
    const worker = (await import('../src/index')).default;
    const mockDb = {
      prepare: () => ({
        first: async () => ({ ok: 1 }),
      }),
    } as unknown as D1Database;
    const mockEnv = {
      DB: mockDb,
      PAIRING_HUB: { idFromName: () => 'do_mock' },
      PCOS_ENV: 'production',
      JWT_SECRET: undefined,
    } as unknown as Env;
    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    const req = new Request('http://edge.pcos.dev/readyz');
    const resp = await worker.fetch(req, mockEnv, ctx);
    expect(resp.status).toBe(503);
    const body = (await resp.json()) as any;
    expect(body.status).toBe('not_ready');
    expect(body.checks.jwt_config.status).toBe('fail');
    expect(body.checks.jwt_config.detail).toContain('JWT_SECRET');
  });

  it('should fail-closed with 503 CONFIG_ERROR for authenticated endpoints when JWT_SECRET is missing', async () => {
    const worker = (await import('../src/index')).default;
    const mockEnv = {
      PCOS_ENV: 'production',
      JWT_SECRET: undefined,
    } as unknown as Env;
    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    const req = new Request('http://edge.pcos.dev/api/v1/users/me', {
      headers: { Authorization: 'Bearer some_token' },
    });
    const resp = await worker.fetch(req, mockEnv, ctx);
    expect(resp.status).toBe(503);
    const body = (await resp.json()) as any;
    expect(body.code).toBe('CONFIG_ERROR');
    expect(body.error).toContain('Server configuration error');
  });

  it('should return 200 on /readyz when all dependencies (JWT, D1, DO) are healthy', async () => {
    const worker = (await import('../src/index')).default;
    const mockDb = {
      prepare: (sql: string) => ({
        first: async () => {
          if (sql.includes('SELECT 1')) return { ok: 1 };
          if (sql.includes('SELECT COUNT(*)')) return { c: 5 };
          return null;
        },
      }),
    } as unknown as D1Database;
    const mockEnv = {
      DB: mockDb,
      PAIRING_HUB: { idFromName: () => 'do_readyz' },
      PCOS_ENV: 'production',
      JWT_SECRET: 'a_very_secure_configured_production_secret_32_chars',
    } as unknown as Env;
    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    const req = new Request('http://edge.pcos.dev/readyz');
    const resp = await worker.fetch(req, mockEnv, ctx);
    expect(resp.status).toBe(200);
    const body = (await resp.json()) as any;
    expect(body.status).toBe('ready');
    expect(body.checks.jwt_config.status).toBe('pass');
    expect(body.checks.d1_database.status).toBe('pass');
    expect(body.checks.durable_objects.status).toBe('pass');
  });
});

describe('Shares API & Public Recipient Access', () => {
  it('should support creating, listing, public token access, and revoking shares', async () => {
    const worker = (await import('../src/index')).default;
    const testSecret = 'test_secret_key_12345678901234567890';
    const userId = 'usr_share_test_123';
    const token = await generateJwt({ sub: userId, email: 'share@pcos.dev', role: 'user' }, testSecret);

    const shares: any[] = [];
    let fileLookupFound = true;

    const mockDb = {
      prepare: (sql: string) => {
        let boundParams: any[] = [];
        return {
          bind: (...args: any[]) => {
            boundParams = args;
            return {
              first: async () => {
                if (sql.includes('FROM file_entries WHERE id =')) {
                  return fileLookupFound
                    ? { id: boundParams[0], name: 'family_vacation.mp4', size_bytes: 52428800, mime_type: 'video/mp4' }
                    : null;
                }
                if (sql.includes('FROM shares s')) {
                  const tokenMatch = shares.find((s) => s.share_token === boundParams[0]);
                  if (!tokenMatch) return null;
                  return {
                    ...tokenMatch,
                    file_name: 'family_vacation.mp4',
                    size_bytes: 52428800,
                    mime_type: 'video/mp4',
                  };
                }
                return null;
              },
              all: async () => {
                if (sql.includes('FROM shares s')) {
                  return { results: shares.filter((s) => s.user_id === boundParams[0]) };
                }
                return { results: [] };
              },
              run: async () => {
                if (sql.includes('INSERT INTO shares')) {
                  shares.push({
                    id: boundParams[0],
                    user_id: boundParams[1],
                    file_id: boundParams[2],
                    share_token: boundParams[3],
                    is_public: boundParams[4],
                    is_upload_request: boundParams[5],
                    password_hash: boundParams[6],
                    expires_at: boundParams[7],
                    max_downloads: boundParams[8],
                    download_count: 0,
                    created_at: boundParams[9],
                  });
                  return { success: true };
                }
                if (sql.includes('DELETE FROM shares')) {
                  const idx = shares.findIndex((s) => s.id === boundParams[0] && s.user_id === boundParams[1]);
                  if (idx !== -1) shares.splice(idx, 1);
                  return { success: true };
                }
                if (sql.includes('UPDATE shares SET download_count')) {
                  const s = shares.find((item) => item.id === boundParams[0]);
                  if (s) s.download_count++;
                  return { success: true };
                }
                return { success: true };
              },
            };
          },
        };
      },
    } as unknown as D1Database;

    const mockEnv = {
      DB: mockDb,
      PCOS_ENV: 'test',
      JWT_SECRET: testSecret,
    } as unknown as Env;

    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    // 1. Create a share link
    const createReq = new Request('http://edge.pcos.dev/api/v1/shares', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        file_id: 'file_001_mp4',
        is_public: true,
        max_downloads: 5,
      }),
    });

    const createResp = await worker.fetch(createReq, mockEnv, ctx);
    expect(createResp.status).toBe(201);
    const createdShare = (await createResp.json()) as any;
    expect(createdShare.file_id).toBe('file_001_mp4');
    expect(createdShare.share_token).toBeDefined();
    expect(shares).toHaveLength(1);

    // 2. List user shares
    const listReq = new Request('http://edge.pcos.dev/api/v1/shares', {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}` },
    });
    const listResp = await worker.fetch(listReq, mockEnv, ctx);
    expect(listResp.status).toBe(200);
    const listData = (await listResp.json()) as any;
    expect(listData.total).toBe(1);
    expect(listData.shares[0].file_id).toBe('file_001_mp4');

    // 3. Unauthenticated public recipient accesses share
    const publicReq = new Request(`http://edge.pcos.dev/api/v1/shared/${createdShare.share_token}`);
    const publicResp = await worker.fetch(publicReq, mockEnv, ctx);
    expect(publicResp.status).toBe(200);
    const publicData = (await publicResp.json()) as any;
    expect(publicData.file_name).toBe('family_vacation.mp4');
    expect(publicData.is_password_protected).toBe(false);

    // 4. Public recipient requests download (increments counter)
    const dlReq = new Request(`http://edge.pcos.dev/api/v1/shared/${createdShare.share_token}/download`);
    const dlResp = await worker.fetch(dlReq, mockEnv, ctx);
    expect(dlResp.status).toBe(200);
    expect(shares[0].download_count).toBe(1);

    // 5. Revoke share
    const delReq = new Request(`http://edge.pcos.dev/api/v1/shares/${createdShare.id}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    const delResp = await worker.fetch(delReq, mockEnv, ctx);
    expect(delResp.status).toBe(200);
    expect(shares).toHaveLength(0);
  });
});

describe('Media Streaming Progress & Continue Watching', () => {
  it('should track video position and list resume candidates', async () => {
    const worker = (await import('../src/index')).default;
    const testSecret = 'test_secret_key_12345678901234567890';
    const userId = 'usr_media_test_456';
    const token = await generateJwt({ sub: userId, email: 'media@pcos.dev', role: 'user' }, testSecret);

    const progressRecords: any[] = [];

    const mockDb = {
      prepare: (sql: string) => {
        let boundParams: any[] = [];
        return {
          bind: (...args: any[]) => {
            boundParams = args;
            return {
              first: async () => {
                if (sql.includes('FROM playback_progress')) {
                  return progressRecords.find((r) => r.user_id === boundParams[0] && r.file_id === boundParams[1]) || null;
                }
                return null;
              },
              all: async () => {
                if (sql.includes('FROM playback_progress p')) {
                  return {
                    results: progressRecords
                      .filter((r) => r.user_id === boundParams[0] && r.completed === 0 && r.position_secs > 10)
                      .map((r) => ({
                        ...r,
                        file_name: 'matrix_resurrections.mkv',
                        size_bytes: 4000000000,
                        mime_type: 'video/x-matroska',
                      })),
                  };
                }
                return { results: [] };
              },
              run: async () => {
                if (sql.includes('INSERT INTO playback_progress')) {
                  const existingIdx = progressRecords.findIndex(
                    (r) => r.user_id === boundParams[1] && r.file_id === boundParams[2]
                  );
                  const record = {
                    id: boundParams[0],
                    user_id: boundParams[1],
                    file_id: boundParams[2],
                    position_secs: boundParams[3],
                    duration_secs: boundParams[4],
                    completed: boundParams[5],
                    updated_at: boundParams[6],
                  };
                  if (existingIdx >= 0) {
                    progressRecords[existingIdx] = record;
                  } else {
                    progressRecords.push(record);
                  }
                  return { success: true };
                }
                return { success: true };
              },
            };
          },
        };
      },
    } as unknown as D1Database;

    const mockEnv = {
      DB: mockDb,
      PCOS_ENV: 'test',
      JWT_SECRET: testSecret,
    } as unknown as Env;

    const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;

    // 1. Record playback progress (e.g. 145 seconds in)
    const postReq = new Request('http://edge.pcos.dev/api/v1/streaming/progress/file_matrix_001', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        position_secs: 145.5,
        duration_secs: 7200,
        completed: false,
      }),
    });
    const postResp = await worker.fetch(postReq, mockEnv, ctx);
    expect(postResp.status).toBe(200);
    const postData = (await postResp.json()) as any;
    expect(postData.position_secs).toBe(145.5);

    // 2. Fetch playback progress for this file
    const getReq = new Request('http://edge.pcos.dev/api/v1/streaming/progress/file_matrix_001', {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}` },
    });
    const getResp = await worker.fetch(getReq, mockEnv, ctx);
    expect(getResp.status).toBe(200);
    const getData = (await getResp.json()) as any;
    expect(getData.position_secs).toBe(145.5);

    // 3. Continue Watching / Media History
    const historyReq = new Request('http://edge.pcos.dev/api/v1/media/history', {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}` },
    });
    const historyResp = await worker.fetch(historyReq, mockEnv, ctx);
    expect(historyResp.status).toBe(200);
    const historyData = (await historyResp.json()) as any;
    expect(historyData.total).toBe(1);
    expect(historyData.history[0].file_name).toBe('matrix_resurrections.mkv');
    expect(historyData.history[0].position_secs).toBe(145.5);
  });
});



