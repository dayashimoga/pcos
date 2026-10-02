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
