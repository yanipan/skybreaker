#!/usr/bin/env node
/**
 * play-submit.js — Skybreaker → Google Play Console
 *
 * Single-locale (en-US) launch path. Adapted from lomed-english's
 * play-upload-all.js, simplified for Skybreaker's English-only release.
 *
 * Reuses google-play-service-account.json from C:\Users\User\lomed-english\
 * (same Play account; service account email must be invited to the new
 *  Skybreaker app in Play Console first).
 *
 * Usage:
 *   node scripts/submit/play-submit.js --aab=builds/skybreaker.aab
 *   node scripts/submit/play-submit.js --aab=builds/skybreaker.aab --track=internal
 *   node scripts/submit/play-submit.js --aab=builds/skybreaker.aab --skip-aab   # listing only
 */

const fs = require('fs');
const path = require('path');
const { SKYBREAKER_PACKAGE_NAME, PLAY_SA_PATH } = require('./_lib');

const args = process.argv.slice(2);
const argVal = (k, dflt = null) => {
  const a = args.find(x => x.startsWith(`--${k}=`));
  return a ? a.slice(k.length + 3) : dflt;
};
const flag = (k) => args.includes(`--${k}`);

const AAB_PATH = argVal('aab', 'builds/skybreaker.aab');
const TRACK = argVal('track', 'production'); // production | beta | alpha | internal
const SKIP_AAB = flag('skip-aab');
const SKIP_LISTING = flag('skip-listing');
const SKIP_SCREENSHOTS = flag('skip-screenshots');

const COPY_DIR = path.resolve(__dirname, '..', '..', 'docs');
const SHOTS_DIR = path.resolve(__dirname, '..', '..', 'assets', 'store', 'screenshots');

async function initPublisher() {
  if (!fs.existsSync(PLAY_SA_PATH)) {
    console.error(`\nService account JSON not found at: ${PLAY_SA_PATH}`);
    console.error('Set GOOGLE_PLAY_SA_PATH env var if it lives elsewhere.\n');
    process.exit(1);
  }
  let googleapis;
  try { googleapis = require('googleapis'); }
  catch { console.error('\nRun: npm install googleapis\n'); process.exit(1); }
  const auth = new googleapis.google.auth.GoogleAuth({
    keyFile: PLAY_SA_PATH,
    scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  });
  return googleapis.google.androidpublisher({ version: 'v3', auth });
}

