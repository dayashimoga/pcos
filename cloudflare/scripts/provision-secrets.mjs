// Automated Secrets Provisioner for PCOS Cloudflare Control Plane
// Ensures JWT_SECRET is verified or provisioned, with fail-fast validation.

import { execSync } from 'child_process';
import crypto from 'crypto';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

function run(cmd, allowFail = false) {
  try {
    return execSync(cmd, { cwd: rootDir, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (err) {
    if (allowFail) return null;
    throw new Error(`Command failed: ${cmd}\nOutput: ${err.stdout || ''}\nError: ${err.stderr || err.message}`);
  }
}

async function provisionSecrets() {
  console.log('🔒 PCOS Cloudflare Secret Verification & Provisioning starting...');

  const envSecret = process.env.JWT_SECRET || process.env.PCOS_JWT_SECRET;

  if (envSecret && envSecret.trim().length >= 32) {
    console.log('  ➜ Provisioning JWT_SECRET from GitHub/CI Environment secret...');
    try {
      execSync('npx wrangler secret put JWT_SECRET', {
        cwd: rootDir,
        input: envSecret.trim(),
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      console.log('  ✓ Successfully provisioned JWT_SECRET to Cloudflare Worker.');
      return;
    } catch (e) {
      console.error('  ❌ Failed to set JWT_SECRET via wrangler:', e.message);
      throw e;
    }
  }

  // Check if JWT_SECRET already exists on the Worker
  console.log('  🔍 Checking existing secrets on Cloudflare Worker...');
  let hasExistingSecret = false;
  try {
    const listOut = run('npx wrangler secret list', true) || '';
    if (listOut.includes('JWT_SECRET')) {
      hasExistingSecret = true;
      console.log('  ✓ Verified: JWT_SECRET is already configured in Cloudflare Worker secrets.');
      return;
    }
  } catch (e) {
    console.warn('  ⚠️ Could not query existing secrets:', e.message);
  }

  if (!hasExistingSecret) {
    console.log('  ⚡ No JWT_SECRET configured. Generating secure random 256-bit secret...');
    const generated = crypto.randomBytes(32).toString('hex');
    try {
      execSync('npx wrangler secret put JWT_SECRET', {
        cwd: rootDir,
        input: generated,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      console.log('  ✓ Successfully auto-provisioned generated JWT_SECRET (256-bit) to Cloudflare Worker.');
      console.log('  ℹ️ Recommendation: Save this secret to your GitHub Repository Secrets (JWT_SECRET) for consistency.');
    } catch (e) {
      console.error('\n❌ FATAL: Failed to provision JWT_SECRET to Cloudflare Worker.');
      console.error('   Ensure CLOUDFLARE_API_TOKEN has "User - Edit Cloudflare Workers" permissions.\n');
      process.exit(1);
    }
  }
}

provisionSecrets().catch((err) => {
  console.error('\n❌ Secrets verification/provisioning failed:', err.message);
  process.exit(1);
});
