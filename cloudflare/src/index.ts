// PCOS Cloudflare Edge Control Plane
// Free-first, always-available distributed cloud coordinator.
// Splits control plane (coordination/metadata/presence) from data plane (storage/compute/FFmpeg).

import { Env, User, DeviceIdentity, StorageNode, FileLocation, FileEntry } from './types';
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

function getCorsHeaders(request: Request, env?: Env): Record<string, string> {
  const origin = request.headers.get('Origin');
  const baseHeaders: Record<string, string> = {
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With',
  };

  if (!origin) {
    baseHeaders['Access-Control-Allow-Origin'] = '*';
    return baseHeaders;
  }

  let allowed = false;
  try {
    const originUrl = new URL(origin);
    const host = originUrl.hostname;
    if (
      host === 'localhost' ||
      host === '127.0.0.1' ||
      host.endsWith('.pages.dev') ||
      host.endsWith('.workers.dev')
    ) {
      allowed = true;
    }
  } catch (_) {}

  if (env?.ALLOWED_ORIGINS) {
    const list = env.ALLOWED_ORIGINS.split(',').map((o) => o.trim());
    if (list.includes(origin) || list.includes('*')) {
      allowed = true;
    }
  }

  if (allowed) {
    baseHeaders['Access-Control-Allow-Origin'] = origin;
    baseHeaders['Access-Control-Allow-Credentials'] = 'true';
    baseHeaders['Vary'] = 'Origin';
  } else {
    baseHeaders['Access-Control-Allow-Origin'] = origin;
  }

  return baseHeaders;
}

// In-memory rate limiting per Worker isolate (complements Durable Object rate limiting)
const authRateLimiter = new Map<string, { attempts: number; blockedUntil: number }>();

function checkRateLimit(key: string): Response | null {
  const now = Date.now();
  const record = authRateLimiter.get(key);
  if (record && record.blockedUntil > now) {
    const waitSecs = Math.ceil((record.blockedUntil - now) / 1000);
    return Response.json(
      { error: `Too many requests. Please wait ${waitSecs}s before retrying.` },
      { status: 429, headers: { 'Retry-After': String(waitSecs) } }
    );
  }
  return null;
}

function recordFailedAttempt(key: string, maxAttempts = 5, blockDurationMs = 300000): void {
  const now = Date.now();
  const record = authRateLimiter.get(key);
  const count = (record && record.blockedUntil <= now ? record.attempts : 0) + 1;
  if (count >= maxAttempts) {
    authRateLimiter.set(key, { attempts: count, blockedUntil: now + blockDurationMs });
  } else {
    authRateLimiter.set(key, { attempts: count, blockedUntil: 0 });
  }
}

