// PCOS Zero-Cost / Free-Tier Guard
// Tracks daily/monthly provider consumption and enforces hard budget limits to prevent accidental cloud bills.

import { Env, BudgetStatus, FreeTierUsage } from '../types';

export class BudgetGuard {
  private env: Env;

  constructor(env: Env) {
    this.env = env;
  }

  private getDateKey(): string {
    return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  }

  async trackRequest(type: 'worker' | 'd1_read' | 'd1_write' | 'do'): Promise<void> {
    const dateKey = this.getDateKey();
    const now = new Date().toISOString();

    const columnMap = {
      worker: 'worker_requests = worker_requests + 1',
      d1_read: 'd1_reads = d1_reads + 1',
      d1_write: 'd1_writes = d1_writes + 1',
      do: 'do_requests = do_requests + 1',
    };

    try {
      await this.env.DB.prepare(
        `INSERT INTO free_tier_usage (date_key, worker_requests, d1_reads, d1_writes, do_requests, r2_storage_bytes, updated_at)
         VALUES (?1, 0, 0, 0, 0, 0, ?2)
         ON CONFLICT(date_key) DO UPDATE SET ${columnMap[type]}, updated_at = ?2`
      )
        .bind(dateKey, now)
        .run();
    } catch {
      // In-flight tracking failures must never break user data requests
    }
  }

  async updateR2StorageBytes(totalBytes: number): Promise<void> {
    const dateKey = this.getDateKey();
    const now = new Date().toISOString();

    try {
      await this.env.DB.prepare(
        `INSERT INTO free_tier_usage (date_key, worker_requests, d1_reads, d1_writes, do_requests, r2_storage_bytes, updated_at)
         VALUES (?1, 0, 0, 0, 0, ?2, ?3)
         ON CONFLICT(date_key) DO UPDATE SET r2_storage_bytes = ?2, updated_at = ?3`
      )
        .bind(dateKey, totalBytes, now)
        .run();
    } catch (_) {}
  }

  async getBudgetStatus(): Promise<BudgetStatus> {
    const dateKey = this.getDateKey();

    // Limits configured in environment or Cloudflare Free Tier defaults
    const workerLimit = parseInt(this.env.MAX_WORKERS_PER_DAY || '100000', 10);
    const d1WriteLimit = parseInt(this.env.MAX_D1_WRITES_PER_DAY || '100000', 10);
    const d1ReadLimit = parseInt(this.env.MAX_D1_READS_PER_MONTH || '5000000', 10);
    const doLimit = 100000;
    const r2LimitGb = parseFloat(this.env.MAX_R2_STORAGE_GB || '10');
    const r2LimitBytes = r2LimitGb * 1024 * 1024 * 1024;

    const row = await this.env.DB.prepare(
      'SELECT * FROM free_tier_usage WHERE date_key = ?1'
    )
      .bind(dateKey)
      .first<FreeTierUsage>();

    const workerUsed = row?.worker_requests || 0;
    const d1WritesUsed = row?.d1_writes || 0;
    const d1ReadsUsed = row?.d1_reads || 0;
    const doUsed = row?.do_requests || 0;
    const r2BytesUsed = row?.r2_storage_bytes || 0;

    const workerPct = Math.min(100, Math.round((workerUsed / workerLimit) * 100));
    const d1WritesPct = Math.min(100, Math.round((d1WritesUsed / d1WriteLimit) * 100));
    const d1ReadsPct = Math.min(100, Math.round((d1ReadsUsed / d1ReadLimit) * 100));
    const doPct = Math.min(100, Math.round((doUsed / doLimit) * 100));
    const r2GbUsed = parseFloat((r2BytesUsed / (1024 * 1024 * 1024)).toFixed(2));
    const r2Pct = Math.min(100, Math.round((r2BytesUsed / r2LimitBytes) * 100));

    const isNearLimit =
      workerPct >= 90 ||
      d1WritesPct >= 90 ||
      d1ReadsPct >= 90 ||
      doPct >= 90 ||
      r2Pct >= 90;

    const hardBudgetEnabled = this.env.FREE_TIER_HARD_BUDGET !== 'false';
    const cloudCacheActive = !hardBudgetEnabled || r2Pct < 95;

    return {
      worker_requests: { used: workerUsed, limit: workerLimit, pct: workerPct },
      d1_reads: { used: d1ReadsUsed, limit: d1ReadLimit, pct: d1ReadsPct },
      d1_writes: { used: d1WritesUsed, limit: d1WriteLimit, pct: d1WritesPct },
      do_requests: { used: doUsed, limit: doLimit, pct: doPct },
      r2_storage_gb: { used: r2GbUsed, limit: r2LimitGb, pct: r2Pct },
      hard_budget_enabled: hardBudgetEnabled,
      estimated_cost: 0.0,
      is_near_limit: isNearLimit,
      cloud_cache_active: cloudCacheActive,
    };
  }

  async isCloudCachePermitted(): Promise<boolean> {
    if (this.env.FREE_TIER_HARD_BUDGET === 'false') return true;
    const status = await this.getBudgetStatus();
    return status.cloud_cache_active;
  }
}
