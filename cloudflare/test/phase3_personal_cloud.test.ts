// Phase 3: Complete Personal-Cloud Capabilities Vitest Suite
import { describe, it, expect, beforeEach } from 'vitest';
import worker from '../src/index';
import { generateJwt } from '../src/services/auth';

describe('PHASE 3: Personal-Cloud Capabilities, Expiring Sharing, File Requests & Media', () => {
  const jwtSecret = 'phase3_test_jwt_secret_32_characters_long!';
  const userId = 'usr_phase3_tester';
  let token: string;

  let mockFiles: Map<string, any>;
  let mockShares: Map<string, any>;
  let mockPlayback: Map<string, any>;
  let mockEnv: any;
  const ctx: any = { waitUntil: () => {} };

  beforeEach(async () => {
    token = await generateJwt({ sub: userId, email: 'p3@pcos.dev', role: 'user' }, jwtSecret, 3600);

    mockFiles = new Map();
    mockShares = new Map();
    mockPlayback = new Map();

    const sampleBytes = new TextEncoder().encode('Personal Cloud Shared Video Content 2026!');
    mockFiles.set('file_video_1', {
      id: 'file_video_1',
      user_id: userId,
      name: 'vacation_drone.mp4',
      mime_type: 'video/mp4',
      size_bytes: sampleBytes.length,
      sha256_hash: 'drone_sha256_hash_789',
      storage_path: 'd1',
      data_blob: sampleBytes,
      is_trashed: 0,
      is_favorite: 0,
    });

    mockFiles.set('folder_drop_1', {
      id: 'folder_drop_1',
      user_id: userId,
      name: 'Client Submissions',
      entry_type: 'folder',
      mime_type: null,
      size_bytes: 0,
      is_trashed: 0,
      is_favorite: 0,
    });

    mockEnv = {
      PCOS_ENV: 'test',
      PCOS_CONTROL_VERSION: '1.8.0',
      JWT_SECRET: jwtSecret,
      FREE_TIER_HARD_BUDGET: 'true',
      DB: {
        prepare: (sql: string) => {
          let bound: any[] = [];
          return {
            bind: (...args: any[]) => {
              bound = args;
              return {
                first: async () => {
                  if (sql.includes('SELECT * FROM file_entries WHERE id = ?1')) {
                    const id = bound[0];
                    const f = mockFiles.get(id);
                    if (sql.includes('AND user_id = ?2')) {
                      return f && f.user_id === bound[1] ? f : null;
                    }
                    return f || null;
                  }
                  if (sql.includes('SELECT id, name, size_bytes, mime_type FROM file_entries WHERE id = ?1 AND user_id = ?2')) {
                    const f = mockFiles.get(bound[0]);
                    return f && f.user_id === bound[1] ? f : null;
                  }
                  if (sql.includes('SELECT id, name, size_bytes, mime_type, sha256_hash FROM file_entries WHERE id = ?1')) {
                    return mockFiles.get(bound[0]) || null;
                  }
                  if (sql.includes('SELECT * FROM shares WHERE share_token = ?1')) {
                    const tok = bound[0];
                    for (const s of mockShares.values()) {
                      if (s.share_token === tok) return s;
                    }
                    return null;
                  }
                  if (sql.includes('SELECT * FROM playback_progress WHERE user_id = ?1 AND file_id = ?2')) {
                    return mockPlayback.get(`${bound[0]}_${bound[1]}`) || null;
                  }
                  return null;
                },
                all: async () => {
                  if (sql.includes('FROM shares s')) {
                    const list = Array.from(mockShares.values()).filter((s) => s.user_id === bound[0]);
                    return {
                      results: list.map((s) => {
                        const f = mockFiles.get(s.file_id) || {};
                        return {
                          ...s,
                          file_name: f.name,
                          size_bytes: f.size_bytes,
                          mime_type: f.mime_type,
                        };
                      }),
                    };
                  }
                  if (sql.includes('FROM playback_progress p')) {
                    return { results: Array.from(mockPlayback.values()) };
                  }
                  return { results: [] };
                },
                run: async () => {
                  if (sql.includes('INSERT INTO shares')) {
                    // id, user_id, file_id, share_token, is_public, is_upload_request, password_hash, expires_at, max_downloads, download_count, created_at
                    const s = {
                      id: bound[0],
                      user_id: bound[1],
                      file_id: bound[2],
                      share_token: bound[3],
                      is_public: bound[4],
                      is_upload_request: bound[5],
                      password_hash: bound[6],
                      expires_at: bound[7],
                      max_downloads: bound[8],
                      download_count: 0,
                      created_at: bound[9],
                    };
                    mockShares.set(s.id, s);
                  }
                  if (sql.includes('DELETE FROM shares WHERE id = ?1 AND user_id = ?2')) {
                    const s = mockShares.get(bound[0]);
                    if (s && s.user_id === bound[1]) {
                      mockShares.delete(bound[0]);
                    }
                  }
                  if (sql.includes('UPDATE shares SET download_count = download_count + 1 WHERE id = ?1')) {
                    const s = mockShares.get(bound[0]);
                    if (s) s.download_count = (s.download_count || 0) + 1;
                  }
                  if (sql.includes('INSERT INTO file_entries')) {
                    const f = {
                      id: bound[0],
                      user_id: bound[1],
                      parent_id: bound[2],
                      name: bound[3],
                      entry_type: 'file',
                      mime_type: bound[4],
                      size_bytes: bound[5],
                      sha256_hash: bound[6],
                      storage_path: 'd1',
                      data_blob: bound[7],
                      created_at: bound[8],
                      updated_at: bound[8],
                    };
                    mockFiles.set(f.id, f);
                  }
                  if (sql.includes('INSERT INTO playback_progress')) {
                    const key = `${bound[1]}_${bound[2]}`;
                    mockPlayback.set(key, {
                      id: bound[0],
                      user_id: bound[1],
                      file_id: bound[2],
                      position_secs: bound[3],
                      duration_secs: bound[4],
                      completed: bound[5],
                      updated_at: bound[6],
                    });
                  }
                  return { success: true };
                },
              };
            },
          };
        },
      },
      PRESENCE_HUB: {
        idFromName: () => 'presence_hub_id',
        get: () => ({
          fetch: async () => Response.json({ success: true, result: {} }),
        }),
      },
    };
  });

  // 1. Sharing: Create Expiring, Password-Protected Share Link
  describe('Secure Expiring & Revocable Sharing', () => {
    it('should create an expiring, password-protected share link and list it', async () => {
      const expiresAt = new Date(Date.now() + 86400000).toISOString(); // 24h
      const createReq = new Request('http://edge.pcos.dev/api/v1/shares', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          file_id: 'file_video_1',
          password: 'RecipientSecretPassword!',
          expires_at: expiresAt,
          max_downloads: 5,
        }),
      });

      const createResp = await worker.fetch(createReq, mockEnv, ctx);
      expect(createResp.status).toBe(201);
      const shareData = (await createResp.json()) as any;
      expect(shareData.share_token).toBeDefined();
      expect(shareData.share_url).toContain('/s/');
      expect(shareData.has_password).toBe(true);
      expect(shareData.max_downloads).toBe(5);

      // Verify list endpoint
      const listReq = new Request('http://edge.pcos.dev/api/v1/shares', {
        headers: { Authorization: `Bearer ${token}` },
      });
      const listResp = await worker.fetch(listReq, mockEnv, ctx);
      expect(listResp.status).toBe(200);
      const listData = (await listResp.json()) as any;
      expect(listData.shares.length).toBe(1);
      expect(listData.shares[0].file_name).toBe('vacation_drone.mp4');

      // Public Recipient Queries Metadata (No Auth Token)
      const pubReq = new Request(`http://edge.pcos.dev/s/${shareData.share_token}`);
      const pubResp = await worker.fetch(pubReq, mockEnv, ctx);
      expect(pubResp.status).toBe(200);
      const pubData = (await pubResp.json()) as any;
      expect(pubData.name).toBe('vacation_drone.mp4');
      expect(pubData.requires_password).toBe(true);

      // Verify Password (wrong fails 401, correct passes 200)
      const wrongPassReq = new Request(`http://edge.pcos.dev/s/${shareData.share_token}/verify`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: 'WrongPassword' }),
      });
      const wrongPassResp = await worker.fetch(wrongPassReq, mockEnv, ctx);
      expect(wrongPassResp.status).toBe(401);

      const goodPassReq = new Request(`http://edge.pcos.dev/s/${shareData.share_token}/verify`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: 'RecipientSecretPassword!' }),
      });
      const goodPassResp = await worker.fetch(goodPassReq, mockEnv, ctx);
      expect(goodPassResp.status).toBe(200);

      // Download Shared File (without password fails 401)
      const unauthDlReq = new Request(`http://edge.pcos.dev/s/${shareData.share_token}/download`);
      const unauthDlResp = await worker.fetch(unauthDlReq, mockEnv, ctx);
      expect(unauthDlResp.status).toBe(401);

      // Download Shared File with valid password header
      const authDlReq = new Request(`http://edge.pcos.dev/s/${shareData.share_token}/download`, {
        headers: { 'X-Share-Password': 'RecipientSecretPassword!' },
      });
      const authDlResp = await worker.fetch(authDlReq, mockEnv, ctx);
      expect(authDlResp.status).toBe(200);
      expect(authDlResp.headers.get('Accept-Ranges')).toBe('bytes');
      const text = await authDlResp.text();
      expect(text).toContain('Personal Cloud Shared Video Content 2026!');

      // Revoke Share
      const revokeReq = new Request(`http://edge.pcos.dev/api/v1/shares/${shareData.id}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });
      const revokeResp = await worker.fetch(revokeReq, mockEnv, ctx);
      expect(revokeResp.status).toBe(200);

      // Subsequent public access fails 404
      const afterRevokeResp = await worker.fetch(pubReq, mockEnv, ctx);
      expect(afterRevokeResp.status).toBe(404);
    });

    it('should reject access to expired share link with 410 Gone', async () => {
      const expiredDate = new Date(Date.now() - 3600000).toISOString(); // 1 hour ago
      const shareId = 'shr_expired_test';
      const shareToken = 'expired_tok_123';
      mockShares.set(shareId, {
        id: shareId,
        user_id: userId,
        file_id: 'file_video_1',
        share_token: shareToken,
        is_public: 1,
        is_upload_request: 0,
        password_hash: null,
        expires_at: expiredDate,
        max_downloads: 10,
        download_count: 0,
      });

      const req = new Request(`http://edge.pcos.dev/s/${shareToken}`);
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(410);
      const data = (await resp.json()) as any;
      expect(data.code).toBe('SHARE_EXPIRED');
    });

    it('should reject access when download limit is reached with 403 Forbidden', async () => {
      const shareId = 'shr_limit_test';
      const shareToken = 'limit_tok_456';
      mockShares.set(shareId, {
        id: shareId,
        user_id: userId,
        file_id: 'file_video_1',
        share_token: shareToken,
        is_public: 1,
        is_upload_request: 0,
        password_hash: null,
        expires_at: null,
        max_downloads: 3,
        download_count: 3, // Already reached max
      });

      const req = new Request(`http://edge.pcos.dev/s/${shareToken}/download`);
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(403);
      const data = (await resp.json()) as any;
      expect(data.code).toBe('LIMIT_EXCEEDED');
    });
  });

  // 2. File Request: Public Upload to User's Folder
  describe('File Requests (Public Recipient Uploads)', () => {
    it('should allow external recipient to upload file via file request link', async () => {
      const shareId = 'shr_file_req_1';
      const shareToken = 'upload_tok_789';
      mockShares.set(shareId, {
        id: shareId,
        user_id: userId,
        file_id: 'folder_drop_1',
        share_token: shareToken,
        is_public: 1,
        is_upload_request: 1,
        password_hash: null,
        expires_at: null,
        max_downloads: null,
        download_count: 0,
      });

      const formData = new FormData();
      const clientFile = new File(['Contract Sign-off Document 2026'], 'contract_signed.pdf', {
        type: 'application/pdf',
      });
      formData.append('file', clientFile);

      const upReq = new Request(`http://edge.pcos.dev/s/${shareToken}/upload`, {
        method: 'POST',
        body: formData,
      });

      const upResp = await worker.fetch(upReq, mockEnv, ctx);
      expect(upResp.status).toBe(201);
      const upData = (await upResp.json()) as any;
      expect(upData.success).toBe(true);
      expect(upData.name).toBe('contract_signed.pdf');

      // File is stored in owner's cloud
      expect(mockFiles.has(upData.file_id)).toBe(true);
      const stored = mockFiles.get(upData.file_id);
      expect(stored.user_id).toBe(userId);
      expect(stored.parent_id).toBe('folder_drop_1');
    });
  });

  // 3. Media Probe & Playback Progress
  describe('Media Direct-Play Probe & Playback Tracking', () => {
    it('should probe media file for direct play compatibility', async () => {
      const probeReq = new Request('http://edge.pcos.dev/api/v1/media/probe/file_video_1', {
        headers: { Authorization: `Bearer ${token}` },
      });
      const probeResp = await worker.fetch(probeReq, mockEnv, ctx);
      expect(probeResp.status).toBe(200);
      const probeData = (await probeResp.json()) as any;
      expect(probeData.direct_play_supported).toBe(true);
      expect(probeData.http_range_seekable).toBe(true);
    });

    it('should save and retrieve video playback position for resume', async () => {
      const saveReq = new Request('http://edge.pcos.dev/api/v1/streaming/progress/file_video_1', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          position_secs: 142.5,
          duration_secs: 600.0,
          completed: false,
        }),
      });

      const saveResp = await worker.fetch(saveReq, mockEnv, ctx);
      expect(saveResp.status).toBe(200);

      const getReq = new Request('http://edge.pcos.dev/api/v1/streaming/progress/file_video_1', {
        headers: { Authorization: `Bearer ${token}` },
      });
      const getResp = await worker.fetch(getReq, mockEnv, ctx);
      expect(getResp.status).toBe(200);
      const progressData = (await getResp.json()) as any;
      expect(progressData.position_secs).toBe(142.5);
      expect(progressData.duration_secs).toBe(600.0);
    });
  });
});
