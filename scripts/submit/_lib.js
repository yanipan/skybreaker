// Shared ASC + Play helpers for Skybreaker submission scripts.
// Reuses the same Apple Developer team + Google Play service account as
// the Lomed English app — only the per-app IDs differ.
//
// Credentials live in C:\Users\User\lomed-english\ and are referenced
// here without being copied. Override with env vars if you move them.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// --- Apple Developer team-level (same as Lomed) ---
const KEY_ID = 'A726RHWTX7';
const ISSUER_ID = 'f2fcaeb1-4500-4e62-89bc-83d05e013db3';
const KEY_PATH = process.env.ASC_KEY_PATH
  || 'C:/Users/User/lomed-english/AuthKey_A726RHWTX7.p8';

// --- Skybreaker-specific (FILL IN after ASC record + Play app are created) ---
const SKYBREAKER_ASC_APP_ID = process.env.SKYBREAKER_ASC_APP_ID || '';
const SKYBREAKER_PACKAGE_NAME = 'com.origami.skybreaker';

// --- Play Console service account (same as Lomed) ---
const PLAY_SA_PATH = process.env.GOOGLE_PLAY_SA_PATH
  || 'C:/Users/User/lomed-english/google-play-service-account.json';

const b64 = (b) => Buffer.from(b).toString('base64')
  .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

function jwt() {
  if (!fs.existsSync(KEY_PATH)) {
    throw new Error(`ASC key missing at ${KEY_PATH}`);
  }
  const now = Math.floor(Date.now() / 1000);
  const h = b64(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' }));
  const p = b64(JSON.stringify({
    iss: ISSUER_ID, iat: now, exp: now + 20 * 60, aud: 'appstoreconnect-v1',
  }));
  const sig = crypto.createSign('SHA256').update(`${h}.${p}`).sign({
    key: fs.readFileSync(KEY_PATH), dsaEncoding: 'ieee-p1363',
  });
  return `${h}.${p}.${b64(sig)}`;
}

async function ascFetch(url, opts = {}) {
  const res = await fetch(url, {
    ...opts,
    headers: {
      Authorization: `Bearer ${jwt()}`,
      'Content-Type': 'application/json',
      ...(opts.headers || {}),
    },
  });
  const text = await res.text();
  let parsed = null;
  try { parsed = JSON.parse(text); } catch {}
  return { status: res.status, body: parsed || text };
}

function requireSkybreakerAppId() {
  if (!SKYBREAKER_ASC_APP_ID) {
    throw new Error(
      'SKYBREAKER_ASC_APP_ID not set. After creating the ASC record, ' +
      'find the app ID in the URL (e.g. apps/6762269706/...) and either ' +
      'set the env var or edit scripts/submit/_lib.js.'
    );
  }
  return SKYBREAKER_ASC_APP_ID;
}

module.exports = {
  jwt,
  ascFetch,
  requireSkybreakerAppId,
  SKYBREAKER_PACKAGE_NAME,
  PLAY_SA_PATH,
};
