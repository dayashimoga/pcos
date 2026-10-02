// Optional Always-Available Encrypted Cloud Cache (R2)
// Stores encrypted chunks/files only when user explicitly selects "Always Available Remotely"
// Guarded by the Free-Tier budget controller so limits are never exceeded.

import { Env } from '../types';
import { BudgetGuard } from './budget';

export class CloudCacheService {
  private env: Env;
  private budget: BudgetGuard;

  constructor(env: Env) {
    this.env = env;
    this.budget = new BudgetGuard(env);
  }

  async putEncryptedFile(
    userId: string,
    fileId: string,
    stream: ReadableStream,
    sizeBytes: number,
    mimeType: string
  ): Promise<{ success: boolean; r2Key?: string; message?: string }> {
    if (!this.env.CACHE_R2) {
      return { success: false, message: 'Cloud cache is not enabled in this deployment.' };
    }

    const permitted = await this.budget.isCloudCachePermitted();
    if (!permitted) {
      return {
        success: false,
        message: 'Cloud cache temporarily suspended: Free-tier limit protection active.',
      };
    }

    const r2Key = `cache/${userId}/${fileId}`;

    try {
      await this.env.CACHE_R2.put(r2Key, stream, {
        httpMetadata: { contentType: mimeType },
        customMetadata: {
          userId,
          fileId,
          cachedAt: new Date().toISOString(),
        },
      });

      // Update R2 storage bytes in usage tracking
      await this.budget.updateR2StorageBytes(sizeBytes);

      return { success: true, r2Key };
    } catch (e) {
      return { success: false, message: `R2 put failed: ${String(e)}` };
    }
  }

  async getEncryptedFile(userId: string, fileId: string): Promise<R2ObjectBody | null> {
    if (!this.env.CACHE_R2) return null;
    const r2Key = `cache/${userId}/${fileId}`;
    const obj = await this.env.CACHE_R2.get(r2Key);
    return obj;
  }

  async deleteEncryptedFile(userId: string, fileId: string): Promise<void> {
    if (!this.env.CACHE_R2) return;
    const r2Key = `cache/${userId}/${fileId}`;
    await this.env.CACHE_R2.delete(r2Key);
  }
}
