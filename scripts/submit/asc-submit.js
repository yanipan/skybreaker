#!/usr/bin/env node
/**
 * asc-submit.js — Skybreaker → App Store Connect
 *
 * Writes the en-US listing metadata to the Skybreaker ASC app and
 * (optionally) submits the currently-attached build for review.
 *
 * Binary upload itself happens via Xcode → Archive → Distribute on Mac.
 * This script only handles metadata + review submission.
 *
 * Reuses AuthKey_A726RHWTX7.p8 from C:\Users\User\lomed-english\.
 *
 * Prerequisite: SKYBREAKER_ASC_APP_ID env var (or edit _lib.js). Find via:
 *   node scripts/submit/find-asc-app.js
 *
 * Usage:
 *   node scripts/submit/asc-submit.js                    # metadata only
 *   node scripts/submit/asc-submit.js --submit-review    # also submit for review
 */

const fs = require('fs');
const path = require('path');
const { ascFetch, requireSkybreakerAppId } = require('./_lib');

const args = process.argv.slice(2);
const SUBMIT_REVIEW = args.includes('--submit-review');

const COPY_DIR = path.resolve(__dirname, '..', '..', 'docs');

function extractCopy() {
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
  const keywordsBlock = md.match(/## Keywords[\s\S]*?```([\s\S]*?)```/);
  return {
    name: 'Skybreaker',
    subtitle: block('App Store subtitle') || 'One pilot. Forty years silent.',
    description: fullDescBlock ? fullDescBlock[1].trim() : null,
    keywords: keywordsBlock ? keywordsBlock[1].trim() : null,
    releaseNotes: releaseNotes ? releaseNotes[1].trim() : 'Launch build.',
    supportUrl: 'https://yanipan.github.io/skybreaker/privacy.html',
    marketingUrl: 'https://yanipan.github.io/skybreaker/',
  };
}

(async () => {
  const appId = requireSkybreakerAppId();
  const copy = extractCopy();

  console.log(`Skybreaker → ASC (appId=${appId})`);

  // Find the editable (PREPARE_FOR_SUBMISSION) appStoreVersion
  const versionsRes = await ascFetch(
    `https://api.appstoreconnect.apple.com/v1/apps/${appId}/appStoreVersions?filter[platform]=IOS&limit=10`
  );
  if (versionsRes.status !== 200) {
    console.error('Failed to list versions:', versionsRes.status, JSON.stringify(versionsRes.body).slice(0, 400));
    process.exit(1);
  }
  const editable = (versionsRes.body.data || []).find(v =>
    ['PREPARE_FOR_SUBMISSION', 'METADATA_REJECTED', 'REJECTED', 'DEVELOPER_REJECTED', 'WAITING_FOR_REVIEW'].includes(v.attributes.appStoreState)
  );
  if (!editable) {
    console.error('No editable appStoreVersion found. Create version 1.0.0 in ASC first.');
    console.error('Existing versions:', versionsRes.body.data?.map(v => `${v.attributes.versionString} (${v.attributes.appStoreState})`).join(', '));
    process.exit(1);
  }
  console.log(`Editing version: ${editable.attributes.versionString} (${editable.attributes.appStoreState})`);

  // Update appStoreVersion (release notes, etc.)
  if (copy.releaseNotes) {
    const r = await ascFetch(`https://api.appstoreconnect.apple.com/v1/appStoreVersions/${editable.id}`, {
      method: 'PATCH',
      body: JSON.stringify({
        data: {
          type: 'appStoreVersions',
          id: editable.id,
          attributes: { copyright: '2026 Yaniv Shimony' },
        },
      }),
    });
    if (r.status >= 300) console.error('Version PATCH:', r.status, JSON.stringify(r.body).slice(0, 300));
  }

  // Update the en-US localization
  const locRes = await ascFetch(
    `https://api.appstoreconnect.apple.com/v1/appStoreVersions/${editable.id}/appStoreVersionLocalizations`
  );
  const enLoc = (locRes.body.data || []).find(l => l.attributes.locale === 'en-US');
  if (!enLoc) {
    console.error('en-US localization not found on version.');
    process.exit(1);
  }
  const attrs = {};
  if (copy.description) attrs.description = copy.description;
  if (copy.keywords) attrs.keywords = copy.keywords;
  if (copy.subtitle) attrs.promotionalText = null; // leave blank initially
  if (copy.releaseNotes) attrs.whatsNew = copy.releaseNotes;
  if (copy.supportUrl) attrs.supportUrl = copy.supportUrl;
  if (copy.marketingUrl) attrs.marketingUrl = copy.marketingUrl;

  const lr = await ascFetch(
    `https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/${enLoc.id}`,
    {
      method: 'PATCH',
      body: JSON.stringify({
        data: { type: 'appStoreVersionLocalizations', id: enLoc.id, attributes: attrs },
      }),
    }
  );
  if (lr.status >= 300) {
    console.error('Localization PATCH failed:', lr.status, JSON.stringify(lr.body).slice(0, 400));
    process.exit(1);
  }
  console.log('en-US localization updated');

  // Update app-level info (name, subtitle live on appInfoLocalizations, not version)
  const infoRes = await ascFetch(
    `https://api.appstoreconnect.apple.com/v1/apps/${appId}/appInfos?limit=10`
  );
  const editableInfo = (infoRes.body.data || []).find(i =>
    ['PREPARE_FOR_SUBMISSION', 'REPLACED_WITH_NEW_INFO'].includes(i.attributes.state)
  );
  if (editableInfo) {
    const infoLocRes = await ascFetch(
      `https://api.appstoreconnect.apple.com/v1/appInfos/${editableInfo.id}/appInfoLocalizations`
    );
    const enInfoLoc = (infoLocRes.body.data || []).find(l => l.attributes.locale === 'en-US');
    if (enInfoLoc) {
      const ilr = await ascFetch(
        `https://api.appstoreconnect.apple.com/v1/appInfoLocalizations/${enInfoLoc.id}`,
        {
          method: 'PATCH',
          body: JSON.stringify({
            data: {
              type: 'appInfoLocalizations',
              id: enInfoLoc.id,
              attributes: {
                name: copy.name,
                subtitle: copy.subtitle,
                privacyPolicyUrl: 'https://yanipan.github.io/skybreaker/privacy.html',
              },
            },
          }),
        }
      );
      if (ilr.status >= 300) {
        console.error('AppInfo localization PATCH:', ilr.status, JSON.stringify(ilr.body).slice(0, 400));
      } else {
        console.log('App-level name/subtitle/privacyPolicyUrl updated');
      }
    }
  }

  if (SUBMIT_REVIEW) {
    const sr = await ascFetch('https://api.appstoreconnect.apple.com/v1/reviewSubmissions', {
      method: 'POST',
      body: JSON.stringify({
        data: {
          type: 'reviewSubmissions',
          attributes: { platform: 'IOS' },
          relationships: { app: { data: { type: 'apps', id: appId } } },
        },
      }),
    });
    if (sr.status >= 300) {
      console.error('reviewSubmissions POST failed:', sr.status, JSON.stringify(sr.body).slice(0, 400));
      process.exit(1);
    }
    const submissionId = sr.body.data.id;
    console.log(`Review submission created: ${submissionId}`);

    // Add the version as an item to the submission
    const ir = await ascFetch('https://api.appstoreconnect.apple.com/v1/reviewSubmissionItems', {
      method: 'POST',
      body: JSON.stringify({
        data: {
          type: 'reviewSubmissionItems',
          relationships: {
            reviewSubmission: { data: { type: 'reviewSubmissions', id: submissionId } },
            appStoreVersion: { data: { type: 'appStoreVersions', id: editable.id } },
          },
        },
      }),
    });
    if (ir.status >= 300) {
      console.error('reviewSubmissionItems POST failed:', ir.status, JSON.stringify(ir.body).slice(0, 400));
      process.exit(1);
    }

    const cr = await ascFetch(
      `https://api.appstoreconnect.apple.com/v1/reviewSubmissions/${submissionId}`,
      {
        method: 'PATCH',
        body: JSON.stringify({
          data: {
            type: 'reviewSubmissions',
            id: submissionId,
            attributes: { submitted: true },
          },
        }),
      }
    );
    if (cr.status >= 300) {
      console.error('Submit (PATCH submitted=true) failed:', cr.status, JSON.stringify(cr.body).slice(0, 400));
      process.exit(1);
    }
    console.log('Submitted for review');
  }
})().catch(e => {
  console.error('FAILED:', e.message);
  process.exit(1);
});
