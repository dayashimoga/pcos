// PairingHub Durable Object
// Coordinates live Web and Mobile pairing sessions, WebSockets, rate limiting, and approval handshake.

import { PairingSessionData } from '../types';

export class PairingHub implements DurableObject {
  private state: DurableObjectState;
  private sessions: Map<string, PairingSessionData> = new Map();
  private codeToId: Map<string, string> = new Map();
  private tokenToId: Map<string, string> = new Map();
  private websockets: Map<string, Set<WebSocket>> = new Map(); // sessionId -> WebSockets
  private ipAttempts: Map<string, { count: number; blockedUntil: number }> = new Map();

  constructor(state: DurableObjectState) {
    this.state = state;
    this.state.blockConcurrencyWhile(async () => {
      const stored = await this.state.storage.get<Map<string, PairingSessionData>>('sessions');
      if (stored) {
        for (const [id, sess] of stored) {
          if (new Date(sess.expires_at) > new Date()) {
            this.sessions.set(id, sess);
            this.codeToId.set(sess.pairing_code, id);
            this.tokenToId.set(sess.enrollment_token, id);
          }
        }
      }
    });
  }

  private async persist(): Promise<void> {
    await this.state.storage.put('sessions', this.sessions);
  }

  private cleanupExpired(): void {
    const now = new Date();
    for (const [id, sess] of this.sessions) {
      if (new Date(sess.expires_at) <= now) {
        this.codeToId.delete(sess.pairing_code);
        this.tokenToId.delete(sess.enrollment_token);
        this.sessions.delete(id);
      }
    }
  }

  private broadcast(sessionId: string, message: Record<string, unknown>): void {
    const sockets = this.websockets.get(sessionId);
    if (!sockets) return;
    const str = JSON.stringify(message);
    for (const ws of sockets) {
      try {
        ws.send(str);
      } catch (_) {
        sockets.delete(ws);
      }
    }
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    this.cleanupExpired();

    // WebSocket upgrade
    if (request.headers.get('Upgrade')?.toLowerCase() === 'websocket') {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();

      const sessionId = url.searchParams.get('sessionId') || '';
      if (!this.websockets.has(sessionId)) {
        this.websockets.set(sessionId, new Set());
      }
      this.websockets.get(sessionId)!.add(server);

      server.addEventListener('close', () => {
        this.websockets.get(sessionId)?.delete(server);
      });

      return new Response(null, { status: 101, webSocket: client });
    }

    if (request.method === 'POST' && url.pathname === '/create') {
      const body = (await request.json()) as {
        id: string;
        userId: string;
        pairingCode: string;
        enrollmentToken: string;
        expiresAt: string;
      };

      const session: PairingSessionData = {
        id: body.id,
        user_id: body.userId,
        pairing_code: body.pairingCode,
        enrollment_token: body.enrollmentToken,
        status: 'pending_redeem',
        failed_attempts: 0,
        expires_at: body.expiresAt,
        created_at: new Date().toISOString(),
      };

      this.sessions.set(session.id, session);
      this.codeToId.set(session.pairing_code, session.id);
      this.tokenToId.set(session.enrollment_token, session.id);
      await this.persist();

      return Response.json(session);
    }

    if (request.method === 'POST' && url.pathname === '/claim') {
      const clientIp = request.headers.get('cf-connecting-ip') || request.headers.get('x-forwarded-for') || '127.0.0.1';
      const now = Date.now();
      const ipRecord = this.ipAttempts.get(clientIp);

      if (ipRecord && ipRecord.blockedUntil > now) {
        const retryAfter = Math.ceil((ipRecord.blockedUntil - now) / 1000);
        return Response.json(
          { error: `Too many failed pairing attempts. Please wait ${retryAfter}s before retrying.` },
          { status: 429, headers: { 'Retry-After': String(retryAfter) } }
        );
      }

      const body = (await request.json()) as {
        key: string;
        candidate: NonNullable<PairingSessionData['candidate_device']>;
      };

      const id = this.codeToId.get(body.key) || this.tokenToId.get(body.key);
      if (!id || !this.sessions.has(id)) {
        const count = ((ipRecord && ipRecord.blockedUntil <= now) ? ipRecord.count : 0) + 1;
        if (count >= 5) {
          this.ipAttempts.set(clientIp, { count, blockedUntil: now + 300000 }); // 5 min block
          return Response.json(
            { error: 'Too many invalid pairing attempts. Pairing temporarily blocked for 5 minutes.' },
            { status: 429, headers: { 'Retry-After': '300' } }
          );
        } else {
          this.ipAttempts.set(clientIp, { count, blockedUntil: 0 });
        }
        return Response.json({ error: 'Invalid or expired pairing code' }, { status: 401 });
      }

      // Valid key: clear failed IP attempts
      this.ipAttempts.delete(clientIp);

      const session = this.sessions.get(id)!;
      if (new Date(session.expires_at) <= new Date()) {
        return Response.json({ error: 'Pairing session has expired' }, { status: 401 });
      }

      if (session.failed_attempts >= 5) {
        this.sessions.delete(id);
        this.codeToId.delete(session.pairing_code);
        this.tokenToId.delete(session.enrollment_token);
        await this.persist();
        return Response.json(
          { error: 'Too many failed attempts. Pairing session invalidated.' },
          { status: 401 }
        );
      }

      session.candidate_device = body.candidate;
      session.status = 'pending_approval';
      await this.persist();

      // Notify connected Web client that a device wants to connect
      this.broadcast(session.id, {
        event: 'pending_approval',
        session,
      });

      return Response.json(session);
    }

    if (request.method === 'POST' && url.pathname === '/approve') {
      const body = (await request.json()) as {
        key: string;
        userId: string;
        approved: boolean;
        redeemResult?: unknown;
      };

      const id = this.codeToId.get(body.key) || this.tokenToId.get(body.key);
      if (!id || !this.sessions.has(id)) {
        return Response.json({ error: 'Invalid or expired pairing code' }, { status: 401 });
      }

      const session = this.sessions.get(id)!;
      if (session.user_id !== body.userId) {
        return Response.json({ error: 'Unauthorized to approve this session' }, { status: 403 });
      }

      if (!body.approved) {
        session.status = 'rejected';
        await this.persist();
        this.broadcast(session.id, { event: 'rejected', session });
        return Response.json(session);
      }

      session.status = 'approved';
      session.redeem_result = body.redeemResult;
      await this.persist();

      // Broadcast approved event with tokens to mobile device
      this.broadcast(session.id, {
        event: 'approved',
        session,
        redeemResult: body.redeemResult,
      });

      return Response.json(session);
    }

    if (request.method === 'GET' && url.pathname === '/status') {
      const key = url.searchParams.get('key') || '';
      const id = this.codeToId.get(key) || this.tokenToId.get(key);
      if (!id || !this.sessions.has(id)) {
        return Response.json({ error: 'Session not found' }, { status: 404 });
      }

      const session = this.sessions.get(id)!;
      return Response.json(session);
    }

    if (request.method === 'POST' && url.pathname === '/consume') {
      const key = url.searchParams.get('key') || '';
      const id = this.codeToId.get(key) || this.tokenToId.get(key);
      if (id && this.sessions.has(id)) {
        const sess = this.sessions.get(id)!;
        this.sessions.delete(id);
        this.codeToId.delete(sess.pairing_code);
        this.tokenToId.delete(sess.enrollment_token);
        await this.persist();
      }
      return Response.json({ success: true });
    }

    return new Response('Not Found', { status: 404 });
  }
}
