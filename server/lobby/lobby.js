#!/usr/bin/env node
// Skybreaker co-op LOBBY SERVICE (docs/MULTIPLAYER_PLAN.md, "Finding a partner").
// No dependencies. It hands out room codes, matches "Play now" players and
// starts one headless Godot room server per room; it never touches gameplay.
//
//   node server/lobby/lobby.js
// Environment:
//   LOBBY_PORT      HTTP port (default 24600)
//   PUBLIC_HOST     address phones use to reach the ROOM servers (default 127.0.0.1)
//   GODOT           Godot binary (default: the macOS app path)
//   PROJECT         game project directory (default: two levels up)
//   ROOM_PORT_MIN / ROOM_PORT_MAX   UDP port pool for rooms (default 24800-24839)
//   MAX_ROOMS       rooms alive at once (default 8)
//   SB_SIG_KEY      shared secret: requests must carry X-SB-Ts and
//                   X-SB-Sig = HMAC-SHA256(key, ts + "." + body). Unset = NOT checked (dev only).
//   QUICK_WAIT_MS   how long a Play-now player may wait for a human (default 10000)
//   REQ_PER_MIN     requests per minute from one address (default 600: mobile carriers put
//                   many phones behind one address, so this is only a flood guard)
//   JOIN_PER_MIN    join-by-code attempts per minute from one address (default 20: with
//                   887 million possible codes and a handful of rooms, guessing is hopeless)
//   ROOM_EXTRA_ARGS extra arguments for every room server (tests only, e.g. "--sectors=1 --duration_mul=0.3")
//
// API (POST, JSON in and out):
//   /v1/room/create  {proto, player_id}        -> {ok, code, host, port}
//   /v1/room/join    {proto, code}             -> {ok, host, port} | {ok:false, error}
//   /v1/quick        {proto, player_id}        -> {ok, matched:true, host, port} | {ok, matched:false, waited_ms}
//   /v1/quick/cancel {player_id}               -> {ok}
//   GET /health                                -> {ok, rooms, waiting}
// Errors: bad_request, bad_signature, rate_limited, version, not_found, started, busy.
'use strict';
const http = require('http');
const crypto = require('crypto');
const path = require('path');
const { spawn } = require('child_process');

const PORT = parseInt(process.env.LOBBY_PORT || '24600', 10);
const PUBLIC_HOST = process.env.PUBLIC_HOST || '127.0.0.1';
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const PROJECT = process.env.PROJECT || path.resolve(__dirname, '..', '..');
// On the server the room runs from an exported pack (Linux Server preset): GODOT is the exported binary, ROOM_PACK its .pck.
const ROOM_PACK = process.env.ROOM_PACK || '';
const PORT_MIN = parseInt(process.env.ROOM_PORT_MIN || '24800', 10);
const PORT_MAX = parseInt(process.env.ROOM_PORT_MAX || '24839', 10);
const MAX_ROOMS = parseInt(process.env.MAX_ROOMS || '8', 10);
const SIG_KEY = process.env.SB_SIG_KEY || '';
const QUICK_WAIT_MS = parseInt(process.env.QUICK_WAIT_MS || '10000', 10);
// BOT_FILL=0 turns the AI partner off (Play now then ends in "nobody found").
const BOT_FILL = (process.env.BOT_FILL || '1') !== '0';
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';   // no 0 O 1 I L
const CODE_TTL_MS = 10 * 60 * 1000;
const REQ_PER_MIN = parseInt(process.env.REQ_PER_MIN || '600', 10);
const JOIN_PER_MIN = parseInt(process.env.JOIN_PER_MIN || '20', 10);
const MAX_BODY = 2048;
const TS_WINDOW_S = 300;

const rooms = new Map();      // code -> room
const waiting = new Map();    // player_id -> {proto, since, seen, room}
const hits = new Map();       // ip -> {t0, n, joins}

function log(...a) { console.log(new Date().toISOString().slice(11, 19), ...a); }

function newCode() {
  for (let tries = 0; tries < 50; tries++) {
    const b = crypto.randomBytes(6);
    let c = '';
    for (let i = 0; i < 6; i++) c += CODE_ALPHABET[b[i] % CODE_ALPHABET.length];
    if (!rooms.has(c)) return c;
  }
  return null;
}

function freePort() {
  const used = new Set([...rooms.values()].map(r => r.port));
  for (let p = PORT_MIN; p <= PORT_MAX; p++) if (!used.has(p)) return p;
  return 0;
}

