// Lists all apps in the App Store Connect account so you can find the
// Skybreaker ASC app ID after creating the record. Copy the ID into
// scripts/submit/_lib.js (or set SKYBREAKER_ASC_APP_ID env var).
//
// Usage: node scripts/submit/find-asc-app.js

const { ascFetch } = require('./_lib');

(async () => {
  const r = await ascFetch('https://api.appstoreconnect.apple.com/v1/apps?limit=200');
  if (r.status !== 200) {
    console.error('Fetch failed:', r.status, JSON.stringify(r.body).slice(0, 400));
    process.exit(1);
  }
  for (const app of r.body.data || []) {
    const a = app.attributes || {};
    console.log(`${app.id}  ${a.bundleId.padEnd(40)}  ${a.name}`);
  }
})();
