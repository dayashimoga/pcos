// Phase 7: Production Personal Cloud Vitest Suite
// Covers Family Clouds, Emergency Recovery, Storage Policy Engine,
// Cluster Protection, Replicas, Zero-Cost Audit & Migration Export.

import { describe, it, expect, beforeEach } from 'vitest';
import worker from '../src/index';
import { hashPassword, generateJwt } from '../src/services/auth';

describe('PHASE 7: Production Personal Cloud, Family, Policies & HA', () => {
  const jwtSecret = 'phase7_test_jwt_secret_32_characters_long!';
  let mockUsers: Map<string, any>;
  let mockDevices: Map<string, any>;
  let mockStorageNodes: Map<string, any>;
  let mockFileEntries: Map<string, any>;
  let mockFamilyClouds: Map<string, any>;
  let mockFamilyMembers: Map<string, any>;
  let mockRecoveryKeys: Map<string, any>;
  let mockStoragePolicies: Map<string, any>;
  let mockFileReplicas: Map<string, any>;
  let mockClusterProtection: Map<string, any>;

  let mockEnv: any;
  const ctx: any = { waitUntil: () => {} };

  beforeEach(async () => {
    mockUsers = new Map();
    mockDevices = new Map();
    mockStorageNodes = new Map();
    mockFileEntries = new Map();
    mockFamilyClouds = new Map();
    mockFamilyMembers = new Map();
    mockRecoveryKeys = new Map();
    mockStoragePolicies = new Map();
    mockFileReplicas = new Map();
    mockClusterProtection = new Map();

    const passHash = await hashPassword('TestP@ss123!');
    mockUsers.set('usr_owner1', {
      id: 'usr_owner1',
      email: 'owner@example.com',
      password_hash: passHash,
      display_name: 'Cloud Owner',
      role: 'admin',
      quota_bytes: 53687091200,
      used_bytes: 1048576,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    mockUsers.set('usr_member2', {
      id: 'usr_member2',
      email: 'member@example.com',
      password_hash: passHash,
      display_name: 'Family Member',
      role: 'user',
      quota_bytes: 21474836480,
      used_bytes: 0,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    mockStorageNodes.set('sn_ssd1', {
      id: 'sn_ssd1',
      device_id: 'dev_pc1',
      user_id: 'usr_owner1',
      name: 'High-Speed NVMe SSD',
      storage_path: 'D:\\PCOS\\FastPool',
      fs_type: 'NTFS',
      total_capacity_bytes: 1000000000000,
      available_capacity_bytes: 800000000000,
      is_online: 1,
      capabilities_json: '{"ffmpeg":true,"ocr":true,"tantivy":true,"ollama":true}',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    mockStorageNodes.set('sn_hdd1', {
      id: 'sn_hdd1',
      device_id: 'dev_nas1',
      user_id: 'usr_owner1',
      name: 'Massive Media HDD',
      storage_path: '/mnt/storage/media',
      fs_type: 'ext4',
      total_capacity_bytes: 8000000000000,
      available_capacity_bytes: 6000000000000,
      is_online: 1,
      capabilities_json: '{"ffmpeg":true,"ocr":false,"tantivy":false,"ollama":false}',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    mockEnv = {
      PCOS_ENV: 'test',
      PCOS_CONTROL_VERSION: '1.8.0',
      JWT_SECRET: jwtSecret,
      FREE_TIER_HARD_BUDGET: 'true',
      DB: {
        prepare: (sql: string) => {
          let bound: any[] = [];
          const stmt: any = {
            bind: (...args: any[]) => {
              bound = args;
              return stmt;
            },
            first: async () => {
              if (sql.includes('FROM users WHERE email = ?1')) {
                const email = bound[0];
                for (const u of mockUsers.values()) {
                  if (u.email === email) return u;
                }
                return null;
              }
              if (sql.includes('FROM users WHERE id = ?1')) {
                return mockUsers.get(bound[0]) || null;
              }
              if (sql.includes('FROM family_clouds WHERE id = ?1')) {
                return mockFamilyClouds.get(bound[0]) || null;
              }
              if (sql.includes('FROM family_members WHERE cloud_id = ?1 AND user_id = ?2')) {
                const key = `${bound[0]}:${bound[1]}`;
                return mockFamilyMembers.get(key) || null;
              }
              if (sql.includes('FROM family_members WHERE invite_code = ?1')) {
                for (const m of mockFamilyMembers.values()) {
                  if (m.invite_code === bound[0]) return m;
                }
                return null;
              }
              if (sql.includes('FROM family_members WHERE id = ?1')) {
                for (const m of mockFamilyMembers.values()) {
                  if (m.id === bound[0]) return m;
                }
                return null;
              }
              if (sql.includes('FROM family_members WHERE cloud_id = ?1 AND user_id = ?2')) {
                for (const m of mockFamilyMembers.values()) {
                  if (m.cloud_id === bound[0] && m.user_id === bound[1]) return m;
                }
                return null;
              }
              if (sql.includes('FROM recovery_keys WHERE user_id = ?1 AND is_used = 0')) {
                for (const k of mockRecoveryKeys.values()) {
                  if (k.user_id === bound[0] && !k.is_used) return k;
                }
                return null;
              }
              if (sql.includes('FROM cluster_protection WHERE user_id = ?1')) {
                return mockClusterProtection.get(bound[0]) || null;
              }
              if (sql.includes('FROM storage_policies WHERE id = ?1 AND user_id = ?2')) {
                const p = mockStoragePolicies.get(bound[0]);
                return p && p.user_id === bound[1] ? p : null;
              }
              if (sql.includes('COUNT(*) as count FROM file_entries')) {
                return { count: mockFileEntries.size };
              }
              if (sql.includes('COUNT(*) as count FROM storage_nodes')) {
                return { count: 2 };
              }
              if (sql.includes('COUNT(*) as count FROM file_replicas')) {
                return { count: mockFileReplicas.size };
              }
              return null;
            },
            all: async () => {
              if (sql.includes('FROM storage_nodes')) {
                const nodes = Array.from(mockStorageNodes.values()).filter((n) => !bound[0] || n.user_id === bound[0]);
                return { results: nodes };
              }
              if (sql.includes('FROM family_clouds')) {
                const clouds = Array.from(mockFamilyClouds.values()).filter((c) => c.owner_id === bound[0]);
                return { results: clouds };
              }
              if (sql.includes('FROM family_members')) {
                const members = Array.from(mockFamilyMembers.values()).filter((m) => m.cloud_id === bound[0]);
                return { results: members };
              }
              if (sql.includes('FROM storage_policies WHERE user_id = ?1')) {
                const policies = Array.from(mockStoragePolicies.values()).filter((p) => p.user_id === bound[0]);
                return { results: policies };
              }
              if (sql.includes('FROM file_replicas')) {
                return { results: Array.from(mockFileReplicas.values()) };
              }
              if (sql.includes('FROM file_entries WHERE user_id = ?1 AND is_trashed = 0')) {
                return { results: Array.from(mockFileEntries.values()).filter((f) => f.user_id === bound[0]) };
              }
              return { results: [] };
            },
            run: async () => {
                  if (sql.includes('INSERT INTO family_clouds')) {
                    mockFamilyClouds.set(bound[0], {
                      id: bound[0],
                      name: bound[1],
                      owner_id: bound[2],
                      cloud_type: bound[3],
                      created_at: bound[4],
                    });
                  }
                  if (sql.includes('INSERT INTO family_members')) {
                    const key = `${bound[1]}:${bound[2]}`;
                    mockFamilyMembers.set(key, {
                      id: bound[0],
                      cloud_id: bound[1],
                      user_id: bound[2],
                      role: bound[3],
                      storage_quota_bytes: bound[4],
                      used_bytes: bound[5],
                      invite_code: bound[6] || null,
                      joined_at: bound[7],
                    });
                  }
                  if (sql.includes('UPDATE family_members SET role = ?1')) {
                    for (const m of mockFamilyMembers.values()) {
                      if (m.id === bound[2]) m.role = bound[0];
                    }
                  }
                  if (sql.includes('UPDATE family_members SET storage_quota_bytes = ?1')) {
                    for (const m of mockFamilyMembers.values()) {
                      if (m.id === bound[2]) m.storage_quota_bytes = bound[0];
                    }
                  }
                  if (sql.includes('DELETE FROM family_members WHERE id = ?1')) {
                    for (const [k, m] of mockFamilyMembers.entries()) {
                      if (m.id === bound[0]) mockFamilyMembers.delete(k);
                    }
                  }
                  if (sql.includes('INSERT INTO recovery_keys')) {
                    mockRecoveryKeys.set(bound[0], {
                      id: bound[0],
                      user_id: bound[1],
                      recovery_hash: bound[2],
                      hint: bound[3],
                      is_used: 0,
                      created_at: bound[4],
                    });
                  }
                  if (sql.includes('UPDATE recovery_keys SET is_used = 1')) {
                    for (const k of mockRecoveryKeys.values()) {
                      if (k.id === bound[0]) k.is_used = 1;
                    }
                  }
                  if (sql.includes('UPDATE users SET password_hash = ?1')) {
                    const u = mockUsers.get(bound[2]);
                    if (u) u.password_hash = bound[0];
                  }
                  if (sql.includes('INSERT INTO storage_policies')) {
                    mockStoragePolicies.set(bound[0], {
                      id: bound[0],
                      user_id: bound[1],
                      category: bound[2],
                      mime_patterns: bound[3],
                      target_storage_type: bound[4],
                      target_node_id: bound[5],
                      replica_count: bound[6],
                      availability_tier: bound[7],
                      priority: bound[8],
                      created_at: bound[9],
                      updated_at: bound[10],
                    });
                  }
                  if (sql.includes('DELETE FROM storage_policies WHERE id = ?1 AND user_id = ?2')) {
                    mockStoragePolicies.delete(bound[0]);
                  }
                  if (sql.includes('INSERT INTO cluster_protection') || sql.includes('UPDATE cluster_protection')) {
                    mockClusterProtection.set(bound[0], {
                      user_id: bound[0],
                      protection_mode: bound[1],
                      rpo_target_minutes: bound[2],
                      rto_target_minutes: bound[3],
                      auto_rebalance: bound[4],
                      last_health_check: bound[5],
                      health_status: bound[6],
                      updated_at: bound[7],
                    });
                  }
                  if (sql.includes('INSERT INTO file_replicas')) {
                    mockFileReplicas.set(bound[0], {
                      id: bound[0],
                      file_id: bound[1],
                      storage_node_id: bound[2],
                      device_id: bound[3],
                      status: bound[4],
                      checksum: bound[5],
                      verified_at: bound[6],
                      created_at: bound[7],
                    });
                  }
                  return { success: true };
                },
              };
              return stmt;
            },
          },
        };
  });

  it('Family Cloud: should create cloud, list members, and assign quotas', async () => {
    const ownerToken = await generateJwt({ sub: 'usr_owner1', email: 'owner@example.com', role: 'admin' }, jwtSecret);

    // 1. Create Family Cloud
    const createReq = new Request('http://localhost/api/v1/family/clouds', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ownerToken}`,
      },
      body: JSON.stringify({ name: 'Shimoga Family Cloud', cloud_type: 'family' }),
    });

    const createRes = await worker.fetch(createReq, mockEnv, ctx);
    expect(createRes.status).toBe(201);
    const createData = (await createRes.json()) as any;
    expect(createData.cloud?.id).toBeDefined();
    expect(createData.cloud?.name).toBe('Shimoga Family Cloud');

    const cloudId = createData.cloud.id;

    // 2. Invite a member
    const inviteReq = new Request('http://localhost/api/v1/family/members/invite', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ownerToken}`,
      },
      body: JSON.stringify({
        cloud_id: cloudId,
        user_id: 'usr_member2',
        role: 'member',
        storage_quota_bytes: 32212254720, // 30 GB
      }),
    });

    const inviteRes = await worker.fetch(inviteReq, mockEnv, ctx);
    expect(inviteRes.status).toBe(200);
    const inviteData = (await inviteRes.json()) as any;
    expect(inviteData.member?.role).toBe('member');
    expect(inviteData.member?.storage_quota_bytes).toBe(32212254720);

    // 3. List Members
    const listReq = new Request(`http://localhost/api/v1/family/members?cloud_id=${cloudId}`, {
      headers: { Authorization: `Bearer ${ownerToken}` },
    });
    const listRes = await worker.fetch(listReq, mockEnv, ctx);
    expect(listRes.status).toBe(200);
    const listData = (await listRes.json()) as any;
    expect(listData.members?.length).toBeGreaterThanOrEqual(1);

    // 4. Update Member Quota
    const memberId = inviteData.member.id;
    const quotaReq = new Request(`http://localhost/api/v1/family/members/${memberId}/quota`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ownerToken}`,
      },
      body: JSON.stringify({ storage_quota_bytes: 53687091200 }),
    });
    const quotaRes = await worker.fetch(quotaReq, mockEnv, ctx);
    expect(quotaRes.status).toBe(200);

    // 5. Delete Member
    const delReq = new Request(`http://localhost/api/v1/family/members/${memberId}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${ownerToken}` },
    });
    const delRes = await worker.fetch(delReq, mockEnv, ctx);
    expect(delRes.status).toBe(200);
  });

  it('Account Recovery: should generate 12-word mnemonic phrase and verify password reset', async () => {
    const ownerToken = await generateJwt({ sub: 'usr_owner1', email: 'owner@example.com', role: 'admin' }, jwtSecret);

    // 1. Generate Emergency Recovery Phrase
    const genReq = new Request('http://localhost/api/v1/auth/recovery/generate', {
      method: 'POST',
      headers: { Authorization: `Bearer ${ownerToken}` },
    });
    const genRes = await worker.fetch(genReq, mockEnv, ctx);
    expect(genRes.status).toBe(200);
    const genData = (await genRes.json()) as any;
    expect(genData.recovery_phrase).toBeDefined();
    expect(genData.recovery_phrase.split(' ').length).toBe(12);

    const phrase = genData.recovery_phrase;

    // 2. Recover Account using phrase and set new password
    const recoverReq = new Request('http://localhost/api/v1/auth/recovery/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'owner@example.com',
        recovery_phrase: phrase,
        new_password: 'RecoveredP@ssword2026!',
      }),
    });
    const recoverRes = await worker.fetch(recoverReq, mockEnv, ctx);
    expect(recoverRes.status).toBe(200);
    const recoverData = (await recoverRes.json()) as any;
    expect(recoverData.success).toBe(true);

    // 3. Second recovery attempt with same phrase should fail (single-use)
    const reuseReq = new Request('http://localhost/api/v1/auth/recovery/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'owner@example.com',
        recovery_phrase: phrase,
        new_password: 'AnotherPassword123!',
      }),
    });
    const reuseRes = await worker.fetch(reuseReq, mockEnv, ctx);
    expect(reuseRes.status).toBe(400);
  });

  it('Storage Policy Engine: should route Photos->SSD, Videos->HDD, Documents->SSD/NAS', async () => {
    const ownerToken = await generateJwt({ sub: 'usr_owner1', email: 'owner@example.com', role: 'admin' }, jwtSecret);

    // 1. Get default storage policies
    const getPoliciesReq = new Request('http://localhost/api/v1/storage/policies', {
      headers: { Authorization: `Bearer ${ownerToken}` },
    });
    const getPoliciesRes = await worker.fetch(getPoliciesReq, mockEnv, ctx);
    expect(getPoliciesRes.status).toBe(200);
    const policiesData = (await getPoliciesRes.json()) as any;
    expect(policiesData.policies?.length).toBeGreaterThanOrEqual(4);

    // 2. Evaluate photo placement -> should route to SSD
    const evalPhotoReq = new Request('http://localhost/api/v1/storage/evaluate', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ownerToken}`,
      },
      body: JSON.stringify({
        name: 'vacation_family.jpg',
        mime_type: 'image/jpeg',
        size_bytes: 4500000,
      }),
    });
    const evalPhotoRes = await worker.fetch(evalPhotoReq, mockEnv, ctx);
    expect(evalPhotoRes.status).toBe(200);
    const photoEval = (await evalPhotoRes.json()) as any;
    expect(photoEval.matched_category).toBe('photos');
    expect(photoEval.target_storage_type).toBe('ssd');
    expect(photoEval.recommended_storage_node_id).toBe('sn_ssd1');

    // 3. Evaluate video placement -> should route to HDD
    const evalVideoReq = new Request('http://localhost/api/v1/storage/evaluate', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ownerToken}`,
      },
      body: JSON.stringify({
        name: '4k_drone_footage.mp4',
        mime_type: 'video/mp4',
        size_bytes: 2500000000,
      }),
    });
    const evalVideoRes = await worker.fetch(evalVideoReq, mockEnv, ctx);
    expect(evalVideoRes.status).toBe(200);
    const videoEval = (await evalVideoRes.json()) as any;
    expect(videoEval.matched_category).toBe('videos');
    expect(videoEval.target_storage_type).toBe('hdd');
    expect(videoEval.recommended_storage_node_id).toBe('sn_hdd1');

    // 4. Create custom high-priority backup policy
    const createPolReq = new Request('http://localhost/api/v1/storage/policies', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ownerToken}`,
      },
      body: JSON.stringify({
        category: 'important_records',
        mime_patterns: 'application/pdf',
        target_storage_type: 'ssd',
        replica_count: 2,
        availability_tier: 'redundant',
        priority: 50,
      }),
    });
    const createPolRes = await worker.fetch(createPolReq, mockEnv, ctx);
    expect(createPolRes.status).toBe(201);
  });

  it('Cluster Protection: should report RPO/RTO metrics and support mode changes', async () => {
    const ownerToken = await generateJwt({ sub: 'usr_owner1', email: 'owner@example.com', role: 'admin' }, jwtSecret);

    // 1. Get cluster status
    const statusReq = new Request('http://localhost/api/v1/cluster/status', {
      headers: { Authorization: `Bearer ${ownerToken}` },
    });
    const statusRes = await worker.fetch(statusReq, mockEnv, ctx);
    expect(statusRes.status).toBe(200);
    const statusData = (await statusRes.json()) as any;
    expect(statusData.protection_mode).toBeDefined();
    expect(statusData.rpo_target_minutes).toBeDefined();
    expect(statusData.rto_target_minutes).toBeDefined();

    // 2. Update cluster protection mode to two_node_protection
    const modeReq = new Request('http://localhost/api/v1/cluster/mode', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ownerToken}`,
      },
      body: JSON.stringify({ protection_mode: 'two_node_protection' }),
    });
    const modeRes = await worker.fetch(modeReq, mockEnv, ctx);
    expect(modeRes.status).toBe(200);
    const modeData = (await modeRes.json()) as any;
    expect(modeData.protection_mode).toBe('two_node_protection');
    expect(modeData.rpo_target_minutes).toBe(15);
    expect(modeData.rto_target_minutes).toBe(5);

    // 3. Trigger rebalance
    const rebalReq = new Request('http://localhost/api/v1/cluster/rebalance', {
      method: 'POST',
      headers: { Authorization: `Bearer ${ownerToken}` },
    });
    const rebalRes = await worker.fetch(rebalReq, mockEnv, ctx);
    expect(rebalRes.status).toBe(200);
  });

  it('Zero-Cost & License Audit: should confirm 100% OSI open source and zero mandatory paid services', async () => {
    const ownerToken = await generateJwt({ sub: 'usr_owner1', email: 'owner@example.com', role: 'admin' }, jwtSecret);

    const auditReq = new Request('http://localhost/api/v1/admin/audit/licenses-quotas', {
      headers: { Authorization: `Bearer ${ownerToken}` },
    });
    const auditRes = await worker.fetch(auditReq, mockEnv, ctx);
    expect(auditRes.status).toBe(200);
    const auditData = (await auditRes.json()) as any;
    expect(auditData.mandatory_paid_dependencies).toBe(0);
    expect(auditData.zero_cost_policy_compliant).toBe(true);
    expect(auditData.self_hosted_oss_alternative).toBeDefined();
    expect(auditData.free_tier_limits.cloudflare_workers_requests_daily).toBe(100000);

    // Migration Export
    const exportReq = new Request('http://localhost/api/v1/admin/export', {
      headers: { Authorization: `Bearer ${ownerToken}` },
    });
    const exportRes = await worker.fetch(exportReq, mockEnv, ctx);
    expect(exportRes.status).toBe(200);
    const exportData = (await exportRes.json()) as any;
    expect(exportData.cloud_export_version).toBe('1.8.0');
    expect(exportData.user?.email).toBe('owner@example.com');
  });
});
