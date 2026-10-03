// Automated Cloudflare Resource Provisioner for PCOS
// Automatically provisions D1 Database, applies schema.sql, creates KV namespace,
// creates R2 bucket, and binds Durable Objects.

import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const configPath = path.join(rootDir, 'wrangler.jsonc');
const schemaPath = path.join(rootDir, 'schema.sql');

const assetsPath = path.resolve(rootDir, '../frontend/build/web');

function run(cmd, allowFail = false) {
  try {
    return execSync(cmd, { cwd: rootDir, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (err) {
    if (allowFail) return null;
    throw new Error(`Command failed: ${cmd}\nOutput: ${err.stdout || ''}\nError: ${err.stderr || err.message}`);
  }
}

async function provision() {
  console.log('⚡ PCOS Cloudflare Automated Provisioning starting...');

  // Ensure assets directory exists for wrangler binding
  if (!fs.existsSync(assetsPath)) {
    console.log(`📁 Creating placeholder assets directory: ${assetsPath}`);
    fs.mkdirSync(assetsPath, { recursive: true });
    fs.writeFileSync(
      path.join(assetsPath, 'index.html'),
      '<!DOCTYPE html><html><head><title>PCOS Cloud</title></head><body><h1>PCOS Personal Cloud OS</h1></body></html>',
      'utf8'
    );
  }

  // 1. D1 Database Provisioning
  console.log('\n📦 Checking D1 Database (pcos-control-db)...');
  let d1Id = null;
  const d1ListOut = run('npx wrangler d1 list --json', true);
  if (d1ListOut) {
    try {
      const list = JSON.parse(d1ListOut);
      const existing = list.find((db) => db.name === 'pcos-control-db');
      if (existing) {
        d1Id = existing.uuid;
        console.log(`  ✓ Found existing D1 Database: ${d1Id}`);
      }
    } catch (_) {}
  }

  if (!d1Id) {
    console.log('  ➜ Creating D1 database "pcos-control-db"...');
    const createOut = run('npx wrangler d1 create pcos-control-db --json', true);
    if (createOut) {
      try {
        const parsed = JSON.parse(createOut);
        d1Id = parsed.uuid || parsed.database_id;
      } catch (_) {}
    }
    if (!d1Id) {
      // Fallback to text parsing
      const txtOut = run('npx wrangler d1 create pcos-control-db', true) || '';
      const match = txtOut.match(/database_id\s*=\s*"([^"]+)"/) || txtOut.match(/([a-f0-9-]{36})/i);
      if (match) d1Id = match[1];
    }
    if (d1Id) {
      console.log(`  ✓ Successfully created D1 Database: ${d1Id}`);
    } else {
      console.warn('  ⚠️ D1 creation output could not be parsed; using configured or fallback ID.');
    }
  }

  // 2. D1 Schema Migration Execution
  if (fs.existsSync(schemaPath)) {
    console.log('\n📄 Executing schema.sql on D1 (remote)...');
    try {
      run('npx wrangler d1 execute pcos-control-db --file=./schema.sql --remote --yes');
      console.log('  ✓ Database schema applied successfully');
    } catch (e) {
      console.warn(`  ⚠️ Schema migration returned: ${e.message}`);
    }
  }

  // 3. KV Namespace Provisioning
  console.log('\n🔑 Checking KV Namespace (CONFIG_KV)...');
  let kvId = null;
  const kvListOut = run('npx wrangler kv namespace list', true);
  if (kvListOut) {
    try {
      const list = JSON.parse(kvListOut);
      const existing = list.find((kv) => kv.title && kv.title.includes('CONFIG_KV'));
      if (existing) {
        kvId = existing.id;
        console.log(`  ✓ Found existing KV Namespace: ${kvId}`);
      }
    } catch (_) {}
  }

  if (!kvId) {
    console.log('  ➜ Creating KV namespace "CONFIG_KV"...');
    const createKvOut = run('npx wrangler kv namespace create CONFIG_KV', true) || '';
    const kvMatch = createKvOut.match(/id\s*=\s*"([^"]+)"/) || createKvOut.match(/([a-f0-9]{32})/i);
    if (kvMatch) {
      kvId = kvMatch[1];
      console.log(`  ✓ Successfully created KV Namespace: ${kvId}`);
    } else {
      console.warn('  ⚠️ KV creation output could not be parsed; continuing.');
    }
  }

  // 4. R2 Bucket Provisioning (Optional Cloud Cache)
  console.log('\n🪣 Checking R2 Bucket (pcos-cloud-cache)...');
  let hasR2 = false;
  try {
    const listOut = run('npx wrangler r2 bucket list', true) || '';
    if (listOut.includes('pcos-cloud-cache')) {
      hasR2 = true;
      console.log('  ✓ Found existing R2 Bucket "pcos-cloud-cache"');
    } else {
      console.log('  ➜ Attempting to create R2 bucket "pcos-cloud-cache"...');
      run('npx wrangler r2 bucket create pcos-cloud-cache', true);
      const verifyOut = run('npx wrangler r2 bucket list', true) || '';
      if (verifyOut.includes('pcos-cloud-cache')) {
        hasR2 = true;
        console.log('  ✓ Successfully created and verified R2 Bucket "pcos-cloud-cache"');
      }
    }
  } catch (_) {}

  if (!hasR2) {
    console.log('  ℹ️ R2 is not enabled on this Cloudflare account or API token lacks R2 permissions.');
    console.log('  ℹ️ PCOS will operate without cloud cache (100% user-owned storage nodes, zero cloud fees).');
  }

  // 5. Update wrangler.jsonc with real IDs and active bindings
  if (fs.existsSync(configPath)) {
    let configContent = fs.readFileSync(configPath, 'utf8');
    if (d1Id) {
      configContent = configContent.replace(
        /"database_id":\s*"[^"]*"/,
        `"database_id": "${d1Id}"`
      );
    }
    if (kvId) {
      configContent = configContent.replace(
        /"id":\s*"pcos-config-kv-[^"]*"/,
        `"id": "${kvId}"`
      );
    }
    if (hasR2) {
      if (!configContent.includes('"binding": "CACHE_R2"')) {
        configContent = configContent.replace(
          /"vars":/,
          `"r2_buckets": [\n    {\n      "binding": "CACHE_R2",\n      "bucket_name": "pcos-cloud-cache"\n    }\n  ],\n\n  "vars":`
        );
        console.log('  ✓ Bound active R2 bucket "pcos-cloud-cache" to CACHE_R2 in wrangler.jsonc');
      }
    } else {
      if (configContent.includes('"binding": "CACHE_R2"')) {
        configContent = configContent.replace(
          /\s*"r2_buckets":\s*\[[\s\S]*?\]\s*,?/,
          ''
        );
        console.log('  ✓ Cleaned r2_buckets from wrangler.jsonc to prevent deployment errors');
      }
    }
    fs.writeFileSync(configPath, configContent, 'utf8');
    console.log('\n📝 Updated wrangler.jsonc with active Cloudflare resource bindings');
  }

  console.log('\n✅ PCOS Cloudflare Provisioning Complete!\n');
}

provision().catch((err) => {
  console.error('\n❌ Provisioning failed:', err.message);
  process.exit(1);
});
