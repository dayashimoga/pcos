import { describe, it, expect } from 'vitest';
import worker, { Env, ExecutionContext } from '../src/index';
import { generateJwt, hashPassword } from '../src/services/auth';
import { generateBip39Mnemonic, validateBip39Mnemonic, BIP39_WORDS } from '../src/services/bip39';

describe('PHASE P0: Deep Security & Vulnerability Remediation Suite', () => {
  const jwtSecret = 'phase0_security_deep_audit_secret_key_888888';

  const ctx = {
    waitUntil: () => {},
    passThroughOnException: () => {},
  } as unknown as ExecutionContext;

  describe('1. Standards-Compliant BIP-39 (RFC 2898 / BIP-39)', () => {
    it('should have exactly 2048 words in official dictionary from abandon to zoo', () => {
      expect(BIP39_WORDS.length).toBe(2048);
      expect(BIP39_WORDS[0]).toBe('abandon');
      expect(BIP39_WORDS[2047]).toBe('zoo');
    });

    it('should generate valid 12-word mnemonics with correct 4-bit checksum', async () => {
      for (let i = 0; i < 10; i++) {
        const phrase = await generateBip39Mnemonic();
        const words = phrase.split(' ');
        expect(words.length).toBe(12);
        for (const w of words) {
          expect(BIP39_WORDS).toContain(w);
        }
        const val = await validateBip39Mnemonic(phrase);
        expect(val.valid).toBe(true);
      }
    });

    it('should detect and reject tampered words and invalid checksums', async () => {
      const phrase = await generateBip39Mnemonic();
      const words = phrase.split(' ');
      // Tamper with the 12th word
      words[11] = words[11] === 'abandon' ? 'zoo' : 'abandon';
      const tampered = words.join(' ');
      const val = await validateBip39Mnemonic(tampered);
      expect(val.valid).toBe(false);
      expect(val.error).toContain('checksum verification failed');
    });

    it('should reject phrases with unknown words or incorrect word count', async () => {
      const shortPhrase = 'abandon ability able';
      const val1 = await validateBip39Mnemonic(shortPhrase);
      expect(val1.valid).toBe(false);
      expect(val1.error).toContain('exactly 12 words');

      const unknownWordPhrase = 'abandon ability able about above absent absorb abstract absurd abuse access notabipword';
      const val2 = await validateBip39Mnemonic(unknownWordPhrase);
      expect(val2.valid).toBe(false);
      expect(val2.error).toContain('not in the official BIP-39 dictionary');
    });
  });

  describe('2. Family Cloud Multi-Tenant Isolation & RBAC', () => {
    it('should reject non-member querying family members with 403 Forbidden', async () => {
      const attackerToken = await generateJwt({ sub: 'usr_attacker', email: 'attacker@evil.com' }, jwtSecret, 3600);

      const mockDb = {
        prepare: (query: string) => ({
          bind: (...args: any[]) => ({
            first: async () => {
              if (query.includes('FROM family_members WHERE cloud_id = ?1 AND user_id = ?2')) {
                // Attacker is NOT a member
                return null;
              }
              return null;
            },
            all: async () => ({ results: [] }),
            run: async () => ({ success: true }),
          }),
        }),
      };

      const env = { JWT_SECRET: jwtSecret, DB: mockDb } as unknown as Env;

      const req = new Request('http://localhost/api/v1/family/members?cloud_id=cld_victim_cloud', {
        headers: { Authorization: `Bearer ${attackerToken}` },
      });

      const res = await worker.fetch(req, env, ctx);
      expect(res.status).toBe(403);
      const data = await res.json() as any;
      expect(data.error).toContain('not a member of this family cloud');
    });

    it('should reject non-admin/non-owner from inviting members with 403 Forbidden', async () => {
      const memberToken = await generateJwt({ sub: 'usr_regular_member', email: 'member@family.com' }, jwtSecret, 3600);

      const mockDb = {
        prepare: (query: string) => ({
          bind: (...args: any[]) => ({
            first: async () => {
              if (query.includes('SELECT role FROM family_members WHERE cloud_id = ?1 AND user_id = ?2')) {
                return { role: 'member' }; // Only a regular member, not owner/admin
              }
              return null;
            },
            run: async () => ({ success: true }),
          }),
        }),
      };

      const env = { JWT_SECRET: jwtSecret, DB: mockDb } as unknown as Env;

      const req = new Request('http://localhost/api/v1/family/members/invite', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${memberToken}`,
        },
        body: JSON.stringify({
          cloud_id: 'cld_123',
          user_id: 'usr_new',
          role: 'admin',
        }),
      });

      const res = await worker.fetch(req, env, ctx);
      expect(res.status).toBe(403);
      const data = await res.json() as any;
      expect(data.error).toContain('Only family cloud owners or administrators can invite members');
    });

    it('should reject non-owner modifying member roles with 403 Forbidden', async () => {
      const adminToken = await generateJwt({ sub: 'usr_admin', email: 'admin@family.com' }, jwtSecret, 3600);

      const mockDb = {
        prepare: (query: string) => ({
          bind: (...args: any[]) => ({
            first: async () => {
              if (query.includes('FROM family_members WHERE id = ?1')) {
                return { id: 'fmem_target', cloud_id: 'cld_123', user_id: 'usr_target', role: 'member' };
              }
              if (query.includes('FROM family_members WHERE cloud_id = ?1 AND user_id = ?2')) {
                return { role: 'admin' }; // Admin cannot change roles (only owner can)
              }
              return null;
            },
            run: async () => ({ success: true }),
          }),
        }),
      };

      const env = { JWT_SECRET: jwtSecret, DB: mockDb } as unknown as Env;

      const req = new Request('http://localhost/api/v1/family/members/fmem_target/role', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${adminToken}`,
        },
        body: JSON.stringify({ role: 'owner' }),
      });

      const res = await worker.fetch(req, env, ctx);
      expect(res.status).toBe(403);
      const data = await res.json() as any;
      expect(data.error).toContain('Only the family cloud owner can modify member roles');
    });
  });

  describe('3. Public File Request Upload Password Enforcement', () => {
    it('should reject upload to password-protected drop folder without password with 401', async () => {
      const sharePasswordHash = await hashPassword('DropSecretPass123!');

      const mockDb = {
        prepare: (query: string) => ({
          bind: (...args: any[]) => ({
            first: async () => {
              if (query.includes('FROM shares WHERE share_token = ?1')) {
                return {
                  id: 'share_drop_1',
                  user_id: 'usr_owner',
                  is_upload_request: 1,
                  password_hash: sharePasswordHash,
                  expires_at: null,
                };
              }
              return null;
            },
            run: async () => ({ success: true }),
          }),
        }),
      };

      const env = { JWT_SECRET: jwtSecret, DB: mockDb } as unknown as Env;

      const formData = new FormData();
      formData.append('file', new File(['hello content'], 'test.txt', { type: 'text/plain' }));

      // No password provided
      const req = new Request('http://localhost/api/v1/shares/public/drop_token_123/upload', {
        method: 'POST',
        body: formData,
      });

      const res = await worker.fetch(req, env, ctx);
      expect(res.status).toBe(401);
      const data = await res.json() as any;
      expect(data.code).toBe('PASSWORD_REQUIRED');
    });

    it('should accept upload to password-protected drop folder with valid password', async () => {
      const sharePasswordHash = await hashPassword('DropSecretPass123!');

      const mockDb = {
        prepare: (query: string) => ({
          bind: (...args: any[]) => ({
            first: async () => {
              if (query.includes('FROM shares WHERE share_token = ?1')) {
                return {
                  id: 'share_drop_1',
                  user_id: 'usr_owner',
                  file_id: 'folder_target_1',
                  is_upload_request: 1,
                  password_hash: sharePasswordHash,
                  expires_at: null,
                };
              }
              return null;
            },
            run: async () => ({ success: true }),
          }),
        }),
      };

      const env = { JWT_SECRET: jwtSecret, DB: mockDb } as unknown as Env;

      const formData = new FormData();
      formData.append('file', new File(['hello safe content'], 'safe.txt', { type: 'text/plain' }));

      // Correct password via X-Share-Password header
      const req = new Request('http://localhost/api/v1/shares/public/drop_token_123/upload', {
        method: 'POST',
        headers: { 'X-Share-Password': 'DropSecretPass123!' },
        body: formData,
      });

      const res = await worker.fetch(req, env, ctx);
      expect(res.status).toBe(201);
      const data = await res.json() as any;
      expect(data.success).toBe(true);
      expect(data.name).toBe('safe.txt');
    });
  });

  describe('4. URL Query Parameter Token Leakage Elimination', () => {
    it('should reject sensitive control endpoints when token is passed only in query param', async () => {
      const token = await generateJwt({ sub: 'usr_admin', email: 'admin@pcos.dev' }, jwtSecret, 3600);

      const mockDb = {
        prepare: () => ({
          bind: () => ({
            first: async () => null,
            all: async () => ({ results: [] }),
            run: async () => ({ success: true }),
          }),
        }),
      };

      const env = { JWT_SECRET: jwtSecret, DB: mockDb } as unknown as Env;

      // Attempting to query family clouds via URL query param
      const req = new Request(`http://localhost/api/v1/family/clouds?token=${token}`);
      const res = await worker.fetch(req, env, ctx);
      expect(res.status).toBe(401);

      // Attempting to access cluster status via URL query param
      const clusterReq = new Request(`http://localhost/api/v1/cluster/status?token=${token}`);
      const clusterRes = await worker.fetch(clusterReq, env, ctx);
      expect(clusterRes.status).toBe(401);
    });
  });
});