function extractCopy() {
  // Parse docs/APP_STORE_COPY.md for the listing text. Falls back to
  // hardcoded values if the markdown can't be parsed (deliberately).
  const md = fs.existsSync(path.join(COPY_DIR, 'APP_STORE_COPY.md'))
    ? fs.readFileSync(path.join(COPY_DIR, 'APP_STORE_COPY.md'), 'utf8')
    : '';
  const block = (label) => {
    const re = new RegExp(`\\*\\*${label.replace(/([().])/g, '\\$1')}[^\\n]*\\*\\*[\\s\\S]*?\`\`\`([\\s\\S]*?)\`\`\``);
    const m = md.match(re);
    return m ? m[1].trim() : null;
  };
  const fullDescBlock = md.match(/## Full description[\s\S]*?```([\s\S]*?)```/);
  const releaseNotes = md.match(/## What's New[\s\S]*?```([\s\S]*?)```/);
  return {
    title: 'Skybreaker',
    shortDescription: block('Play Store short description')
      || "A hand-painted mobile shmup. Answer the signal. Save what's left of humanity.",
    fullDescription: fullDescBlock ? fullDescBlock[1].trim() : null,
    releaseNotes: releaseNotes ? releaseNotes[1].trim() : 'Launch build.',
  };
}

async function uploadScreenshots(publisher, editId) {
  // Phone screenshots from android_phone/, tablet from android_tablet/.
  // Picks first 8 PNGs (Play limit) sorted alphabetically.
  const phoneShots = fs.existsSync(path.join(SHOTS_DIR, 'android_phone'))
    ? fs.readdirSync(path.join(SHOTS_DIR, 'android_phone'))
        .filter(f => f.endsWith('.png') && !f.endsWith('.import'))
        .sort().slice(0, 8)
        .map(f => path.join(SHOTS_DIR, 'android_phone', f))
    : [];
  const tabletShots = fs.existsSync(path.join(SHOTS_DIR, 'android_tablet'))
    ? fs.readdirSync(path.join(SHOTS_DIR, 'android_tablet'))
        .filter(f => f.endsWith('.png') && !f.endsWith('.import'))
        .sort().slice(0, 8)
        .map(f => path.join(SHOTS_DIR, 'android_tablet', f))
    : [];

  for (const [imageType, files] of [
    ['phoneScreenshots', phoneShots],
    ['tenInchScreenshots', tabletShots],
  ]) {
    if (files.length === 0) {
      console.log(`  [${imageType}] no files`);
      continue;
    }
    // Clear existing first
    try {
      await publisher.edits.images.deleteall({
        packageName: SKYBREAKER_PACKAGE_NAME, editId, language: 'en-US', imageType,
      });
    } catch (e) { /* 404 fine */ }

    for (const filePath of files) {
      try {
        await publisher.edits.images.upload({
          packageName: SKYBREAKER_PACKAGE_NAME,
          editId, language: 'en-US', imageType,
          media: { mimeType: 'image/png', body: fs.createReadStream(filePath) },
        });
        console.log(`  [${imageType}] ${path.basename(filePath)}`);
      } catch (e) {
        console.error(`  [${imageType}] ${path.basename(filePath)} FAILED: ${e.message.slice(0, 200)}`);
      }
      await new Promise(r => setTimeout(r, 250));
    }
  }
}

(async () => {
  console.log(`Skybreaker → Play Console (package=${SKYBREAKER_PACKAGE_NAME}, track=${TRACK})`);
  const publisher = await initPublisher();

  const editRes = await publisher.edits.insert({ packageName: SKYBREAKER_PACKAGE_NAME });
  const editId = editRes.data.id;
  console.log(`Edit created: ${editId}`);

  const copy = extractCopy();

  // Listing text
  if (!SKIP_LISTING && (copy.title || copy.shortDescription || copy.fullDescription)) {
    const body = {};
    if (copy.title) body.title = copy.title;
    if (copy.shortDescription) body.shortDescription = copy.shortDescription;
    if (copy.fullDescription) body.fullDescription = copy.fullDescription;
    await publisher.edits.listings.update({
      packageName: SKYBREAKER_PACKAGE_NAME, editId, language: 'en-US', requestBody: body,
    });
    console.log('Listing text updated');
  }

  // Screenshots
  if (!SKIP_SCREENSHOTS) {
    await uploadScreenshots(publisher, editId);
  }

  // AAB upload + release
  if (!SKIP_AAB) {
    if (!fs.existsSync(AAB_PATH)) {
      console.error(`\nAAB not found at: ${AAB_PATH}`);
      console.error('Run scripts/build/4-build-android.ps1 first.\n');
      process.exit(1);
    }
    console.log(`Uploading AAB: ${AAB_PATH} (${(fs.statSync(AAB_PATH).size / 1024 / 1024).toFixed(1)}MB)`);
    const bundleRes = await publisher.edits.bundles.upload({
      packageName: SKYBREAKER_PACKAGE_NAME, editId,
      media: { mimeType: 'application/octet-stream', body: fs.createReadStream(AAB_PATH) },
    });
    const versionCode = bundleRes.data.versionCode;
    console.log(`AAB uploaded: versionCode=${versionCode}`);

    await publisher.edits.tracks.update({
      packageName: SKYBREAKER_PACKAGE_NAME, editId, track: TRACK,
      requestBody: {
        track: TRACK,
        releases: [{
          name: copy.title + ' 1.0.0',
          versionCodes: [String(versionCode)],
          status: TRACK === 'production' ? 'completed' : 'completed',
          releaseNotes: [{ language: 'en-US', text: copy.releaseNotes }],
        }],
      },
    });
    console.log(`Assigned to track: ${TRACK}`);
  }

  // Validate + commit
  await publisher.edits.validate({ packageName: SKYBREAKER_PACKAGE_NAME, editId });
  await publisher.edits.commit({ packageName: SKYBREAKER_PACKAGE_NAME, editId });
  console.log('Edit committed → Play Console');
})().catch(e => {
  console.error('FAILED:', e.message);
  if (e.errors) console.error(JSON.stringify(e.errors, null, 2));
  process.exit(1);
});
