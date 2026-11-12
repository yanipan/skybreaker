#!/usr/bin/env python3
"""Smoke test of a DEPLOYED co-op server: a friend room through the real lobby,
two bots from this Mac play it (sector 1 and into 2), then both go down = game over. Usage: cloud_smoke.py https://host
Uses the real signing key from config/online_keys.gd (never printed)."""
import hashlib, hmac, json, os, re, subprocess, sys, tempfile, time, urllib.request, urllib.error, uuid
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GODOT = os.environ.get('GODOT', '/Applications/Godot.app/Contents/MacOS/Godot')
URL = sys.argv[1].rstrip('/')
KEY = re.search(r'const SIG_KEY[^=]*=\s*"([^"]+)"', open(os.path.join(ROOT, 'config/online_keys.gd')).read()).group(1)
PROTO = int(re.search(r'const PROTO: int = (\d+)', open(os.path.join(ROOT, 'scripts/net/Net.gd')).read()).group(1))
fails = []
def check(ok, what):
    print(('PASS  ' if ok else 'FAIL  ') + what, flush=True)
    if not ok: fails.append(what)
def call(path, body=None, sign=True):
    raw = json.dumps(body) if body is not None else None
    headers = {'Content-Type': 'application/json', 'User-Agent': 'skybreaker-smoke/1.0'}
    if sign and raw is not None:
        t = str(int(time.time()))
        headers['X-SB-Ts'] = t
        headers['X-SB-Sig'] = hmac.new(KEY.encode(), (t + '.' + raw).encode(), hashlib.sha256).hexdigest()
    req = urllib.request.Request(URL + path, data=raw.encode() if raw else None, headers=headers, method='POST' if raw else 'GET')
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read() or b'{}')
st, h = call('/health')
check(st == 200 and h.get('ok') and h.get('signed'), f'health over https, signed ({h})')
st, j = call('/v1/room/join', {'proto': PROTO, 'code': 'ABCDEF'}, sign=False)
check(j.get('error') == 'bad_signature', 'unsigned request refused')
st, room = call('/v1/room/create', {'proto': PROTO, 'player_id': str(uuid.uuid4())})
check(room.get('ok') and room.get('port'), f'room created ({ {k: room.get(k) for k in ("code", "host", "port")} })')
if room.get('ok'):
    tmp = tempfile.mkdtemp()
    def bot(name):
        return subprocess.Popen([GODOT, '--headless', '--path', ROOT, 'res://scenes/net/NetBot.tscn', '--',
                                 f'--host={room["host"]}', f'--port={room["port"]}', f'--name={name}', '--dmg=8', '--die_at=75', '--no_rescue', '--timeout=200'],
                                stdout=open(os.path.join(tmp, name + '.log'), 'w'), stderr=subprocess.STDOUT)
    bots = [bot('botA'), bot('botB')]
    time.sleep(20)
    check(call('/health')[1].get('rooms') == 1, 'one room alive while the bots play')
    for b in bots:
        try: b.wait(timeout=240)
        except subprocess.TimeoutExpired: b.kill()
    for n in ('botA', 'botB'):
        t = open(os.path.join(tmp, n + '.log')).read()
        m = re.search(r'STATS (\{.*\})', t)
        check(m is not None and 'SCRIPT ERROR' not in t, f'{n} played to the end over the internet, no script errors')
        if m: print('      ', m.group(1)[:230])
    time.sleep(8)
    check(call('/health')[1].get('rooms') == 0, 'room closed itself afterwards')
    print('logs', tmp)
print('CloudSmoke: all passed' if not fails else f'CloudSmoke: {len(fails)} FAILED')
sys.exit(1 if fails else 0)
