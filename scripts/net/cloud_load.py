#!/usr/bin/env python3
"""Load check of a DEPLOYED co-op server: several games at the same time.
Usage: cloud_load.py https://host <friend games> <AI games> [seconds]
Friend game = two bots from this Mac in one room; AI game = one bot that asks
for PLAY NOW alone and gets the server's AI partner. Prints /health while they
play; read the machine's own load over ssh meanwhile."""
import hashlib, hmac, json, os, re, subprocess, sys, tempfile, time, urllib.request, urllib.error, uuid
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GODOT = os.environ.get('GODOT', '/Applications/Godot.app/Contents/MacOS/Godot')
URL = sys.argv[1].rstrip('/'); N_FRIEND = int(sys.argv[2]); N_AI = int(sys.argv[3]); SECS = int(sys.argv[4]) if len(sys.argv) > 4 else 100
KEY = re.search(r'const SIG_KEY[^=]*=\s*"([^"]+)"', open(os.path.join(ROOT, 'config/online_keys.gd')).read()).group(1)
PROTO = int(re.search(r'const PROTO: int = (\d+)', open(os.path.join(ROOT, 'scripts/net/Net.gd')).read()).group(1))
def call(path, body=None):
    raw = json.dumps(body) if body is not None else None
    headers = {'Content-Type': 'application/json', 'User-Agent': 'skybreaker-load/1.0'}
    if raw is not None:
        t = str(int(time.time()))
        headers['X-SB-Ts'] = t
        headers['X-SB-Sig'] = hmac.new(KEY.encode(), (t + '.' + raw).encode(), hashlib.sha256).hexdigest()
    req = urllib.request.Request(URL + path, data=raw.encode() if raw else None, headers=headers, method='POST' if raw else 'GET')
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return json.loads(r.read())
    except urllib.error.HTTPError as e: return json.loads(e.read() or b'{}')
tmp = tempfile.mkdtemp(); bots = []
def bot(name, room):
    p = subprocess.Popen([GODOT, '--headless', '--path', ROOT, 'res://scenes/net/NetBot.tscn', '--', f'--host={room["host"]}', f'--port={room["port"]}',
                          f'--name={name}', '--dmg=8', f'--timeout={SECS}'], stdout=open(os.path.join(tmp, name + '.log'), 'w'), stderr=subprocess.STDOUT)
    bots.append((name, p))
for i in range(N_FRIEND):
    room = call('/v1/room/create', {'proto': PROTO, 'player_id': str(uuid.uuid4())})
    print(f'friend game {i + 1}:', {k: room.get(k) for k in ('ok', 'error', 'port')}, flush=True)
    if room.get('ok'): bot(f'f{i}a', room); bot(f'f{i}b', room)
for i in range(N_AI):
    pid = str(uuid.uuid4()); room = {}
    for _ in range(30):
        room = call('/v1/quick', {'proto': PROTO, 'player_id': pid})
        if room.get('matched') or room.get('error'): break
        time.sleep(1.5)
    print(f'AI game {i + 1}:', {k: room.get(k) for k in ('ok', 'matched', 'error', 'port')}, flush=True)
    if room.get('matched'): bot(f'ai{i}', room)
print('one more than the limit:', call('/v1/room/create', {'proto': PROTO, 'player_id': str(uuid.uuid4())}), flush=True)
t0 = time.time()
while time.time() - t0 < SECS - 25:
    time.sleep(15); print('health', call('/health'), flush=True)
for name, p in bots:
    try: p.wait(timeout=SECS + 60)
    except subprocess.TimeoutExpired: p.kill()
bad = 0
for name, p in bots:
    t = open(os.path.join(tmp, name + '.log')).read()
    s = re.search(r'"bytes_in":(\d+)', t)
    if 'SCRIPT ERROR' in t: bad += 1; print('SCRIPT ERROR in', name)
print(f'bots {len(bots)}, with script errors {bad}, logs {tmp}')
