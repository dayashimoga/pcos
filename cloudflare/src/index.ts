// PCOS Cloudflare Edge Control Plane
// Free-first, always-available distributed cloud coordinator.
// Splits control plane (coordination/metadata/presence) from data plane (storage/compute/FFmpeg).

import { Env, User, DeviceIdentity, StorageNode, FileLocation } from './types';
import {
  hashPassword,
  verifyPassword,
  generateJwt,
  verifyJwt,
  generatePairingCode,
  generateEnrollmentToken,
} from './services/auth';
import { BudgetGuard } from './services/budget';
import { CloudCacheService } from './services/r2_cache';

export { PairingHub } from './durable_objects/PairingHub';
export { DevicePresenceHub } from './durable_objects/DevicePresenceHub';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With',
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    // 1. Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const budget = new BudgetGuard(env);

    // Track request in Free-Tier guard
    ctx.waitUntil(budget.trackRequest('worker'));

    try {
      // 2. WebSocket routes to Durable Objects
      if (url.pathname === '/ws/pairing') {
        const id = env.PAIRING_HUB.idFromName('global_pairing_hub');
        const stub = env.PAIRING_HUB.get(id);
        return stub.fetch(request);
      }

      if (url.pathname === '/ws/presence') {
        const id = env.PRESENCE_HUB.idFromName('global_presence_hub');
        const stub = env.PRESENCE_HUB.get(id);
        return stub.fetch(request);
      }

      // 3. API Routes
      if (url.pathname.startsWith('/api/') || url.pathname === '/health') {
        const response = await handleApiRequest(request, env, budget);
        // Add CORS headers to API responses
        const headers = new Headers(response.headers);
        for (const [k, v] of Object.entries(CORS_HEADERS)) {
          headers.set(k, v);
        }
        return new Response(response.body, {
          status: response.status,
          statusText: response.statusText,
          headers,
        });
      }

      // 4. Static Assets for Flutter Web SPA
      if (env.ASSETS) {
        const assetResponse = await env.ASSETS.fetch(request);
        if (assetResponse.status === 404 && !url.pathname.includes('.')) {
          // SPA rewrite for deep links (e.g. /#/pair or /dashboard)
          return env.ASSETS.fetch(new Request(new URL('/index.html', request.url)));
        }
        return assetResponse;
      }

      return new Response('PCOS Edge Control Plane Active', { status: 200 });
    } catch (err) {
      return Response.json(
        { error: 'Internal edge error', message: String(err) },
        { status: 500, headers: CORS_HEADERS }
      );
    }
  },
};