// One headless Godot process = one room. Its stdout tells us how full it is
// and when the run starts (the code is retired then).
function startRoom(proto, kind, bots = 0) {
  if (rooms.size >= MAX_ROOMS) return null;
  const port = freePort();
  const code = newCode();
  if (!port || !code) return null;
  const args = ['--headless', ...(ROOM_PACK ? ['--main-pack', ROOM_PACK] : ['--path', PROJECT]), 'res://scenes/net/ServerWorld.tscn', '--',
    `--port=${port}`, '--players=2', '--sector=1', `--room=${code}`];
  // A matched room that does not fill fast is abandoned fast; a friend room waits for the code's lifetime.
  args.push(kind === 'quick' ? '--lobby_timeout=45' : '--lobby_timeout=600');
  if (bots > 0) args.push(`--bots=${bots}`);   // an AI partner takes the second seat
  if (process.env.ROOM_EXTRA_ARGS) args.push(...process.env.ROOM_EXTRA_ARGS.split(' ').filter(Boolean));   // tests only
  const child = spawn(GODOT, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  const room = { code, port, proto, kind, bots, child, created: Date.now(), joined: 0, started: false };
  rooms.set(code, room);
  let buf = '';
  child.stdout.on('data', d => {
    buf += d.toString();
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i); buf = buf.slice(i + 1);
      const m = line.match(/ServerWorld: lobby (\d+)\/(\d+)/);
      if (m) room.joined = parseInt(m[1], 10);
      if (/ServerWorld: sector \d+ start/.test(line) && !room.started) { room.started = true; log('room', code, 'run started'); }
    }
  });
  child.stderr.on('data', () => {});
  child.on('exit', (c) => { rooms.delete(code); log('room', code, 'closed, exit', c, '| rooms', rooms.size); });
  child.on('error', (e) => { rooms.delete(code); log('room', code, 'spawn error', e.message); });
  log('room', code, kind, bots > 0 ? 'with AI partner' : '', 'on port', port, '| rooms', rooms.size);
  return room;
}

function closeRoom(room) {
  try { room.child.kill(); } catch (e) { /* already gone */ }
}

function verify(req, raw) {
  if (!SIG_KEY) return true;
  const ts = String(req.headers['x-sb-ts'] || '');
  const sig = String(req.headers['x-sb-sig'] || '');
  if (!/^\d{9,11}$/.test(ts) || !/^[0-9a-f]{64}$/.test(sig)) return false;
  if (Math.abs(Date.now() / 1000 - parseInt(ts, 10)) > TS_WINDOW_S) return false;
  const want = crypto.createHmac('sha256', SIG_KEY).update(ts + '.' + raw).digest('hex');
  return crypto.timingSafeEqual(Buffer.from(want), Buffer.from(sig));
}

// A flood guard per address plus a cap on code guesses (see REQ_PER_MIN / JOIN_PER_MIN).
function limited(ip, isJoin) {
  const now = Date.now();
  let h = hits.get(ip);
  if (!h || now - h.t0 > 60000) { h = { t0: now, n: 0, joins: 0 }; hits.set(ip, h); }
  h.n++;
  if (isJoin) h.joins++;
  // The guess cap only ever refuses JOIN requests: one person mistyping codes
  // must not block Play now for everyone behind the same carrier address.
  return h.n > REQ_PER_MIN || (isJoin && h.joins > JOIN_PER_MIN);
}

const idOk = s => typeof s === 'string' && /^[0-9a-fA-F-]{8,64}$/.test(s);
const protoOk = n => Number.isInteger(n) && n > 0 && n < 100000;

