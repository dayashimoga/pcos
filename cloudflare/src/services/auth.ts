// Cryptographic and Authentication Utilities for Edge Control Plane
// Uses standard WebCrypto APIs (supported on Cloudflare Workers, Node, Browser)

export async function hashPassword(password: string): Promise<string> {
  const enc = new TextEncoder();
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    enc.encode(password),
    { name: 'PBKDF2' },
    false,
    ['deriveBits', 'deriveKey']
  );

  const derivedKey = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt,
      iterations: 100000,
      hash: 'SHA-256',
    },
    keyMaterial,
    256
  );

  const saltHex = Array.from(salt)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  const hashHex = Array.from(new Uint8Array(derivedKey))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  return `pbkdf2$100000$${saltHex}$${hashHex}`;
}

export async function verifyPassword(
  password: string,
  storedHash: string
): Promise<boolean> {
  const parts = storedHash.split('$');
  if (parts.length !== 4 || parts[0] !== 'pbkdf2') {
    return false;
  }

  const iterations = parseInt(parts[1], 10);
  const saltHex = parts[2];
  const expectedHashHex = parts[3];

  const salt = new Uint8Array(
    saltHex.match(/.{1,2}/g)?.map((byte) => parseInt(byte, 16)) || []
  );

  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    enc.encode(password),
    { name: 'PBKDF2' },
    false,
    ['deriveBits', 'deriveKey']
  );

  const derivedKey = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt,
      iterations,
      hash: 'SHA-256',
    },
    keyMaterial,
    256
  );

  const actualHash = new Uint8Array(derivedKey);
  const expectedBytes = new Uint8Array(
    expectedHashHex.match(/.{1,2}/g)?.map((byte) => parseInt(byte, 16)) || []
  );

  // Constant-time comparison to prevent timing side-channel attacks
  if (actualHash.length !== expectedBytes.length) return false;
  let diff = 0;
  for (let i = 0; i < actualHash.length; i++) {
    diff |= actualHash[i] ^ expectedBytes[i];
  }
  return diff === 0;
}

export async function generateJwt(
  payload: Record<string, unknown>,
  secret: string,
  expiresInSeconds: number
): Promise<string> {
  const enc = new TextEncoder();
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const fullPayload = {
    ...payload,
    iat: now,
    exp: now + expiresInSeconds,
  };

  const b64Header = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const b64Payload = base64UrlEncode(enc.encode(JSON.stringify(fullPayload)));
  const data = `${b64Header}.${b64Payload}`;

  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const signature = await crypto.subtle.sign('HMAC', key, enc.encode(data));
  const b64Sig = base64UrlEncode(new Uint8Array(signature));

  return `${data}.${b64Sig}`;
}

export async function verifyJwt(
  token: string,
  secret: string
): Promise<Record<string, unknown> | null> {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    const [b64Header, b64Payload, b64Sig] = parts;
    const data = `${b64Header}.${b64Payload}`;
    const enc = new TextEncoder();

    const key = await crypto.subtle.importKey(
      'raw',
      enc.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    );

    const sig = base64UrlDecode(b64Sig);
    const valid = await crypto.subtle.verify('HMAC', key, sig, enc.encode(data));
    if (!valid) return null;

    const payloadStr = new TextDecoder().decode(base64UrlDecode(b64Payload));
    const payload = JSON.parse(payloadStr) as Record<string, unknown>;

    const now = Math.floor(Date.now() / 1000);
    if (typeof payload.exp === 'number' && payload.exp < now) {
      return null; // Expired
    }

    return payload;
  } catch {
    return null;
  }
}

export function generatePairingCode(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  const num = buf[0] % 1000000;
  return num.toString().padStart(6, '0');
}

export function generateEnrollmentToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// ─── RFC 6238 Standard TOTP (Google Authenticator, Authy, Apple Keychain compatible) ───
const RFC3548_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function generateTotpSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32)); // 32 base32 characters
  let secret = '';
  for (let i = 0; i < bytes.length; i++) {
    secret += RFC3548_ALPHABET[bytes[i] % 32];
  }
  return secret;
}

export function base32ToBytes(base32: string): Uint8Array {
  const clean = base32.toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = '';
  for (let i = 0; i < clean.length; i++) {
    const val = RFC3548_ALPHABET.indexOf(clean[i]);
    if (val === -1) continue;
    bits += val.toString(2).padStart(5, '0');
  }
  const bytes = new Uint8Array(Math.floor(bits.length / 8));
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(bits.slice(i * 8, (i + 1) * 8), 2);
  }
  return bytes;
}

export async function computeTotp(secretBase32: string, timeStep: number): Promise<string> {
  const keyBytes = base32ToBytes(secretBase32);
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign']
  );

  const counterBuf = new ArrayBuffer(8);
  const counterView = new DataView(counterBuf);
  // High 32-bits (for standard Unix timestamps < 2038 this is 0)
  counterView.setUint32(0, Math.floor(timeStep / 0x100000000), false);
  counterView.setUint32(4, timeStep >>> 0, false);

  const sig = await crypto.subtle.sign('HMAC', key, counterBuf);
  const hash = new Uint8Array(sig);

  const offset = hash[hash.length - 1] & 0x0f;
  const binary =
    ((hash[offset] & 0x7f) << 24) |
    ((hash[offset + 1] & 0xff) << 16) |
    ((hash[offset + 2] & 0xff) << 8) |
    (hash[offset + 3] & 0xff);

  const otp = (binary % 1000000).toString().padStart(6, '0');
  return otp;
}

export async function verifyTotpCode(
  secretBase32: string,
  code: string,
  windowSteps = 1
): Promise<boolean> {
  if (!secretBase32 || !code) return false;
  const cleanCode = code.trim().replace(/\s+/g, '');
  if (cleanCode.length !== 6 || !/^\d{6}$/.test(cleanCode)) return false;

  const currentStep = Math.floor(Date.now() / 1000 / 30);
  for (let stepOffset = -windowSteps; stepOffset <= windowSteps; stepOffset++) {
    const expected = await computeTotp(secretBase32, currentStep + stepOffset);
    if (expected === cleanCode) {
      return true;
    }
  }
  return false;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function base64UrlDecode(str: string): Uint8Array {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) {
    base64 += '=';
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