function recordSuccess(key: string): void {
  authRateLimiter.delete(key);
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const corsHeaders = getCorsHeaders(request, env);

    // 1. Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
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
      if (
        url.pathname.startsWith('/api/') ||
        url.pathname === '/health' ||
        url.pathname === '/livez' ||
        url.pathname === '/readyz'
      ) {
        const response = await handleApiRequest(request, env, budget);
        // Add dynamic CORS headers to API responses
        const headers = new Headers(response.headers);
        for (const [k, v] of Object.entries(corsHeaders)) {
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
      console.error('PCOS Edge uncaught error:', err);
      return Response.json(
        { error: 'Internal edge server error' },
        { status: 500, headers: corsHeaders }
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

  // ─── Unauthenticated Health Probes (BEFORE JWT gate) ───
  // These MUST work even when JWT_SECRET is missing to enable diagnostics.

  // /livez — process is reachable (Kubernetes-style liveness)
  if (url.pathname === '/livez') {
    return Response.json({ status: 'alive', timestamp: new Date().toISOString() });
  }

  // /health — basic reachability (legacy compat)
  if (url.pathname === '/health' || url.pathname === '/api/v1/health') {
    return Response.json({
      status: 'healthy',
      version: env.PCOS_CONTROL_VERSION || '1.0.0',
      platform: 'cloudflare_edge',
      uptime_secs: Math.floor(Date.now() / 1000),
    });
  }

  // /readyz — deep dependency check: JWT config + D1 + DO + KV
  if (url.pathname === '/readyz' || url.pathname === '/api/v1/readyz') {
    const checks: Record<string, { status: string; detail?: string }> = {};
    let allReady = true;

    // Check JWT_SECRET configuration
    const hasJwt = !!(env.JWT_SECRET || (env.PCOS_ENV !== 'production'));
    checks['jwt_config'] = hasJwt
      ? { status: 'pass' }
      : { status: 'fail', detail: 'JWT_SECRET secret is not configured. Run: npx wrangler secret put JWT_SECRET' };
    if (!hasJwt) allReady = false;

    // Check D1 Database connectivity
    try {
      const result = await env.DB.prepare("SELECT 1 as ok").first<{ ok: number }>();
      checks['d1_database'] = result?.ok === 1
        ? { status: 'pass' }
        : { status: 'fail', detail: 'D1 query returned unexpected result' };
      if (result?.ok !== 1) allReady = false;
    } catch (e) {
      checks['d1_database'] = { status: 'fail', detail: 'D1 database unreachable' };
      allReady = false;
    }

    // Check D1 schema (users table exists)
    try {
      await env.DB.prepare("SELECT COUNT(*) as c FROM users").first();
      checks['d1_schema'] = { status: 'pass' };
    } catch (e) {
      checks['d1_schema'] = { status: 'fail', detail: 'D1 schema not applied. Run schema migrations.' };
      allReady = false;
    }

    // Check Durable Objects are bindable
    try {
      const doId = env.PAIRING_HUB.idFromName('readyz_probe');
      checks['durable_objects'] = doId ? { status: 'pass' } : { status: 'fail', detail: 'PairingHub DO binding failed' };
      if (!doId) allReady = false;
    } catch (e) {
      checks['durable_objects'] = { status: 'fail', detail: 'Durable Object bindings unavailable' };
      allReady = false;
    }

    // Check KV binding
    try {
      if (env.CONFIG_KV) {
        checks['kv_namespace'] = { status: 'pass' };
      } else {
        checks['kv_namespace'] = { status: 'warn', detail: 'CONFIG_KV not bound (optional)' };
      }
    } catch (e) {
      checks['kv_namespace'] = { status: 'warn', detail: 'KV namespace check failed (optional)' };
    }

    const overallStatus = allReady ? 'ready' : 'not_ready';
    return Response.json(
      {
        status: overallStatus,
        version: env.PCOS_CONTROL_VERSION || '1.0.0',
        checks,
        timestamp: new Date().toISOString(),
      },
      { status: allReady ? 200 : 503 }
    );
  }

  // /api/v1/doctor/connectivity — network diagnostics (unauthenticated)
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

  // ─── JWT_SECRET Gate (fail-closed for all authenticated endpoints) ───
  const effectiveJwtSecret = env.JWT_SECRET || (env.PCOS_ENV === 'production' ? '' : 'pcos_dev_jwt_secret_do_not_use_in_production');
  if (!effectiveJwtSecret) {
    console.error('FATAL: JWT_SECRET environment variable is not configured in production');
    return Response.json(
      { error: 'Server configuration error', code: 'CONFIG_ERROR', message: 'The server is not fully configured. Contact your administrator.' },
      { status: 503 }
    );
  }
  const jwtSecret = effectiveJwtSecret;

  // ─── Free-Tier Usage & Budget Dashboard ───
  if (url.pathname === '/api/v1/usage/budget') {
    const status = await budget.getBudgetStatus();
    return Response.json(status);
  }

  // ─── Auth: Register ───
  if (request.method === 'POST' && url.pathname === '/api/v1/auth/register') {
    const clientIp = request.headers.get('cf-connecting-ip') || '127.0.0.1';
    const rateLimitResp = checkRateLimit(`reg_${clientIp}`);
    if (rateLimitResp) return rateLimitResp;

    const body = (await request.json().catch(() => ({}))) as {
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
      recordSuccess(`reg_${clientIp}`);

      return Response.json({
        user: { id: userId, email: body.email, display_name: body.display_name, cloud_id: cloudId },
        tokens,
      }, { status: 201 });
    } catch (e) {
      if (String(e).includes('UNIQUE')) {
        return Response.json({ error: 'User with this email already exists' }, { status: 409 });
      }
      console.error('Registration failed:', e);
      recordFailedAttempt(`reg_${clientIp}`, 5, 300000);
      return Response.json({ error: 'Registration failed' }, { status: 500 });
    }
  }

  // ─── Auth: Login ───
  if (request.method === 'POST' && url.pathname === '/api/v1/auth/login') {
    const clientIp = request.headers.get('cf-connecting-ip') || '127.0.0.1';
    const rateLimitResp = checkRateLimit(`login_${clientIp}`);
    if (rateLimitResp) return rateLimitResp;

    const body = (await request.json().catch(() => ({}))) as { email?: string; password?: string };
    if (!body.email || !body.password) {
      return Response.json({ error: 'Email and password required' }, { status: 400 });
    }

    const user = await env.DB.prepare('SELECT * FROM users WHERE email = ?1')
      .bind(body.email.toLowerCase().trim())
      .first<User>();

    if (!user || !(await verifyPassword(body.password, user.password_hash))) {
      recordFailedAttempt(`login_${clientIp}`, 5, 300000);
      return Response.json({ error: 'Invalid email or password' }, { status: 401 });
    }

    recordSuccess(`login_${clientIp}`);

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

    // Forward to PairingHub DO with client IP for rate limiting
    const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
    const stub = env.PAIRING_HUB.get(doId);
    const clientIp = request.headers.get('cf-connecting-ip') || '';
    const resp = await stub.fetch('http://do/claim', {
      method: 'POST',
      headers: { 'cf-connecting-ip': clientIp },
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

    const body = (await request.json().catch(() => ({}))) as {
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

    // Approved: Provision the device once
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

    // Update D1 with approved status and redeem result to avoid duplicate device on redeem
    const candidateWithRedeem = {
      ...candidate,
      device_id: deviceId,
      redeem_result: redeemResult,
    };
    await env.DB.prepare("UPDATE pairing_sessions SET status = 'approved', candidate_device_json = ?1 WHERE id = ?2")
      .bind(JSON.stringify(candidateWithRedeem), sessionRow.id)
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
    const body = (await request.json().catch(() => ({}))) as {
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
      .first<{ id: string; user_id: string; status: string; expires_at: string; candidate_device_json?: string }>();

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

    // Check if session was already approved and provisioned
    if (sessionRow.status === 'approved') {
      let candidateData: { redeem_result?: { device: Record<string, unknown>; access_token: string; refresh_token: string } } = {};
      try {
        candidateData = JSON.parse(sessionRow.candidate_device_json || '{}');
      } catch (_) {}

      // Consume session immediately (single-use token)
      await env.DB.prepare('DELETE FROM pairing_sessions WHERE id = ?1').bind(sessionRow.id).run();
      const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
      const stub = env.PAIRING_HUB.get(doId);
      await stub.fetch(`http://do/consume?key=${encodeURIComponent(key)}`, { method: 'POST' });

      if (candidateData.redeem_result) {
        return Response.json(candidateData.redeem_result);
      }
    }

    // Direct single-step headless enrollment (e.g. for CLI without approval requirement)
    await env.DB.prepare('DELETE FROM pairing_sessions WHERE id = ?1').bind(sessionRow.id).run();
    const doId = env.PAIRING_HUB.idFromName('global_pairing_hub');
    const stub = env.PAIRING_HUB.get(doId);
    await stub.fetch(`http://do/consume?key=${encodeURIComponent(key)}`, { method: 'POST' });

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
  if (
    (request.method === 'POST' || request.method === 'PUT') &&
    url.pathname.startsWith('/api/v1/devices/') &&
    url.pathname.endsWith('/heartbeat')
  ) {
    const parts = url.pathname.split('/');
    const deviceId = parts[4]; // /api/v1/devices/<deviceId>/heartbeat
    const body = (await request.json().catch(() => ({}))) as {
      deviceId?: string;
      userId?: string;
      lanIp?: string;
      lan_ip?: string;
      name?: string;
      deviceType?: string;
    };

    const lanIp = body.lanIp || body.lan_ip || null;
    const now = new Date().toISOString();

    // 1. Update D1 device identity
    await env.DB.prepare(
      `UPDATE device_identities
       SET is_online = 1, last_seen_at = ?1, last_lan_ip = COALESCE(?2, last_lan_ip), updated_at = ?1
       WHERE id = ?3`
    )
      .bind(now, lanIp, deviceId)
      .run();

    // 2. Forward to DevicePresenceHub DO
    const doId = env.PRESENCE_HUB.idFromName('global_presence_hub');
    const stub = env.PRESENCE_HUB.get(doId);
    const clientIp = request.headers.get('cf-connecting-ip') || '';

    await stub.fetch('http://do/heartbeat', {
      method: 'POST',
      headers: { 'cf-connecting-ip': clientIp },
      body: JSON.stringify({
        deviceId,
        userId: body.userId,
        name: body.name,
        deviceType: body.deviceType,
        lanIp,
      }),
    });

    return Response.json({
      success: true,
      is_online: true,
      device_id: deviceId,
      last_seen_at: now,
    });
  }

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

    if (request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as {
        name?: string;
        device_type?: string;
        os?: string;
        os_version?: string;
        agent_version?: string;
        public_key?: string;
      };

      if (!body.name) {
        return Response.json({ error: 'Device name is required' }, { status: 400 });
      }

      const cloudRow = await env.DB.prepare('SELECT cloud_id FROM cloud_identities WHERE user_id = ?1')
        .bind(userPayload.sub)
        .first<{ cloud_id: string }>();

      const deviceId = crypto.randomUUID();
      const now = new Date().toISOString();
      const cloudId = cloudRow?.cloud_id || 'pcos';
      const deviceType = body.device_type || 'desktop';
      const osName = body.os || 'unknown';
      const osVersion = body.os_version || '';
      const agentVersion = body.agent_version || '0.1.0';

      await env.DB.prepare(
        `INSERT INTO device_identities (id, user_id, cloud_id, name, device_type, os, os_version, agent_version, public_key, is_online, last_seen_at, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 1, ?10, ?10, ?10)`
      )
        .bind(
          deviceId,
          userPayload.sub,
          cloudId,
          body.name.trim(),
          deviceType,
          osName,
          osVersion,
          agentVersion,
          body.public_key || null,
          now
        )
        .run();

      const createdDevice = {
        id: deviceId,
        user_id: userPayload.sub,
        cloud_id: cloudId,
        name: body.name.trim(),
        device_type: deviceType,
        os: osName,
        os_version: osVersion,
        agent_version: agentVersion,
        is_online: 1,
        last_seen_at: now,
        created_at: now,
        updated_at: now,
      };

      return Response.json(createdDevice, { status: 201 });
    }
  }

  // ─── Devices: Single Device Operations (GET / DELETE) ───
  if (
    url.pathname.match(/^\/api\/v1\/devices\/[0-9a-fA-F-]+$/) &&
    !url.pathname.endsWith('/heartbeat') &&
    !url.pathname.includes('/pair')
  ) {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }
    const deviceId = url.pathname.split('/')[4];

    if (request.method === 'GET') {
      const device = await env.DB.prepare(
        'SELECT * FROM device_identities WHERE id = ?1 AND user_id = ?2'
      )
        .bind(deviceId, userPayload.sub)
        .first<DeviceIdentity>();

      if (!device) {
        return Response.json({ error: 'Device not found' }, { status: 404 });
      }
      return Response.json(device);
    }

    if (request.method === 'DELETE') {
      await env.DB.prepare(
        'DELETE FROM device_identities WHERE id = ?1 AND user_id = ?2'
      )
        .bind(deviceId, userPayload.sub)
        .run();

      return Response.json({ success: true, message: 'Device removed successfully' });
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

  // ─── Version & System Diagnostics ───
  if (url.pathname === '/api/v1/version') {
    return Response.json({
      version: env.PCOS_CONTROL_VERSION || '1.0.0',
      platform: 'cloudflare_edge',
    });
  }

  if (url.pathname === '/api/v1/admin/system') {
    return Response.json({
      status: 'healthy',
      version: env.PCOS_CONTROL_VERSION || '1.0.0',
      platform: 'cloudflare_edge',
      total_storage_bytes: 0,
    });
  }

  // ─── Users: Me Profile ───
  if (url.pathname === '/api/v1/users/me') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });
    const user = await env.DB.prepare(
      'SELECT id, email, display_name, role, quota_bytes, used_bytes, created_at, updated_at FROM users WHERE id = ?1'
    )
      .bind(userPayload.sub)
      .first<User>();
    if (!user) return Response.json({ error: 'User not found' }, { status: 404 });
    return Response.json(user);
  }

  // ─── Auxiliary Stubs (Shares, Notifications, Media History) ───
  if (url.pathname === '/api/v1/shares') {
    return Response.json({ shares: [], total: 0 });
  }

  if (url.pathname === '/api/v1/notifications') {
    return Response.json({ notifications: [], total: 0 });
  }

  if (url.pathname === '/api/v1/media/history') {
    return Response.json({ history: [] });
  }

  // ─── Folders: List Root ───
  if (request.method === 'GET' && url.pathname === '/api/v1/folders') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });

    const rows = await env.DB.prepare(
      `SELECT id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, is_trashed, is_favorite, created_at, updated_at
       FROM file_entries
       WHERE user_id = ?1 AND parent_id IS NULL AND is_trashed = 0
       ORDER BY entry_type DESC, name ASC`
    )
      .bind(userPayload.sub)
      .all<FileEntry>();

    const entries = (rows.results || []).map((e) => ({
      ...e,
      is_trashed: e.is_trashed === 1,
      is_favorite: e.is_favorite === 1,
    }));

    return Response.json({
      total: entries.length,
      entries,
      path: [{ id: null, name: 'Root' }],
    });
  }

  // ─── Folders: List by ID ───
  if (request.method === 'GET' && url.pathname.startsWith('/api/v1/folders/')) {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });

    const folderId = url.pathname.replace('/api/v1/folders/', '');
    const folder = await env.DB.prepare(
      `SELECT * FROM file_entries WHERE id = ?1 AND user_id = ?2 AND is_trashed = 0`
    )
      .bind(folderId, userPayload.sub)
      .first<FileEntry>();

    if (!folder) {
      return Response.json({ error: 'Folder not found' }, { status: 404 });
    }

    const rows = await env.DB.prepare(
      `SELECT id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, is_trashed, is_favorite, created_at, updated_at
       FROM file_entries
       WHERE user_id = ?1 AND parent_id = ?2 AND is_trashed = 0
       ORDER BY entry_type DESC, name ASC`
    )
      .bind(userPayload.sub, folderId)
      .all<FileEntry>();

    const entries = (rows.results || []).map((e) => ({
      ...e,
      is_trashed: e.is_trashed === 1,
      is_favorite: e.is_favorite === 1,
    }));

    return Response.json({
      total: entries.length,
      entries,
      path: [
        { id: null, name: 'Root' },
        { id: folder.id, name: folder.name },
      ],
    });
  }

  // ─── Folders: Create ───
  if (request.method === 'POST' && url.pathname === '/api/v1/folders') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });

    const body = (await request.json().catch(() => ({}))) as { name?: string; parent_id?: string | null };
    if (!body.name || !body.name.trim()) {
      return Response.json({ error: 'Folder name is required' }, { status: 400 });
    }

    const folderId = crypto.randomUUID();
    const now = new Date().toISOString();

    await env.DB.prepare(
      `INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, size_bytes, is_trashed, is_favorite, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, 'folder', 0, 0, 0, ?5, ?5)`
    )
      .bind(folderId, userPayload.sub, body.parent_id || null, body.name.trim(), now)
      .run();

    return Response.json(
      {
        id: folderId,
        parent_id: body.parent_id || null,
        name: body.name.trim(),
        entry_type: 'folder',
        size_bytes: 0,
        is_trashed: false,
        is_favorite: false,
        created_at: now,
        updated_at: now,
      },
      { status: 201 }
    );
  }

  // ─── Files: List Recent Files (Dashboard) ───
  if (request.method === 'GET' && url.pathname === '/api/v1/files') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });

    const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get('limit') || '50', 10)));
    const rows = await env.DB.prepare(
      `SELECT id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, is_trashed, is_favorite, created_at, updated_at
       FROM file_entries
       WHERE user_id = ?1 AND entry_type = 'file' AND is_trashed = 0
       ORDER BY updated_at DESC
       LIMIT ?2`
    )
      .bind(userPayload.sub, limit)
      .all<FileEntry>();

    const entries = (rows.results || []).map((e) => ({
      ...e,
      is_trashed: e.is_trashed === 1,
      is_favorite: e.is_favorite === 1,
    }));

    return Response.json({ total: entries.length, entries });
  }

  // ─── Files: Upload ───
  if (request.method === 'POST' && url.pathname === '/api/v1/files/upload') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });

    try {
      const formData = await request.formData();
      const file = formData.get('file') as File | null;
      const parentId = (formData.get('parent_id') as string) || null;

      if (!file) {
        return Response.json({ error: 'No file provided' }, { status: 400 });
      }

      const fileId = crypto.randomUUID();
      const now = new Date().toISOString();
      const filename = file.name || 'unnamed_file';
      const mimeType = file.type || 'application/octet-stream';
      const sizeBytes = file.size;

      let storagePath = 'local';
      let dataBlob: ArrayBuffer | null = null;

      if (env.CACHE_R2) {
        const permitted = await budget.isCloudCachePermitted();
        if (permitted) {
          const r2Key = `cache/${userPayload.sub}/${fileId}`;
          await env.CACHE_R2.put(r2Key, file.stream(), {
            httpMetadata: { contentType: mimeType },
            customMetadata: { userId: userPayload.sub, fileId, filename },
          });
          await budget.updateR2StorageBytes(sizeBytes);
          storagePath = 'r2';
        }
      }

      if (storagePath !== 'r2') {
        if (sizeBytes <= 2 * 1024 * 1024) {
          dataBlob = await file.arrayBuffer();
          storagePath = 'd1';
        } else {
          storagePath = 'metadata_only';
        }
      }

      await env.DB.prepare(
        `INSERT INTO file_entries (id, user_id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, storage_path, is_trashed, is_favorite, data_blob, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, 'file', ?5, ?6, '', ?7, 0, 0, ?8, ?9, ?9)`
      )
        .bind(fileId, userPayload.sub, parentId, filename, mimeType, sizeBytes, storagePath, dataBlob, now)
        .run();

      return Response.json(
        {
          id: fileId,
          parent_id: parentId,
          name: filename,
          entry_type: 'file',
          mime_type: mimeType,
          size_bytes: sizeBytes,
          storage_path: storagePath,
          is_trashed: false,
          is_favorite: false,
          created_at: now,
          updated_at: now,
        },
        { status: 201 }
      );
    } catch (err) {
      console.error('File upload error:', err);
      return Response.json({ error: 'File upload failed' }, { status: 500 });
    }
  }

  // ─── Files: Download & Preview ───
  if (
    request.method === 'GET' &&
    (url.pathname.match(/^\/api\/v1\/files\/[^/]+\/download$/) ||
      url.pathname.match(/^\/api\/v1\/files\/[^/]+\/preview$/))
  ) {
    const userPayload = await extractAuthUser(request, jwtSecret);
    const fileId = url.pathname.split('/')[4];
    const isPreview = url.pathname.endsWith('/preview');
    const entry = await env.DB.prepare('SELECT * FROM file_entries WHERE id = ?1')
      .bind(fileId)
      .first<FileEntry>();

    if (!entry || (userPayload && entry.user_id !== userPayload.sub)) {
      return Response.json({ error: 'File not found or unauthorized' }, { status: 404 });
    }

    const mime = entry.mime_type || 'application/octet-stream';
    const disposition = isPreview
      ? 'inline'
      : `attachment; filename="${encodeURIComponent(entry.name)}"`;

    if (entry.storage_path === 'r2' && env.CACHE_R2) {
      const obj = await env.CACHE_R2.get(`cache/${entry.user_id}/${entry.id}`);
      if (obj) {
        return new Response(obj.body, {
          headers: {
            'Content-Type': mime,
            'Content-Disposition': disposition,
            'Content-Length': String(entry.size_bytes),
          },
        });
      }
    }

    if (entry.data_blob) {
      return new Response(entry.data_blob, {
        headers: {
          'Content-Type': mime,
          'Content-Disposition': disposition,
          'Content-Length': String(entry.size_bytes),
        },
      });
    }

    return Response.json(
      {
        error: 'File content resides on your connected local PCOS Storage Node.',
        file_id: entry.id,
        name: entry.name,
      },
      { status: 404 }
    );
  }

  // ─── Files: Item Operations (Rename & Delete) ───
  if (url.pathname.match(/^\/api\/v1\/files\/[^/]+$/)) {
    const fileId = url.pathname.split('/')[4];
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });
    const now = new Date().toISOString();

    if (request.method === 'PUT') {
      const body = (await request.json().catch(() => ({}))) as { name?: string };
      if (!body.name) return Response.json({ error: 'Name is required' }, { status: 400 });
      await env.DB.prepare(
        'UPDATE file_entries SET name = ?1, updated_at = ?2 WHERE id = ?3 AND user_id = ?4'
      )
        .bind(body.name.trim(), now, fileId, userPayload.sub)
        .run();
      return Response.json({ success: true, name: body.name.trim() });
    }

    if (request.method === 'DELETE') {
      await env.DB.prepare(
        'UPDATE file_entries SET is_trashed = 1, trashed_at = ?1, updated_at = ?1 WHERE id = ?2 AND user_id = ?3'
      )
        .bind(now, fileId, userPayload.sub)
        .run();
      return Response.json({ success: true, message: 'Item moved to trash' });
    }
  }

  // ─── Files: Favorite ───
  if (request.method === 'PUT' && url.pathname.match(/^\/api\/v1\/files\/[^/]+\/favorite$/)) {
    const fileId = url.pathname.split('/')[4];
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });
    const now = new Date().toISOString();
    await env.DB.prepare(
      'UPDATE file_entries SET is_favorite = (CASE WHEN is_favorite = 1 THEN 0 ELSE 1 END), updated_at = ?1 WHERE id = ?2 AND user_id = ?3'
    )
      .bind(now, fileId, userPayload.sub)
      .run();
    return Response.json({ success: true });
  }

  // ─── Files: Move ───
  if (request.method === 'PUT' && url.pathname.match(/^\/api\/v1\/files\/[^/]+\/move$/)) {
    const fileId = url.pathname.split('/')[4];
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });
    const body = (await request.json().catch(() => ({}))) as { target_folder_id?: string | null };
    const now = new Date().toISOString();
    await env.DB.prepare(
      'UPDATE file_entries SET parent_id = ?1, updated_at = ?2 WHERE id = ?3 AND user_id = ?4'
    )
      .bind(body.target_folder_id || null, now, fileId, userPayload.sub)
      .run();
    return Response.json({ success: true });
  }

  // ─── Files: Bulk Delete ───
  if (request.method === 'POST' && url.pathname === '/api/v1/files/bulk-delete') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });
    const body = (await request.json().catch(() => ({}))) as { ids?: string[] };
    const now = new Date().toISOString();
    if (body.ids && body.ids.length > 0) {
      for (const id of body.ids) {
        await env.DB.prepare(
          'UPDATE file_entries SET is_trashed = 1, trashed_at = ?1, updated_at = ?1 WHERE id = ?2 AND user_id = ?3'
        )
          .bind(now, id, userPayload.sub)
          .run();
      }
    }
    return Response.json({ success: true });
  }

  // ─── Trash: List ───
  if (url.pathname === '/api/v1/trash' && request.method === 'GET') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });
    const rows = await env.DB.prepare(
      `SELECT id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, is_trashed, is_favorite, created_at, updated_at, trashed_at
       FROM file_entries WHERE user_id = ?1 AND is_trashed = 1 ORDER BY trashed_at DESC`
    )
      .bind(userPayload.sub)
      .all<FileEntry>();
    return Response.json(rows.results || []);
  }

  // ─── Trash: Restore ───
  if (url.pathname.match(/^\/api\/v1\/trash\/[^/]+\/restore$/) && request.method === 'POST') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });
    const itemId = url.pathname.split('/')[4];
    const now = new Date().toISOString();
    await env.DB.prepare(
      'UPDATE file_entries SET is_trashed = 0, trashed_at = NULL, updated_at = ?1 WHERE id = ?2 AND user_id = ?3'
    )
      .bind(now, itemId, userPayload.sub)
      .run();
    return Response.json({ success: true });
  }

  // ─── Trash: Empty ───
  if (url.pathname === '/api/v1/trash/empty' && request.method === 'POST') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });
    await env.DB.prepare('DELETE FROM file_entries WHERE user_id = ?1 AND is_trashed = 1')
      .bind(userPayload.sub)
      .run();
    return Response.json({ success: true });
  }

  // ─── Search: Files & Photos (Used by Gallery & Search) ───
  if (request.method === 'GET' && url.pathname === '/api/v1/search') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });

    const q = url.searchParams.get('q') || '*';
    const type = url.searchParams.get('type');
    const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get('limit') || '50', 10)));

    let querySql = `SELECT id, parent_id, name, entry_type, mime_type, size_bytes, sha256_hash, is_trashed, is_favorite, created_at, updated_at
                    FROM file_entries WHERE user_id = ?1 AND is_trashed = 0`;
    const binds: (string | number)[] = [userPayload.sub];

    if (type === 'file') {
      querySql += ` AND entry_type = 'file'`;
    } else if (type === 'folder') {
      querySql += ` AND entry_type = 'folder'`;
    }

    if (q && q !== '*') {
      querySql += ` AND name LIKE ?2`;
      binds.push(`%${q}%`);
    }

    querySql += ` ORDER BY updated_at DESC LIMIT ?${binds.length + 1}`;
    binds.push(limit);

    const stmt = env.DB.prepare(querySql);
    const rows = await stmt.bind(...binds).all<FileEntry>();

    const results = (rows.results || []).map((e) => ({
      ...e,
      is_trashed: e.is_trashed === 1,
      is_favorite: e.is_favorite === 1,
    }));

    return Response.json({
      results,
      total: results.length,
      query: q,
    });
  }

  // ─── Storage: Nodes Management ───
  if (url.pathname === '/api/v1/storage/nodes') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    if (request.method === 'GET') {
      const rows = await env.DB.prepare(
        'SELECT * FROM storage_nodes WHERE user_id = ?1 ORDER BY created_at DESC'
      )
        .bind(userPayload.sub)
        .all();

      return Response.json({
        storage_nodes: rows.results || [],
        total: (rows.results || []).length,
      });
    }

    if (request.method === 'POST') {
      const body = (await request.json().catch(() => ({}))) as {
        id?: string;
        device_id?: string;
        name?: string;
        storage_path?: string;
        total_capacity_bytes?: number;
        available_capacity_bytes?: number;
        capabilities_json?: string;
      };

      if (!body.device_id || !body.storage_path) {
        return Response.json(
          { error: 'device_id and storage_path are required' },
          { status: 400 }
        );
      }

      // Verify device belongs to user
      const device = await env.DB.prepare(
        'SELECT id, name FROM device_identities WHERE id = ?1 AND user_id = ?2'
      )
        .bind(body.device_id, userPayload.sub)
        .first();

      if (!device) {
        return Response.json(
          { error: 'Referenced device not found or does not belong to user' },
          { status: 404 }
        );
      }

      const nodeId = body.id || crypto.randomUUID();
      const nodeName = body.name || `${device.name} Storage`;
      const now = new Date().toISOString();
      const caps = body.capabilities_json || '{"ffmpeg":false,"ocr":false,"tantivy":false,"ollama":false}';
      const totalBytes = body.total_capacity_bytes || 0;
      const availBytes = body.available_capacity_bytes || 0;

      await env.DB.prepare(
        `INSERT INTO storage_nodes (id, device_id, user_id, name, storage_path, total_capacity_bytes, available_capacity_bytes, is_online, capabilities_json, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 1, ?8, ?9, ?9)
         ON CONFLICT(id) DO UPDATE SET
           storage_path = ?5,
           total_capacity_bytes = ?6,
           available_capacity_bytes = ?7,
           is_online = 1,
           capabilities_json = ?8,
           updated_at = ?9`
      )
        .bind(
          nodeId,
          body.device_id,
          userPayload.sub,
          nodeName,
          body.storage_path,
          totalBytes,
          availBytes,
          caps,
          now
        )
        .run();

      return Response.json(
        {
          id: nodeId,
          device_id: body.device_id,
          user_id: userPayload.sub,
          name: nodeName,
          storage_path: body.storage_path,
          total_capacity_bytes: totalBytes,
          available_capacity_bytes: availBytes,
          is_online: 1,
          capabilities_json: caps,
          created_at: now,
          updated_at: now,
        },
        { status: 201 }
      );
    }
  }

  if (url.pathname.startsWith('/api/v1/storage/nodes/')) {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const nodeId = url.pathname.replace('/api/v1/storage/nodes/', '');

    if (request.method === 'DELETE') {
      await env.DB.prepare('DELETE FROM storage_nodes WHERE id = ?1 AND user_id = ?2')
        .bind(nodeId, userPayload.sub)
        .run();

      return Response.json({ success: true, message: 'Storage node deleted' });
    }
  }

  // ─── Storage: Statistics ───
  if (request.method === 'GET' && url.pathname === '/api/v1/storage/stats') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });

    const filesCount = await env.DB.prepare(
      `SELECT COUNT(*) as count FROM file_entries WHERE user_id = ?1 AND entry_type = 'file' AND is_trashed = 0`
    )
      .bind(userPayload.sub)
      .first<{ count: number }>();

    const foldersCount = await env.DB.prepare(
      `SELECT COUNT(*) as count FROM file_entries WHERE user_id = ?1 AND entry_type = 'folder' AND is_trashed = 0`
    )
      .bind(userPayload.sub)
      .first<{ count: number }>();

    const sizeSum = await env.DB.prepare(
      `SELECT SUM(size_bytes) as total_bytes FROM file_entries WHERE user_id = ?1 AND entry_type = 'file' AND is_trashed = 0`
    )
      .bind(userPayload.sub)
      .first<{ total_bytes: number }>();

    const trashedCount = await env.DB.prepare(
      `SELECT COUNT(*) as count FROM file_entries WHERE user_id = ?1 AND is_trashed = 1`
    )
      .bind(userPayload.sub)
      .first<{ count: number }>();

    return Response.json({
      total_files: filesCount?.count || 0,
      total_folders: foldersCount?.count || 0,
      total_size_bytes: sizeSum?.total_bytes || 0,
      trashed_items: trashedCount?.count || 0,
    });
  }

  // ─── Analytics: Overview (Dashboard) ───
  if (request.method === 'GET' && url.pathname === '/api/v1/analytics/overview') {
    const userPayload = await extractAuthUser(request, jwtSecret);
    if (!userPayload) return Response.json({ error: 'Unauthorized' }, { status: 401 });

    const filesCount = await env.DB.prepare(
      `SELECT COUNT(*) as count FROM file_entries WHERE user_id = ?1 AND entry_type = 'file' AND is_trashed = 0`
    )
      .bind(userPayload.sub)
      .first<{ count: number }>();

    const foldersCount = await env.DB.prepare(
      `SELECT COUNT(*) as count FROM file_entries WHERE user_id = ?1 AND entry_type = 'folder' AND is_trashed = 0`
    )
      .bind(userPayload.sub)
      .first<{ count: number }>();

    const sizeSum = await env.DB.prepare(
      `SELECT SUM(size_bytes) as total_bytes FROM file_entries WHERE user_id = ?1 AND entry_type = 'file' AND is_trashed = 0`
    )
      .bind(userPayload.sub)
      .first<{ total_bytes: number }>();

    const devCount = await env.DB.prepare(
      `SELECT COUNT(*) as count FROM device_identities WHERE user_id = ?1`
    )
      .bind(userPayload.sub)
      .first<{ count: number }>();

    const bytes = sizeSum?.total_bytes || 0;

    return Response.json({
      total_files: filesCount?.count || 0,
      total_folders: foldersCount?.count || 0,
      total_size_bytes: bytes,
      total_devices: devCount?.count || 0,
      active_shares: 0,
      total_backups: 0,
      formatted_size: formatBytes(bytes),
    });
  }

  return Response.json({ error: 'Endpoint not found' }, { status: 404 });
}

// ─── Helper Functions ───


function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}


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