function handle(pathname, body, ip) {
  if (!protoOk(body.proto) && pathname !== '/v1/quick/cancel') return { ok: false, error: 'bad_request' };
  switch (pathname) {
    case '/v1/room/create': {
      if (!idOk(body.player_id)) return { ok: false, error: 'bad_request' };
      const room = startRoom(body.proto, 'friend');
      if (!room) return { ok: false, error: 'busy' };
      return { ok: true, code: room.code, host: PUBLIC_HOST, port: room.port };
    }
    case '/v1/room/join': {
      const code = String(body.code || '').toUpperCase().trim();
      if (!/^[A-Z2-9]{6}$/.test(code)) return { ok: false, error: 'not_found' };
      const room = rooms.get(code);
      if (!room || room.kind !== 'friend' || Date.now() - room.created > CODE_TTL_MS) return { ok: false, error: 'not_found' };
      if (room.proto !== body.proto) return { ok: false, error: 'version' };
      if (room.started || room.joined >= 2) return { ok: false, error: 'started' };
      return { ok: true, host: PUBLIC_HOST, port: room.port };
    }
    case '/v1/quick': {
      if (!idOk(body.player_id)) return { ok: false, error: 'bad_request' };
      const now = Date.now();
      let me = waiting.get(body.player_id);
      if (me && me.room) {                      // someone paired with us while we were polling
        waiting.delete(body.player_id);
        return { ok: true, matched: true, host: PUBLIC_HOST, port: me.room.port };
      }
      for (const [pid, w] of waiting) {         // the longest-waiting human on the same version
        if (pid === body.player_id || w.room || w.proto !== body.proto || now - w.seen > 4000) continue;
        const room = startRoom(body.proto, 'quick');
        if (!room) return { ok: false, error: 'busy' };
        w.room = room;
        waiting.delete(body.player_id);
        return { ok: true, matched: true, host: PUBLIC_HOST, port: room.port };
      }
      // Nobody else is looking: after a search of varying length (so it does not
      // always end on the same second) an AI partner fills the room.
      if (!me) { me = { proto: body.proto, since: now, seen: now, room: null, botAt: QUICK_WAIT_MS * (0.55 + 0.4 * Math.random()) }; waiting.set(body.player_id, me); }
      me.seen = now;
      me.proto = body.proto;
      if (BOT_FILL && now - me.since >= me.botAt) {
        const room = startRoom(body.proto, 'quick', 1);
        if (room) {
          waiting.delete(body.player_id);
          return { ok: true, matched: true, host: PUBLIC_HOST, port: room.port };
        }
      }
      return { ok: true, matched: false, waited_ms: now - me.since, give_up_ms: QUICK_WAIT_MS };
    }
    case '/v1/quick/cancel': {
      if (!idOk(body.player_id)) return { ok: false, error: 'bad_request' };
      const w = waiting.get(body.player_id);
      if (w && w.room && w.room.joined === 0) closeRoom(w.room);
      waiting.delete(body.player_id);
      return { ok: true };
    }
  }
  return { ok: false, error: 'bad_request' };
}

// Players who stopped polling are forgotten; so are stale rate-limit rows.
setInterval(() => {
  const now = Date.now();
  for (const [pid, w] of waiting) if (now - w.seen > 15000) waiting.delete(pid);
  for (const [ip, h] of hits) if (now - h.t0 > 120000) hits.delete(ip);
}, 5000).unref();

const server = http.createServer((req, res) => {
  const send = (status, obj) => {
    const out = JSON.stringify(obj);
    res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(out), 'Cache-Control': 'no-store' });
    res.end(out);
  };
  const ip = req.socket.remoteAddress || '?';
  const pathname = (req.url || '').split('?')[0];
  if (req.method === 'GET' && pathname === '/health') {
    return send(200, { ok: true, rooms: rooms.size, waiting: waiting.size, signed: !!SIG_KEY });
  }
  if (req.method !== 'POST') return send(405, { ok: false, error: 'bad_request' });
  if (limited(ip, pathname === '/v1/room/join')) return send(429, { ok: false, error: 'rate_limited' });
  let raw = '';
  let tooBig = false;
  req.on('data', d => { raw += d; if (raw.length > MAX_BODY) { tooBig = true; req.destroy(); } });
  req.on('end', () => {
    if (tooBig) return;
    if (!verify(req, raw)) return send(401, { ok: false, error: 'bad_signature' });
    let body;
    try { body = JSON.parse(raw); } catch (e) { return send(400, { ok: false, error: 'bad_request' }); }
    if (!body || typeof body !== 'object' || Array.isArray(body)) return send(400, { ok: false, error: 'bad_request' });
    send(200, handle(pathname, body, ip));
  });
});

function shutdown() {
  for (const r of rooms.values()) closeRoom(r);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 1500).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

server.listen(PORT, () => {
  log(`lobby on :${PORT}, rooms ${PORT_MIN}-${PORT_MAX} (max ${MAX_ROOMS}), public host ${PUBLIC_HOST}, signed=${!!SIG_KEY}`);
  if (!SIG_KEY) log('WARNING: SB_SIG_KEY is not set, requests are NOT verified (development only)');
});
