import fs from 'fs';

const words = fs.readFileSync('backend/crates/auth/src/bip39_english.txt', 'utf8')
  .trim()
  .split(/\r?\n/)
  .map(w => w.trim())
  .filter(Boolean);

if (words.length !== 2048) {
  throw new Error(`Expected 2048 words, got ${words.length}`);
}

const tsContent = `// Official Standard BIP-39 English Wordlist (2048 words) and Checksum Implementation
// Conforms to Bitcoin Improvement Proposal 39 (RFC 2898 / BIP-39)

export const BIP39_WORDS: readonly string[] = ${JSON.stringify(words, null, 2)} as const;

const WORD_MAP = new Map<string, number>();
BIP39_WORDS.forEach((w, idx) => WORD_MAP.set(w, idx));

/**
 * Generate a standard BIP-39 12-word mnemonic phrase with 128-bit entropy and 4-bit checksum.
 */
export async function generateBip39Mnemonic(customEntropy?: Uint8Array): Promise<string> {
  const entropy = customEntropy || crypto.getRandomValues(new Uint8Array(16));
  if (entropy.length !== 16) {
    throw new Error('BIP-39 12-word phrase requires exactly 16 bytes (128 bits) of entropy');
  }

  // 128-bit entropy -> SHA-256 -> first 4 bits is checksum
  const hashBuf = await crypto.subtle.digest('SHA-256', entropy);
  const hashBytes = new Uint8Array(hashBuf);
  const checksum = hashBytes[0] >> 4; // Top 4 bits

  // 128 bits entropy + 4 bits checksum = 132 bits = 12 * 11 bits
  const indices: number[] = [];
  let bitBuffer = 0;
  let bitCount = 0;

  for (let i = 0; i < 16; i++) {
    bitBuffer = (bitBuffer << 8) | entropy[i];
    bitCount += 8;
    while (bitCount >= 11) {
      indices.push((bitBuffer >> (bitCount - 11)) & 0x7ff);
      bitCount -= 11;
    }
  }

  // Append 4-bit checksum
  bitBuffer = (bitBuffer << 4) | checksum;
  bitCount += 4;
  indices.push(bitBuffer & 0x7ff);

  return indices.map((idx) => BIP39_WORDS[idx]).join(' ');
}

/**
 * Validate a standard BIP-39 12-word mnemonic phrase, including dictionary lookup and 4-bit checksum.
 */
export async function validateBip39Mnemonic(phrase: string): Promise<{ valid: boolean; error?: string }> {
  const words = phrase.trim().toLowerCase().split(/\\s+/);
  if (words.length !== 12) {
    return { valid: false, error: 'Mnemonic phrase must consist of exactly 12 words' };
  }

  const indices: number[] = [];
  for (const word of words) {
    const idx = WORD_MAP.get(word);
    if (idx === undefined) {
      return { valid: false, error: \`Word '\${word}' is not in the official BIP-39 dictionary\` };
    }
    indices.push(idx);
  }

  // Reconstruct 132 bits: 12 words * 11 bits = 132 bits = 16 bytes (128 bits) + 4 bits checksum
  const entropy = new Uint8Array(16);
  let bitBuffer = 0;
  let bitCount = 0;
  let byteIdx = 0;

  for (let i = 0; i < 11; i++) {
    bitBuffer = (bitBuffer << 11) | indices[i];
    bitCount += 11;
    while (bitCount >= 8 && byteIdx < 16) {
      entropy[byteIdx++] = (bitBuffer >> (bitCount - 8)) & 0xff;
      bitCount -= 8;
    }
  }

  // 12th word contains the last 7 bits of entropy + 4 bits checksum
  const lastWord = indices[11];
  bitBuffer = (bitBuffer << 11) | lastWord;
  bitCount += 11;
  entropy[15] = (bitBuffer >> 4) & 0xff;
  const providedChecksum = bitBuffer & 0x0f;

  // Calculate actual checksum
  const hashBuf = await crypto.subtle.digest('SHA-256', entropy);
  const hashBytes = new Uint8Array(hashBuf);
  const expectedChecksum = hashBytes[0] >> 4;

  if (providedChecksum !== expectedChecksum) {
    return { valid: false, error: 'BIP-39 checksum verification failed: invalid or mistyped phrase' };
  }

  return { valid: true };
}

/**
 * Derive high-security PBKDF2 hash of the mnemonic phrase for safe database storage.
 */
export async function deriveRecoveryHash(phrase: string, salt: string): Promise<string> {
  const enc = new TextEncoder();
  const normalizedPhrase = phrase.trim().toLowerCase();
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    enc.encode(normalizedPhrase),
    { name: 'PBKDF2' },
    false,
    ['deriveBits']
  );

  const derived = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt: enc.encode('pcos_recovery_' + salt),
      iterations: 10000,
      hash: 'SHA-256',
    },
    keyMaterial,
    256
  );

  return Array.from(new Uint8Array(derived))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}
`;

fs.writeFileSync('cloudflare/src/services/bip39.ts', tsContent);
console.log('Successfully wrote cloudflare/src/services/bip39.ts with 2048 BIP-39 words!');
