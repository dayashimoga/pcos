// Types and Provider Abstractions for PCOS Edge Control Plane

export interface Env {
  DB: D1Database;
  PAIRING_HUB: DurableObjectNamespace;
  PRESENCE_HUB: DurableObjectNamespace;
  CONFIG_KV: KVNamespace;
  CACHE_R2?: R2Bucket;
  ASSETS?: Fetcher;

  // Environment variables
  PCOS_ENV: string;
  PCOS_CONTROL_VERSION: string;
  FREE_TIER_HARD_BUDGET: string;
  MAX_R2_STORAGE_GB: string;
  MAX_WORKERS_PER_DAY: string;
  MAX_D1_WRITES_PER_DAY: string;
  MAX_D1_READS_PER_MONTH: string;
  JWT_SECRET?: string;
}

export interface User {
  id: string;
  email: string;
  password_hash: string;
  display_name: string;
  role: string;
  quota_bytes: number;
  used_bytes: number;
  created_at: string;
  updated_at: string;
}

export interface DeviceIdentity {
  id: string;
  user_id: string;
  cloud_id: string;
  name: string;
  device_type: 'desktop' | 'laptop' | 'phone' | 'tablet' | 'nas' | 'tv' | 'web';
  os: string;
  os_version: string;
  agent_version: string;
  public_key?: string;
  is_online: boolean;
  last_seen_at?: string;
  last_lan_ip?: string;
  wireguard_pubkey?: string;
  relay_endpoint?: string;
  created_at: string;
  updated_at: string;
}

export interface StorageNode {
  id: string;
  device_id: string;
  user_id: string;
  name: string;
  storage_path: string;
  total_capacity_bytes: number;
  available_capacity_bytes: number;
  is_online: boolean;
  capabilities: {
    ffmpeg: boolean;
    ocr: boolean;
    tantivy: boolean;
    ollama: boolean;
  };
  created_at: string;
  updated_at: string;
}

export interface FileLocation {
  file_id: string;
  user_id: string;
  storage_node_id: string;
  relative_path: string;
  file_name: string;
  file_size: number;
  mime_type: string;
  sha256_checksum: string;
  replication_policy: 'device_only' | 'any_device' | 'always_available_remote' | 'redundant_copy' | 'archive';
  r2_cached_key?: string;
  r2_cached_size?: number;
  created_at: string;
  updated_at: string;
}

export interface PairingSessionData {
  id: string;
  user_id: string;
  pairing_code: string;
  enrollment_token: string;
  status: 'pending_redeem' | 'pending_approval' | 'approved' | 'rejected' | 'expired';
  failed_attempts: number;
  candidate_device?: {
    device_name: string;
    device_type: string;
    os: string;
    os_version?: string;
    agent_version?: string;
    client_fingerprint?: string;
    requested_at: string;
  };
  expires_at: string;
  created_at: string;
}

export interface FreeTierUsage {
  date_key: string;
  worker_requests: number;
  d1_reads: number;
  d1_writes: number;
  do_requests: number;
  r2_storage_bytes: number;
  updated_at: string;
}

export interface BudgetStatus {
  worker_requests: { used: number; limit: number; pct: number };
  d1_reads: { used: number; limit: number; pct: number };
  d1_writes: { used: number; limit: number; pct: number };
  do_requests: { used: number; limit: number; pct: number };
  r2_storage_gb: { used: number; limit: number; pct: number };
  hard_budget_enabled: boolean;
  estimated_cost: number;
  is_near_limit: boolean;
  cloud_cache_active: boolean;
}

// ─── Provider Abstraction Interfaces ───
// Ensures PCOS can run on Cloudflare, on self-hosted Rust gateways, or on other clouds without lock-in.

export interface IControlPlaneProvider {
  registerDevice(device: Partial<DeviceIdentity>): Promise<DeviceIdentity>;
  resolveRoute(deviceId: string): Promise<{
    is_online: boolean;
    lan_ip?: string;
    wireguard_pubkey?: string;
    relay_endpoint?: string;
    recommended_route: 'LAN' | 'P2P' | 'Relay' | 'Offline';
  }>;
  getBudgetStatus(): Promise<BudgetStatus>;
}

export interface IPairingBroker {
  createSession(userId: string, ttlSeconds: number): Promise<PairingSessionData>;
  claimSession(key: string, candidate: NonNullable<PairingSessionData['candidate_device']>): Promise<PairingSessionData>;
  approveSession(userId: string, key: string, approved: boolean): Promise<PairingSessionData>;
  getStatus(key: string): Promise<PairingSessionData>;
}

export interface IPresenceBroker {
  recordHeartbeat(deviceId: string, lanIp?: string): Promise<void>;
  broadcastCommand(targetDeviceId: string, command: string, payload: unknown): Promise<void>;
}
