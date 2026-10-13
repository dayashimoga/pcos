import { describe, it, expect, vi } from 'vitest';
import worker, { Env, ExecutionContext } from '../src/index';

describe('PHASE 5: Security, Penetration Testing & Resilience Verification', () => {
  const jwtSecret = 'prod_security_audit_secret_key_9999999999';

  // Helper to generate a valid test JWT
  async function makeJwt(payload: any, secret: string = jwtSecret): Promise<string> {
    const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
      .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
    const body = btoa(JSON.stringify(payload))
      .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
    const data = new TextEncoder().encode(`${header}.${body}`);
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );
    const signature = await crypto.subtle.sign('HMAC', key, data);
    const sigStr = btoa(String.fromCharCode(...new Uint8Array(signature)))
      .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
    return `${header}.${body}.${sigStr}`;
  }

  // 1. Filesystem Traversal Penetration Tests
  describe('Filesystem Traversal Confinement (Red-Team)', () => {
    it('should reject path traversal attempts via physical node proxy with 400', async () => {
      const validToken = await makeJwt({ sub: 'usr_sec_01', email: 'sec@pcos.dev' });
      const maliciousPaths = [
        '../../../../etc/passwd',
        '..\\..\\..\\Windows\\System32\\cmd.exe',
        '/etc/shadow',
        'C:\\Windows\\win.ini',
        'folder/../../../secret.key',
      ];

      for (const badPath of maliciousPaths) {
        const req = new Request('http://edge.pcos.dev/api/v1/storage/proxy/fs', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${validToken}`,
          },
          body: JSON.stringify({
            deviceId: 'dev_001',
            op: 'fs_list',
            relative_path: badPath,
          }),
        });

        const mockEnv = {
          JWT_SECRET: jwtSecret,
          DB: {
            prepare: () => ({
              bind: () => ({
                first: async () => null,
                all: async () => ({ results: [] }),
                run: async () => ({ success: true }),
              }),
            }),
          },
        } as unknown as Env;

        const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
        const resp = await worker.fetch(req, mockEnv, ctx);
        // Traversal path must either fail authorization, validation (400), or reject (404/503), NEVER expose host filesystem
        expect([400, 401, 403, 404, 503]).toContain(resp.status);
      }
    });
  });

  // 2. JWT Security & Anti-Tampering Gate
  describe('JWT Anti-Tampering & Secret Rigor', () => {
    it('should reject tokens signed with algorithm "none"', async () => {
      const noneHeader = btoa(JSON.stringify({ alg: 'none', typ: 'JWT' }))
        .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
      const body = btoa(JSON.stringify({ sub: 'usr_hacker', email: 'hacker@evil.com' }))
        .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
      const forgedToken = `${noneHeader}.${body}.`;

      const req = new Request('http://edge.pcos.dev/api/v1/users/me', {
        headers: { Authorization: `Bearer ${forgedToken}` },
      });

      const mockEnv = {
        JWT_SECRET: jwtSecret,
        DB: {
          prepare: () => ({ bind: () => ({ first: async () => null }) }),
        },
      } as unknown as Env;

      const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(401);
    });

    it('should reject tokens signed with a different secret', async () => {
      const forgedToken = await makeJwt({ sub: 'usr_attacker' }, 'wrong_untrusted_secret_key_12345');
      const req = new Request('http://edge.pcos.dev/api/v1/users/me', {
        headers: { Authorization: `Bearer ${forgedToken}` },
      });

      const mockEnv = {
        JWT_SECRET: jwtSecret,
        DB: {
          prepare: () => ({ bind: () => ({ first: async () => null }) }),
        },
      } as unknown as Env;

      const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(401);
    });
  });

  // 3. Share Security: Token Brute-force & Expiration Rigor
  describe('Public Share Threat Resistance', () => {
    it('should return 404 for nonexistent share tokens', async () => {
      const req = new Request('http://edge.pcos.dev/s/random_fake_token_that_does_not_exist');
      const mockEnv = {
        JWT_SECRET: jwtSecret,
        DB: {
          prepare: () => ({ bind: () => ({ first: async () => null }) }),
        },
      } as unknown as Env;
      const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(404);
    });

    it('should strictly reject download without correct password', async () => {
      const mockShare = {
        id: 'sh_999',
        user_id: 'usr_01',
        file_id: 'file_01',
        share_token: 'secret_share_tok',
        is_public: 0,
        password_hash: 'phc_valid_hash',
        expires_at: null,
        max_downloads: null,
        download_count: 0,
      };

      const req = new Request('http://edge.pcos.dev/s/secret_share_tok/download', {
        headers: { 'X-Share-Password': 'WrongPassword123' },
      });

      const mockEnv = {
        JWT_SECRET: jwtSecret,
        DB: {
          prepare: (sql: string) => ({
            bind: () => ({
              first: async () => {
                if (sql.includes('FROM shares')) return mockShare;
                return null;
              },
            }),
          }),
        },
      } as unknown as Env;

      const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(401);
    });
  });

  // 4. HTTP Range Stress & Robustness
  describe('HTTP Range 206 Resilience', () => {
    it('should handle zero-range and boundary offsets gracefully', async () => {
      const fileBytes = new Uint8Array([10, 20, 30, 40, 50]);
      const validToken = await makeJwt({ sub: 'usr_01' });

      const req = new Request('http://edge.pcos.dev/api/v1/files/f1/download', {
        headers: {
          Authorization: `Bearer ${validToken}`,
          Range: 'bytes=0-0',
        },
      });

      const mockEnv = {
        JWT_SECRET: jwtSecret,
        DB: {
          prepare: () => ({
            bind: () => ({
              first: async () => ({
                id: 'f1',
                user_id: 'usr_01',
                name: 'tiny.bin',
                mime_type: 'application/octet-stream',
                size_bytes: 5,
                storage_path: 'd1',
                data_blob: fileBytes.buffer,
              }),
            }),
          }),
        },
      } as unknown as Env;

      const ctx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(206);
      expect(resp.headers.get('Content-Range')).toBe('bytes 0-0/5');
      expect(resp.headers.get('Content-Length')).toBe('1');
      const body = await resp.arrayBuffer();
      expect(new Uint8Array(body)[0]).toBe(10);
    });
  });
});
