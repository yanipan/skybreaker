#!/usr/bin/env node
// Cutscene narration: one MP3 per story beat, read straight from CutsceneData.gd
// so the audio never drifts from the captions.
//
//   INWORLD_API_KEY=... node scripts/tools/narration_tts.mjs [--voice Eldrin] [--force] [--only intro]
//
// Output: assets/audio/narration/<image_file>.mp3 (Cutscene.gd plays the file
// that matches the beat's image_file; a missing file just means no voice).
// Cost: ~20 short lines, about $0.02 per full run on inworld-tts-1.5-max.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const DATA = path.join(ROOT, 'scripts', 'CutsceneData.gd');
const OUT = path.join(ROOT, 'assets', 'audio', 'narration');
const KEY = process.env.INWORLD_API_KEY;
if (!KEY) { console.error('INWORLD_API_KEY missing'); process.exit(2); }
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const VOICE = opt('--voice', 'Eldrin');
const ONLY = opt('--only', '');
const FORCE = args.includes('--force');

// _beat("file", "caption", dur) — captions may hold \n and escaped quotes.
const src = fs.readFileSync(DATA, 'utf8');
const beats = [];
const re = /_beat\("([^"]+)",\s*"((?:[^"\\]|\\.)*)"/g;
let m;
while ((m = re.exec(src)) !== null) {
  const text = m[2].replace(/\\n/g, ' ').replace(/\\"/g, '"').replace(/\s+/g, ' ').trim();
  beats.push({ file: m[1], text });
}
console.log(`${beats.length} beats, voice ${VOICE}`);
fs.mkdirSync(OUT, { recursive: true });

async function synth(text) {
  const body = {
    text, voiceId: VOICE, modelId: 'inworld-tts-1.5-max',
    audioConfig: { audioEncoding: 'MP3', sampleRateHertz: 22050 },
    temperature: 0.7, applyTextNormalization: 'ON',
  };
  for (let attempt = 1; attempt <= 3; attempt++) {
    const res = await fetch('https://api.inworld.ai/tts/v1/voice', {
      method: 'POST',
      headers: { Authorization: `Basic ${KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (res.ok) {
      const data = await res.json();
      if (data.audioContent) return Buffer.from(data.audioContent, 'base64');
    }
    console.error(`  attempt ${attempt}: HTTP ${res.status} ${(await res.text()).slice(0, 120)}`);
    await new Promise(r => setTimeout(r, 1000 * attempt));
  }
  throw new Error('synthesis failed');
}

let made = 0;
for (const b of beats) {
  if (ONLY && !b.file.includes(ONLY)) continue;
  const out = path.join(OUT, `${b.file}.mp3`);
  if (fs.existsSync(out) && !FORCE) { console.log(`keep  ${b.file}`); continue; }
  const buf = await synth(b.text);
  fs.writeFileSync(out, buf);
  made++;
  console.log(`wrote ${b.file} (${buf.length} B): ${b.text}`);
  await new Promise(r => setTimeout(r, 300));
}
console.log(`done, ${made} new files in ${path.relative(ROOT, OUT)}`);
