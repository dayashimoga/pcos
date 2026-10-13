// Phase 2: Storage, Remote Connectivity, HTTP Range 206, and Resumable Transfers Vitest Suite
import { describe, it, expect, beforeEach } from 'vitest';
import worker, { parseHttpRange } from '../src/index';
import { generateJwt } from '../src/services/auth';

describe('PHASE 2: Real Storage, Remote Connectivity, HTTP Range & Resumable Transfers', () => {
  const jwtSecret = 'phase2_test_jwt_secret_32_characters_long!';
  const userId = 'usr_phase2_tester';
  let token: string;

  let mockFiles: Map<string, any>;
  let mockStorageNodes: Map<string, any>;
  let mockDevices: Map<string, any>;
  let mockEnv: any;
  const ctx: any = { waitUntil: () => {} };

  beforeEach(async () => {
    token = await generateJwt({ sub: userId, email: 'p2@pcos.dev', role: 'user' }, jwtSecret, 3600);

    mockFiles = new Map();
    mockStorageNodes = new Map();
    mockDevices = new Map();

    // Set up test physical storage node
    mockDevices.set('dev_laptop_1', {
      id: 'dev_laptop_1',
      user_id: userId,
      cloud_id: 'cld_p2',
      name: 'ThinkPad Laptop',
      device_type: 'laptop',
      os: 'windows',
      is_online: 1,
    });

    mockStorageNodes.set('node_drive_d', {
      id: 'node_drive_d',
      device_id: 'dev_laptop_1',
      user_id: userId,
      name: 'Data Drive D',
      storage_path: 'D:/PCOS_Storage',
      total_capacity_bytes: 1000000000000,
      available_capacity_bytes: 500000000000,
      is_online: 1,
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
                    const entry = mockFiles.get(id);
                    if (sql.includes('AND user_id = ?2')) {
                      return entry && entry.user_id === bound[1] ? entry : null;
                    }
                    return entry || null;
                  }
                  if (sql.includes('SELECT id, device_id, storage_path, is_online FROM storage_nodes WHERE id = ?1')) {
                    const id = bound[0];
                    const node = mockStorageNodes.get(id);
                    if (sql.includes('AND user_id = ?2')) {
                      return node && node.user_id === bound[1] ? node : null;
                    }
                    return node || null;
                  }
                  if (sql.includes('SELECT id, device_id, name, storage_path, is_online FROM storage_nodes WHERE id = ?1 AND user_id = ?2')) {
                    const node = mockStorageNodes.get(bound[0]);
                    return node && node.user_id === bound[1] ? node : null;
                  }
                  if (sql.includes('SELECT id FROM device_identities WHERE id = ?1 AND user_id = ?2')) {
                    const dev = mockDevices.get(bound[0]);
                    return dev && dev.user_id === bound[1] ? dev : null;
                  }
                  return null;
                },
                all: async () => {
                  if (sql.includes('FROM file_entries WHERE user_id = ?1')) {
                    return { results: Array.from(mockFiles.values()).filter((f) => f.user_id === bound[0]) };
                  }
                  return { results: [] };
                },
                run: async () => {
                  if (sql.includes('INSERT INTO file_entries')) {
                    const f = {
                      id: bound[0],
                      user_id: bound[1],
                      parent_id: bound[2],
                      name: bound[3],
                      entry_type: 'file',
                      mime_type: bound[4],
                      size_bytes: typeof bound[5] === 'number' ? bound[5] : 0,
                      sha256_hash: bound[6] || '',
                      storage_path: sql.includes("'resumable_transfer'") ? 'resumable_transfer' : bound[7],
                      storage_node_id: sql.includes("'resumable_transfer'") ? bound[7] : bound[8],
                      data_blob: bound[8] instanceof Uint8Array || bound[8] instanceof ArrayBuffer ? bound[8] : (bound[7] instanceof Uint8Array ? bound[7] : null),
                      is_trashed: 0,
                      is_favorite: 0,
                      created_at: bound[bound.length - 1],
                      updated_at: bound[bound.length - 1],
                    };
                    mockFiles.set(f.id, f);
                  }
                  if (sql.includes('UPDATE file_entries SET storage_path = ?1, sha256_hash = ?2')) {
                    const f = mockFiles.get(bound[3]);
                    if (f) {
                      f.storage_path = bound[0];
                      f.sha256_hash = bound[1];
                      f.updated_at = bound[2];
                    }
                  }
                  if (sql.includes('UPDATE file_entries SET updated_at = ?1 WHERE id = ?2')) {
                    const f = mockFiles.get(bound[1]);
                    if (f) f.updated_at = bound[0];
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
          fetch: async (req: any, init?: any) => {
            const urlStr = typeof req === 'string' ? req : (req.url || 'http://do/');
            const url = new URL(urlStr);

            if (url.pathname === '/resolve') {
              const targetDeviceId = url.searchParams.get('targetDeviceId');
              const callerLanIp = url.searchParams.get('callerLanIp');
              if (callerLanIp === '192.168.1.50') {
                return Response.json({
                  is_online: true,
                  recommended_route: 'LAN',
                  lan_ip: '192.168.1.100',
                  port: 19820,
                });
              }
              return Response.json({
                is_online: true,
                recommended_route: 'Relay',
                relay_endpoint: 'https://pcos-control-plane.workers.dev',
              });
            }

            if (url.pathname === '/proxy/fs') {
              let body: any = {};
              if (init && init.body) {
                body = typeof init.body === 'string' ? JSON.parse(init.body) : init.body;
              } else if (req && req.body) {
                body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
              } else if (req && typeof req.json === 'function') {
                body = await req.json();
              }
              if (body.op === 'fs_read_chunk') {
                const sampleContent = 'Hello PCOS HTTP Range Streaming & Seeking Protocol 2026!';
                const binary = new TextEncoder().encode(sampleContent);
                const offset = body.offset || 0;
                const length = body.length || binary.length;
                const slice = binary.subarray(offset, offset + length);
                const b64 = btoa(String.fromCharCode(...slice));
                return Response.json({
                  success: true,
                  result: {
                    relative_path: body.relative_path,
                    offset,
                    length: slice.length,
                    total_size: binary.length,
                    data_base64: b64,
                  },
                });
              }
              if (body.op === 'fs_write_chunk') {
                return Response.json({
                  success: true,
                  result: {
                    relative_path: body.relative_path,
                    offset: body.offset,
                    bytes_written: body.data_base64 ? Math.floor(body.data_base64.length * 0.75) : 0,
                  },
                });
              }
              if (body.op === 'fs_checksum') {
                return Response.json({
                  success: true,
                  result: {
                    sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                  },
                });
              }
              return Response.json({ success: true, result: {} });
            }

            return Response.json({ ok: true });
          },
        }),
      },
    };
  });

  // 1. parseHttpRange Utility Tests
  describe('HTTP Range Parser', () => {
    it('should parse standard bytes range header', () => {
      const range = parseHttpRange('bytes=0-499', 1000);
      expect(range).not.toBeNull();
      expect(range?.start).toBe(0);
      expect(range?.end).toBe(499);
    });

    it('should parse prefix range (from offset to EOF)', () => {
      const range = parseHttpRange('bytes=500-', 1000);
      expect(range).not.toBeNull();
      expect(range?.start).toBe(500);
      expect(range?.end).toBe(999);
    });

    it('should parse suffix range (last N bytes)', () => {
      const range = parseHttpRange('bytes=-200', 1000);
      expect(range).not.toBeNull();
      expect(range?.start).toBe(800);
      expect(range?.end).toBe(999);
    });

    it('should reject invalid or out of bounds range', () => {
      expect(parseHttpRange('bytes=1500-2000', 1000)).toBeNull();
      expect(parseHttpRange('bytes=500-400', 1000)).toBeNull();
      expect(parseHttpRange('invalid', 1000)).toBeNull();
    });
  });

  // 2. HTTP Range 206 Partial Content on File Download & Preview
  describe('HTTP Range 206 Streaming', () => {
    it('should stream partial content (206) with Content-Range and Accept-Ranges headers', async () => {
      const fileId = 'file_stream_test_1';
      const content = new TextEncoder().encode('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ');
      mockFiles.set(fileId, {
        id: fileId,
        user_id: userId,
        name: 'video_clip.mp4',
        mime_type: 'video/mp4',
        size_bytes: content.length,
        sha256_hash: 'mock_sha256_123',
        storage_path: 'd1',
        data_blob: content,
      });

      // Request bytes 5 to 14 (10 bytes)
      const req = new Request(`http://edge.pcos.dev/api/v1/files/${fileId}/download`, {
        headers: {
          Authorization: `Bearer ${token}`,
          Range: 'bytes=5-14',
        },
      });

      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(206);
      expect(resp.headers.get('Accept-Ranges')).toBe('bytes');
      expect(resp.headers.get('Content-Range')).toBe(`bytes 5-14/${content.length}`);
      expect(resp.headers.get('Content-Length')).toBe('10');
      expect(resp.headers.get('ETag')).toBe('"mock_sha256_123"');

      const bodyText = await resp.text();
      expect(bodyText).toBe('56789ABCDE');
    });

    it('should return 416 Range Not Satisfiable when range starts beyond file size', async () => {
      const fileId = 'file_oob_test';
      const content = new TextEncoder().encode('short');
      mockFiles.set(fileId, {
        id: fileId,
        user_id: userId,
        name: 'short.txt',
        mime_type: 'text/plain',
        size_bytes: content.length,
        storage_path: 'd1',
        data_blob: content,
      });

      const req = new Request(`http://edge.pcos.dev/api/v1/files/${fileId}/download`, {
        headers: {
          Authorization: `Bearer ${token}`,
          Range: 'bytes=100-200',
        },
      });

      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(416);
      expect(resp.headers.get('Content-Range')).toBe(`bytes */${content.length}`);
    });

    it('should stream chunk from physical laptop storage node over Durable Object proxy', async () => {
      const fileId = 'file_on_physical_disk';
      mockFiles.set(fileId, {
        id: fileId,
        user_id: userId,
        name: 'recorded_meeting.mkv',
        mime_type: 'video/x-matroska',
        size_bytes: 58,
        sha256_hash: 'node_file_hash_456',
        storage_path: 'recordings/meeting.mkv',
        storage_node_id: 'node_drive_d',
      });

      const req = new Request(`http://edge.pcos.dev/api/v1/files/${fileId}/preview`, {
        headers: {
          Authorization: `Bearer ${token}`,
          Range: 'bytes=0-9',
        },
      });

      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(206);
      expect(resp.headers.get('Content-Range')).toBe('bytes 0-9/56');
      expect(resp.headers.get('Content-Length')).toBe('10');
      const text = await resp.text();
      expect(text).toBe('Hello PCOS');
    });
  });

  // 3. Resumable Chunked Transfer Protocol (up to 100GB files)
  describe('Resumable Transfers Protocol', () => {
    it('should execute full resumable transfer lifecycle: init -> chunk -> status -> finalize', async () => {
      // Step 1: Initialize Resumable Transfer for a 50GB file
      const initReq = new Request('http://edge.pcos.dev/api/v1/transfers/resumable/init', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          name: 'raw_backup_disk_image.img',
          size_bytes: 53687091200, // 50 GB
          sha256_hash: 'expected_backup_hash_123',
          storage_node_id: 'node_drive_d',
        }),
      });

      const initResp = await worker.fetch(initReq, mockEnv, ctx);
      expect(initResp.status).toBe(201);
      const initData = (await initResp.json()) as any;
      expect(initData.transfer_id).toBeDefined();
      expect(initData.total_bytes).toBe(53687091200);
      expect(initData.chunk_size).toBe(2097152); // 2 MB

      const transferId = initData.transfer_id;

      // Step 2: Upload First Chunk at offset 0
      const chunkB64 = btoa('Sample 2MB Chunk Data Payload');
      const chunkReq = new Request(`http://edge.pcos.dev/api/v1/transfers/resumable/${transferId}/chunk`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          offset: 0,
          data_base64: chunkB64,
        }),
      });

      const chunkResp = await worker.fetch(chunkReq, mockEnv, ctx);
      expect(chunkResp.status).toBe(200);
      const chunkData = (await chunkResp.json()) as any;
      expect(chunkData.success).toBe(true);
      expect(chunkData.offset).toBe(0);

      // Step 3: Query Transfer Status for Resume
      const statusReq = new Request(`http://edge.pcos.dev/api/v1/transfers/resumable/${transferId}/status`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      const statusResp = await worker.fetch(statusReq, mockEnv, ctx);
      expect(statusResp.status).toBe(200);
      const statusData = (await statusResp.json()) as any;
      expect(statusData.total_bytes).toBe(53687091200);
      expect(statusData.status).toBe('in_progress');

      // Step 4: Finalize Transfer
      const finReq = new Request(`http://edge.pcos.dev/api/v1/transfers/resumable/${transferId}/finalize`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ sha256_hash: 'expected_backup_hash_123' }),
      });

      const finResp = await worker.fetch(finReq, mockEnv, ctx);
      expect(finResp.status).toBe(200);
      const finData = (await finResp.json()) as any;
      expect(finData.success).toBe(true);
      expect(finData.file_id).toBe(transferId);
      expect(finData.sha256_hash).toBe('expected_backup_hash_123');
    });
  });

  // 4. Remote Route Resolution (Direct LAN -> P2P -> Relay Fallback)
  describe('Connection Manager Route Resolution', () => {
    it('should recommend Direct LAN route when devices share local subnet', async () => {
      const req = new Request('http://edge.pcos.dev/api/v1/devices/resolve/dev_laptop_1?callerLanIp=192.168.1.50', {
        headers: { Authorization: `Bearer ${token}` },
      });
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(200);
      const data = (await resp.json()) as any;
      expect(data.recommended_route).toBe('LAN');
      expect(data.lan_ip).toBe('192.168.1.100');
    });

    it('should recommend Relay route when caller is on another network (e.g. 5G/cellular)', async () => {
      const req = new Request('http://edge.pcos.dev/api/v1/devices/resolve/dev_laptop_1?callerLanIp=10.240.12.8', {
        headers: { Authorization: `Bearer ${token}` },
      });
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(200);
      const data = (await resp.json()) as any;
      expect(data.recommended_route).toBe('Relay');
    });

    it('should reject unauthenticated route resolution attempt', async () => {
      const req = new Request('http://edge.pcos.dev/api/v1/devices/resolve/dev_laptop_1');
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(401);
    });
  });

  // 5. Remote Checksum Calculation via Agent Proxy
  describe('Remote Checksum Proxy', () => {
    it('should compute cryptographic SHA-256 hash of file on physical disk', async () => {
      const req = new Request('http://edge.pcos.dev/api/v1/storage/nodes/node_drive_d/fs/checksum?path=photos/family.raw', {
        headers: { Authorization: `Bearer ${token}` },
      });
      const resp = await worker.fetch(req, mockEnv, ctx);
      expect(resp.status).toBe(200);
      const data = (await resp.json()) as any;
      expect(data.sha256).toHaveLength(64);
    });
  });
});