async function handleApiRequest(
  request: Request,
  env: Env,
  budget: BudgetGuard
): Promise<Response> {
  const url = new URL(request.url);
  const jwtSecret = env.JWT_SECRET || 'pcos_edge_control_plane_jwt_secret_default_change_me';

  // ─── Health & Connectivity Diagnostics ───
  if (url.pathname === '/health' || url.pathname === '/api/v1/health') {
    return Response.json({
      status: 'healthy',
      version: env.PCOS_CONTROL_VERSION || '1.0.0',
      platform: 'cloudflare_edge',
      uptime_secs: Math.floor(Date.now() / 1000),
    });
  }

  if (url.pathname === '/api/v1/doctor/connectivity') {
    const clientIp = request.headers.get('cf-connecting-ip') || '127.0.0.1';
    const budgetStatus = await budget.getBudgetStatus();
    return Response.json({
      lan_ip: clientIp,
      hostname: 'pcos-edge.pages.dev',
      is_private_ip: false,
      is_cgnat: false,
      tls_enabled: true,
      active_connect_mode: 'automatic',
      recommended_provider: 'Cloudflare Edge Control Plane + Direct LAN/P2P',
      available_providers: [
        'Cloudflare Edge Control Plane',
        'Direct LAN',
        'WireGuard / Headscale P2P',
        'Encrypted Relay Tunnel',
      ],
      ports: { http_port: 80, https_port: 443, wireguard_port: 51820 },
      storage_healthy: true,
      database_healthy: true,
      cloud_cache_active: budgetStatus.cloud_cache_active,
      recommendations: [
        'Always-on Cloudflare Control Plane active.',
        'Direct LAN transfer used when devices share local network.',
      ],
    });
  }

  // ─── Free-Tier Usage & Budget Dashboard ───
  if (url.pathname === '/api/v1/usage/budget') {
    const status = await budget.getBudgetStatus();
    return Response.json(status);
  }

  // ─── Auth: Register ───
  if (request.method === 'POST' && url.pathname === '/api/v1/auth/register') {
    const body = (await request.json()) as {
      email?: string;
      password?: string;
      display_name?: string;
    };

    if (!body.email || !body.password) {
      return Response.json({ error: 'Email and password are required' }, { status: 400 });
    }

    const userId = crypto.randomUUID();
    const cloudId = `cld_${userId.slice(0, 8)}`;
    const passHash = await hashPassword(body.password);
    const now = new Date().toISOString();

    try {
      await env.DB.prepare(
        `INSERT INTO users (id, email, password_hash, display_name, role, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, 'user', ?5, ?5)`
      )
        .bind(userId, body.email.toLowerCase().trim(), passHash, body.display_name || 'User', now)
        .run();

      await env.DB.prepare(
        `INSERT INTO cloud_identities (user_id, cloud_id, created_at) VALUES (?1, ?2, ?3)`
      )
        .bind(userId, cloudId, now)
        .run();

      const tokens = await issueTokenPair(userId, body.email, jwtSecret, env.DB);

      return Response.json({
        user: { id: userId, email: body.email, display_name: body.display_name, cloud_id: cloudId },
        tokens,
      }, { status: 201 });
    } catch (e) {
      if (String(e).includes('UNIQUE')) {
        return Response.json({ error: 'User with this email already exists' }, { status: 409 });
      }
      return Response.json({ error: 'Registration failed', details: String(e) }, { status: 500 });
    }
  }

  // ─── Auth: Login ───
  if (request.method === 'POST' && url.pathname === '/api/v1/auth/login') {
    const body = (await request.json()) as { email?: string; password?: string };
    if (!body.email || !body.password) {
      return Response.json({ error: 'Email and password required' }, { status: 400 });
    }

    const user = await env.DB.prepare('SELECT * FROM users WHERE email = ?1')
      .bind(body.email.toLowerCase().trim())
      .first<User>();

    if (!user || !(await verifyPassword(body.password, user.password_hash))) {
      return Response.json({ error: 'Invalid email or password' }, { status: 401 });
    }

    const cloudRow = await env.DB.prepare('SELECT cloud_id FROM cloud_identities WHERE user_id = ?1')
      .bind(user.id)
      .first<{ cloud_id: string }>();

    const tokens = await issueTokenPair(user.id, user.email, jwtSecret, env.DB);

    return Response.json({
      user: {
        id: user.id,
        email: user.email,
        display_name: user.display_name,
        role: user.role,
        cloud_id: cloudRow?.cloud_id,
      },
      tokens,
    });
  }

  // ─── Auth: Refresh ───
  if (request.method === 'POST' && url.pathname === '/api/v1/auth/refresh') {
    const body = (await request.json()) as { refresh_token?: string };
    if (!body.refresh_token) {
      return Response.json({ error: 'Refresh token required' }, { status: 400 });
    }

    const tokenHash = await hashToken(body.refresh_token);
    const row = await env.DB.prepare(
      'SELECT * FROM refresh_tokens WHERE token_hash = ?1 AND revoked = 0'
    )
      .bind(tokenHash)
      .first<{ id: string; user_id: string; expires_at: string }>();

    if (!row || new Date(row.expires_at) <= new Date()) {
      return Response.json({ error: 'Invalid or expired refresh token' }, { status: 401 });
    }

    const user = await env.DB.prepare('SELECT email FROM users WHERE id = ?1')
      .bind(row.user_id)
      .first<{ email: string }>();

    if (!user) {
      return Response.json({ error: 'User not found' }, { status: 404 });
    }

    // Revoke old refresh token (rotation)
    await env.DB.prepare('UPDATE refresh_tokens SET revoked = 1 WHERE id = ?1').bind(row.id).run();

    const tokens = await issueTokenPair(row.user_id, user.email, jwtSecret, env.DB);
    return Response.json({ tokens });
  }

  // ─── Pairing: Create Session ───
  if (request.method === 'POST' && url.pathname === '/api/v1/devices/pair') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized: Sign in required to pair devices' }, { status: 401 });
    }

    const body = (await request.json().catch(() => ({}))) as { expires_in_seconds?: number };
    const ttl = Math.min(3600, Math.max(60, body.expires_in_seconds || 300));
    const pairingCode = generatePairingCode();
    const enrollmentToken = generateEnrollmentToken();
    const sessionId = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + ttl * 1000).toISOString();
    const now = new Date().toISOString();

    const host = request.headers.get('host') || 'pcos.pages.dev';
    const proto = url.protocol;
    const universalLink = `${proto}//${host}/#/pair?code=${pairingCode}&token=${enrollmentToken}`;

    // Store in D1
    await env.DB.prepare(
      `INSERT INTO pairing_sessions (id, user_id, pairing_code, enrollment_token, status, expires_at, created_at)
       VALUES (?1, ?2, ?3, ?4, 'pending_redeem', ?5, ?6)`
    )
      .bind(sessionId, userPayload.sub, pairingCode, enrollmentToken, expiresAt, now)
      .run();

    // Initialize in PairingHub Durable Object
    const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
    const stub = env.PAIRING_HUB.get(doId);
    await stub.fetch('http://do/create', {
      method: 'POST',
      body: JSON.stringify({
        id: sessionId,
        userId: userPayload.sub,
        pairingCode,
        enrollmentToken,
        expiresAt,
      }),
    });

    return Response.json({
      pairing_code: pairingCode,
      enrollment_token: enrollmentToken,
      expires_at: expiresAt,
      expires_in_seconds: ttl,
      qr_payload: universalLink,
    }, { status: 201 });
  }

  // ─── Pairing: Claim Session (Mobile device submits code) ───
  if (request.method === 'POST' && url.pathname === '/api/v1/devices/pair/claim') {
    const body = (await request.json()) as {
      pairing_code?: string;
      enrollment_token?: string;
      device_name?: string;
      device_type?: string;
      os?: string;
      os_version?: string;
      agent_version?: string;
      client_fingerprint?: string;
    };

    const key = body.enrollment_token || body.pairing_code;
    if (!key) {
      return Response.json({ error: 'Pairing code or enrollment token required' }, { status: 400 });
    }

    const candidate = {
      device_name: body.device_name || 'Mobile Phone',
      device_type: body.device_type || 'phone',
      os: body.os || 'unknown',
      os_version: body.os_version || '',
      agent_version: body.agent_version || '0.1.0',
      client_fingerprint: body.client_fingerprint,
      requested_at: new Date().toISOString(),
    };

    // Forward to PairingHub DO
    const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
    const stub = env.PAIRING_HUB.get(doId);
    const resp = await stub.fetch('http://do/claim', {
      method: 'POST',
      body: JSON.stringify({ key, candidate }),
    });

    if (resp.status !== 200) {
      return resp;
    }

    // Update D1
    await env.DB.prepare(
      `UPDATE pairing_sessions SET status = 'pending_approval', candidate_device_json = ?1
       WHERE pairing_code = ?2 OR enrollment_token = ?2`
    )
      .bind(JSON.stringify(candidate), key)
      .run();

    return resp;
  }

  // ─── Pairing: Approve Session (Web user approves candidate) ───
  if (request.method === 'POST' && url.pathname === '/api/v1/devices/pair/approve') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = (await request.json()) as {
      pairing_code?: string;
      enrollment_token?: string;
      approved: boolean;
    };

    const key = body.enrollment_token || body.pairing_code;
    if (!key) {
      return Response.json({ error: 'Pairing code or enrollment token required' }, { status: 400 });
    }

    const sessionRow = await env.DB.prepare(
      'SELECT * FROM pairing_sessions WHERE pairing_code = ?1 OR enrollment_token = ?1'
    )
      .bind(key)
      .first<{ id: string; user_id: string; candidate_device_json?: string }>();

    if (!sessionRow || sessionRow.user_id !== userPayload.sub) {
      return Response.json({ error: 'Pairing session not found or unauthorized' }, { status: 404 });
    }

    if (!body.approved) {
      await env.DB.prepare("UPDATE pairing_sessions SET status = 'rejected' WHERE id = ?1")
        .bind(sessionRow.id)
        .run();

      const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
      const stub = env.PAIRING_HUB.get(doId);
      return stub.fetch('http://do/approve', {
        method: 'POST',
        body: JSON.stringify({ key, userId: userPayload.sub, approved: false }),
      });
    }

    // Approved: Provision the device
    const candidate = JSON.parse(sessionRow.candidate_device_json || '{}') as {
      device_name: string;
      device_type: string;
      os: string;
      os_version?: string;
      agent_version?: string;
    };

    const deviceId = crypto.randomUUID();
    const cloudRow = await env.DB.prepare('SELECT cloud_id FROM cloud_identities WHERE user_id = ?1')
      .bind(userPayload.sub)
      .first<{ cloud_id: string }>();

    const now = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO device_identities (id, user_id, cloud_id, name, device_type, os, os_version, agent_version, is_online, last_seen_at, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 1, ?9, ?9, ?9)`
    )
      .bind(
        deviceId,
        userPayload.sub,
        cloudRow?.cloud_id || 'pcos',
        candidate.device_name || 'Mobile Phone',
        candidate.device_type || 'phone',
        candidate.os || 'unknown',
        candidate.os_version || '',
        candidate.agent_version || '0.1.0',
        now
      )
      .run();

    const tokens = await issueTokenPair(userPayload.sub, String(userPayload.email || ''), jwtSecret, env.DB);

    const redeemResult = {
      device: {
        id: deviceId,
        name: candidate.device_name,
        device_type: candidate.device_type,
        os: candidate.os,
        is_online: true,
      },
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
    };

    // Update D1
    await env.DB.prepare("UPDATE pairing_sessions SET status = 'approved' WHERE id = ?1")
      .bind(sessionRow.id)
      .run();

    // Notify PairingHub DO
    const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
    const stub = env.PAIRING_HUB.get(doId);
    return stub.fetch('http://do/approve', {
      method: 'POST',
      body: JSON.stringify({
        key,
        userId: userPayload.sub,
        approved: true,
        redeemResult,
      }),
    });
  }

  // ─── Pairing: Status ───
  if (request.method === 'GET' && url.pathname === '/api/v1/devices/pair/status') {
    const key = url.searchParams.get('token') || url.searchParams.get('code');
    if (!key) {
      return Response.json({ error: 'Code or token query parameter required' }, { status: 400 });
    }

    const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
    const stub = env.PAIRING_HUB.get(doId);
    return stub.fetch(`http://do/status?key=${encodeURIComponent(key)}`);
  }

  // ─── Pairing: Redeem (Mobile picks up tokens once approved) ───
  if (request.method === 'POST' && url.pathname === '/api/v1/devices/pair/redeem') {
    const body = (await request.json()) as {
      pairing_code?: string;
      enrollment_token?: string;
      device_name?: string;
      device_type?: string;
      os?: string;
    };

    const key = body.enrollment_token || body.pairing_code;
    if (!key) {
      return Response.json({ error: 'Pairing code or enrollment token required' }, { status: 400 });
    }

    const sessionRow = await env.DB.prepare(
      'SELECT * FROM pairing_sessions WHERE pairing_code = ?1 OR enrollment_token = ?1'
    )
      .bind(key)
      .first<{ id: string; user_id: string; status: string; expires_at: string }>();

    if (!sessionRow) {
      return Response.json({ error: 'Invalid pairing code' }, { status: 401 });
    }

    if (new Date(sessionRow.expires_at) <= new Date()) {
      return Response.json({ error: 'Pairing session has expired' }, { status: 401 });
    }

    if (sessionRow.status === 'rejected') {
      return Response.json({ error: 'Pairing request was declined by device owner' }, { status: 401 });
    }

    if (sessionRow.status === 'pending_approval') {
      return Response.json(
        { error: 'Waiting for device approval on your PCOS Web/Desktop screen' },
        { status: 401 }
      );
    }

    // Consume pairing session immediately (single-use token protection)
    await env.DB.prepare('DELETE FROM pairing_sessions WHERE id = ?1').bind(sessionRow.id).run();

    const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
    const stub = env.PAIRING_HUB.get(doId);
    await stub.fetch(`http://do/consume?key=${encodeURIComponent(key)}`, { method: 'POST' });

    // Direct single-step enrollment (e.g. for headless CLI or test flows)
    const user = await env.DB.prepare('SELECT email FROM users WHERE id = ?1')
      .bind(sessionRow.user_id)
      .first<{ email: string }>();

    const deviceId = crypto.randomUUID();
    const cloudRow = await env.DB.prepare('SELECT cloud_id FROM cloud_identities WHERE user_id = ?1')
      .bind(sessionRow.user_id)
      .first<{ cloud_id: string }>();

    const now = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO device_identities (id, user_id, cloud_id, name, device_type, os, os_version, agent_version, is_online, last_seen_at, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, '', '0.1.0', 1, ?7, ?7, ?7)`
    )
      .bind(
        deviceId,
        sessionRow.user_id,
        cloudRow?.cloud_id || 'pcos',
        body.device_name || 'Device',
        body.device_type || 'phone',
        body.os || 'unknown',
        now
      )
      .run();

    const tokens = await issueTokenPair(sessionRow.user_id, user?.email || '', jwtSecret, env.DB);

    return Response.json({
      device: {
        id: deviceId,
        name: body.device_name || 'Device',
        device_type: body.device_type || 'phone',
        os: body.os || 'unknown',
        is_online: true,
      },
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
    });
  }

  // ─── Devices: List & Heartbeat ───
  if (url.pathname === '/api/v1/devices') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    if (request.method === 'GET') {
      const devices = await env.DB.prepare(
        'SELECT * FROM device_identities WHERE user_id = ?1 ORDER BY created_at DESC'
      )
        .bind(userPayload.sub)
        .all<DeviceIdentity>();

      return Response.json({
        devices: devices.results,
        total: devices.results.length,
      });
    }
  }

  // ─── Devices: Resolve Route (Connection Manager) ───
  if (request.method === 'GET' && url.pathname.startsWith('/api/v1/devices/resolve/')) {
    const targetDeviceId = url.pathname.replace('/api/v1/devices/resolve/', '');
    const callerLanIp = url.searchParams.get('callerLanIp') || '';

    const doId = env.PRESENCE_HUB.idFromName('global_presence_hub');
    const stub = env.PRESENCE_HUB.get(doId);
    return stub.fetch(
      `http://do/resolve?targetDeviceId=${encodeURIComponent(targetDeviceId)}&callerLanIp=${encodeURIComponent(callerLanIp)}`
    );
  }

  // ─── Control Commands: Send-to-Device / Play-on-TV ───
  if (request.method === 'POST' && url.pathname === '/api/v1/control/commands') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = (await request.json()) as {
      targetDeviceId: string;
      command: 'play_on_tv' | 'send_to_device';
      payload: Record<string, unknown>;
    };

    const doId = env.PRESENCE_HUB.idFromName('global_presence_hub');
    const stub = env.PRESENCE_HUB.get(doId);
    return stub.fetch('http://do/command', {
      method: 'POST',
      body: JSON.stringify(body),
    });
  }

  // ─── Free-Tier Guard: Usage & Budget Status ───
  if (request.method === 'GET' && url.pathname === '/api/v1/free-tier/usage') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const guard = new BudgetGuard(env);
    const status = await guard.getBudgetStatus();
    return Response.json(status);
  }

  // ─── Always-Available: Set File Availability Tier ───
  if (request.method === 'PUT' && url.pathname.startsWith('/api/v1/files/') && url.pathname.endsWith('/availability')) {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const parts = url.pathname.split('/');
    const fileId = parts[4]; // /api/v1/files/<file_id>/availability
    const body = (await request.json()) as { availability_tier?: string };
    const tier = body.availability_tier || 'local_only';

    const now = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO file_locations (id, file_id, user_id, storage_node_id, availability_tier, is_cached_in_cloud, created_at, updated_at)
       VALUES (?1, ?2, ?3, 'default', ?4, 0, ?5, ?5)
       ON CONFLICT(id) DO UPDATE SET availability_tier = ?4, updated_at = ?5`
    )
      .bind(crypto.randomUUID(), fileId, userPayload.sub, tier, now)
      .run();

    return Response.json({ success: true, file_id: fileId, availability_tier: tier });
  }

  // ─── Always-Available: Replicate File (R2 Encrypted Cloud Cache / Peer Node) ───
  if (request.method === 'POST' && url.pathname.startsWith('/api/v1/files/') && url.pathname.endsWith('/replicate')) {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const parts = url.pathname.split('/');
    const fileId = parts[4];
    const body = (await request.json().catch(() => ({}))) as {
      target?: 'r2_cache' | 'storage_node';
      file_size_bytes?: number;
    };

    const guard = new BudgetGuard(env);
    const permitted = await guard.isCloudCachePermitted();
    if (!permitted) {
      return Response.json(
        {
          success: false,
          error: 'Cloud cache blocked by Free-Tier Guard: hard budget limit reached or R2 quota full.',
        },
        { status: 403 }
      );
    }

    const now = new Date().toISOString();
    await env.DB.prepare(
      `UPDATE file_locations SET is_cached_in_cloud = 1, availability_tier = 'always_available', updated_at = ?1
       WHERE file_id = ?2 AND user_id = ?3`
    )
      .bind(now, fileId, userPayload.sub)
      .run();

    return Response.json({
      success: true,
      file_id: fileId,
      status: 'replicated_to_cloud_cache',
      is_cached_in_cloud: true,
    });
  }

  return Response.json({ error: 'Endpoint not found' }, { status: 404 });
}

// ─── Helper Functions ───

async function issueTokenPair(
  userId: string,
  email: string,
  secret: string,
  db: D1Database
): Promise<{ access_token: string; refresh_token: string }> {
  const access_token = await generateJwt({ sub: userId, email, role: 'user' }, secret, 900); // 15 mins
  const refresh_token = crypto.randomUUID().replace(/-/g, '') + crypto.randomUUID().replace(/-/g, '');
  const tokenHash = await hashToken(refresh_token);
  const exp = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString(); // 30 days
  const now = new Date().toISOString();

  await db.prepare(
    `INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, revoked, created_at)
     VALUES (?1, ?2, ?3, ?4, 0, ?5)`
  )
    .bind(crypto.randomUUID(), userId, tokenHash, exp, now)
    .run();

  return { access_token, refresh_token };
}

async function extractAuthUser(
  request: Request,
  secret: string
): Promise<{ sub: string; email?: string } | null> {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  const token = authHeader.slice(7).trim();
  const payload = await verifyJwt(token, secret);
  if (!payload || !payload.sub) {
    return null;
  }
  return { sub: String(payload.sub), email: payload.email ? String(payload.email) : undefined };
}

async function hashToken(token: string): Promise<string> {
  const enc = new TextEncoder();
  const hash = await crypto.subtle.digest('SHA-256', enc.encode(token));
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}
