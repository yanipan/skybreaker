#!/usr/bin/env python3
"""End-to-end test of the lobby service on this machine.
    python3 server/lobby/test_lobby.py
Starts its own lobby (port 24610, rooms 24810-24819, signed with a test key),
checks the API rules, plays one friend game with two headless bots through a
created room, and checks that rooms are cleaned up. Exit code 1 on any failure."""
import hashlib, hmac, json, os, re, signal, subprocess, sys, tempfile, time, urllib.request, urllib.error

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GODOT = os.environ.get('GODOT', '/Applications/Godot.app/Contents/MacOS/Godot')
PORT = 24610
KEY = 'test-key-not-a-secret'
URL = f'http://127.0.0.1:{PORT}'
PROTO = int(re.search(r'const PROTO: int = (\d+)', open(os.path.join(ROOT, 'scripts/net/Net.gd')).read()).group(1))
fails = []

def check(ok, what):
    print(('PASS  ' if ok else 'FAIL  ') + what, flush=True)
    if not ok:
        fails.append(what)

def call(path, body, sign=True, key=KEY, ts=None):
    raw = json.dumps(body)
    headers = {'Content-Type': 'application/json'}
    if sign:
        t = str(int(time.time()) if ts is None else ts)
        headers['X-SB-Ts'] = t
        headers['X-SB-Sig'] = hmac.new(key.encode(), (t + '.' + raw).encode(), hashlib.sha256).hexdigest()
    req = urllib.request.Request(URL + path, data=raw.encode(), headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b'{}')

def health():
    with urllib.request.urlopen(URL + '/health', timeout=5) as r:
        return json.loads(r.read())

tmp = tempfile.mkdtemp()
env = dict(os.environ, LOBBY_PORT=str(PORT), ROOM_PORT_MIN='24810', ROOM_PORT_MAX='24819', MAX_ROOMS='3',
           SB_SIG_KEY=KEY, GODOT=GODOT, PROJECT=ROOT, ROOM_EXTRA_ARGS='--sectors=1 --duration_mul=0.3',
           JOIN_PER_MIN='12')
lobby_log = open(os.path.join(tmp, 'lobby.log'), 'w')
lobby = subprocess.Popen(['node', os.path.join(ROOT, 'server/lobby/lobby.js')], env=env, stdout=lobby_log, stderr=subprocess.STDOUT)
procs = [lobby]
try:
    for _ in range(40):
        try:
            health(); break
        except Exception:
            time.sleep(0.25)
    h = health()
    check(h.get('ok') and h.get('rooms') == 0 and h.get('signed') is True, f'lobby is up, signed, no rooms ({h})')

    A = '00000000-0000-4000-8000-0000000000a1'
    B = '00000000-0000-4000-8000-0000000000b2'
    # --- Signing ---
    st, j = call('/v1/room/join', {'proto': PROTO, 'code': 'ABCDEF'}, sign=False)
    check(st == 401 and j.get('error') == 'bad_signature', 'unsigned request refused')
    st, j = call('/v1/room/join', {'proto': PROTO, 'code': 'ABCDEF'}, key='wrong-key')
    check(st == 401, 'wrong key refused')
    st, j = call('/v1/room/join', {'proto': PROTO, 'code': 'ABCDEF'}, ts=int(time.time()) - 3600)
    check(st == 401, 'an hour-old signed request refused (replay window)')
    # --- Codes ---
    st, j = call('/v1/room/join', {'proto': PROTO, 'code': 'ABCDEF'})
    check(st == 200 and j == {'ok': False, 'error': 'not_found'}, 'unknown code: not_found')
    st, j = call('/v1/room/create', {'proto': PROTO, 'player_id': 'not an id'})
    check(j.get('error') == 'bad_request', 'bad player id refused')
    st, room = call('/v1/room/create', {'proto': PROTO, 'player_id': A})
    code = room.get('code', '')
    check(room.get('ok') and re.fullmatch(r'[A-HJ-KM-NP-Z2-9]{6}', code) is not None and 24810 <= room.get('port', 0) <= 24819, f'room created: code {code}, port {room.get("port")}')
    st, j = call('/v1/room/join', {'proto': PROTO, 'code': code.lower()})
    check(j.get('ok') and j.get('port') == room.get('port'), 'join by code (typed in lower case) gives the same room')
    st, j = call('/v1/room/join', {'proto': PROTO + 1, 'code': code})
    check(j == {'ok': False, 'error': 'version'}, 'another game version: version')
    check(health()['rooms'] == 1, 'one room alive')

    # --- A friend game through that room: two bots ---
    def bot(name):
        return subprocess.Popen([GODOT, '--headless', '--path', ROOT, 'res://scenes/net/NetBot.tscn', '--',
                                 f'--port={room["port"]}', f'--name={name}', '--dmg=8', '--timeout=200'],
                                stdout=open(os.path.join(tmp, name + '.log'), 'w'), stderr=subprocess.STDOUT)
    ba, bb = bot('botA'), bot('botB')
    procs += [ba, bb]
    # Wait for the lobby to see the run start (its log), then ask ONCE: polling
    # join would trip the code-guessing limit, which is what it is there for.
    for _ in range(120):
        if f'room {code} run started' in open(os.path.join(tmp, 'lobby.log')).read():
            break
        time.sleep(0.5)
    st, j = call('/v1/room/join', {'proto': PROTO, 'code': code})
    check(j == {'ok': False, 'error': 'started'}, f'once the run has started the code no longer lets anyone in ({j})')
    ba.wait(timeout=180); bb.wait(timeout=180)
    stats = []
    for n in ('botA', 'botB'):
        t = open(os.path.join(tmp, n + '.log')).read()
        m = re.search(r'STATS (\{.*\})', t)
        check(m is not None and 'SCRIPT ERROR' not in t, f'{n} played the room to the end, no script errors')
        if m:
            stats.append(json.loads(m.group(1)))
    check(len(stats) == 2 and all(s['cleared'] == [1] for s in stats), 'both bots cleared sector 1 in the lobby-made room')
    for _ in range(40):
        if health()['rooms'] == 0:
            break
        time.sleep(0.5)
    check(health()['rooms'] == 0, 'the room process is gone after the run')
    st, j = call('/v1/room/join', {'proto': PROTO, 'code': code})
    check(j == {'ok': False, 'error': 'not_found'}, 'the finished room code is not_found')

    # --- Play now ---
    st, j = call('/v1/quick', {'proto': PROTO, 'player_id': A})
    check(j.get('ok') and j.get('matched') is False and j.get('give_up_ms') == 10000, 'first Play-now player waits')
    st, j = call('/v1/quick', {'proto': PROTO + 1, 'player_id': B})
    check(j.get('matched') is False, 'a player on another version is not matched with them')
    call('/v1/quick/cancel', {'player_id': B})
    st, jb = call('/v1/quick', {'proto': PROTO, 'player_id': B})
    check(jb.get('matched') is True and 24810 <= jb.get('port', 0) <= 24819, f'second player on the same version is matched at once (port {jb.get("port")})')
    st, ja = call('/v1/quick', {'proto': PROTO, 'player_id': A})
    check(ja.get('matched') is True and ja.get('port') == jb.get('port'), 'the waiting player gets the same room on the next poll')
    check(health()['waiting'] == 0, 'nobody left in the queue')
    st, j = call('/v1/quick', {'proto': PROTO, 'player_id': A})
    st, j2 = call('/v1/quick/cancel', {'player_id': A})
    check(j.get('matched') is False and j2.get('ok') and health()['waiting'] == 0, 'cancel leaves the queue')

    # --- Limits ---
    r1 = call('/v1/room/create', {'proto': PROTO, 'player_id': A})[1]
    r2 = call('/v1/room/create', {'proto': PROTO, 'player_id': A})[1]
    r3 = call('/v1/room/create', {'proto': PROTO, 'player_id': A})[1]
    check(r3.get('error') == 'busy' or r2.get('error') == 'busy', f'room limit (3) holds: {[r.get("ok") for r in (r1, r2, r3)]}, {health()["rooms"]} alive')
    print('waiting for a fresh rate-limit minute...', flush=True)
    time.sleep(62)
    codes = []
    for i in range(16):
        codes.append(call('/v1/room/join', {'proto': PROTO, 'code': 'ZZZZZ' + 'ABCDEFGHJKMNPQRS'[i]})[1].get('error'))
    check(codes[:12] == ['not_found'] * 12 and codes[12:] == ['rate_limited'] * 4, f'code guessing: 12 a minute allowed in this test, the rest refused ({codes.count("rate_limited")} of 16)')
    st, j = call('/v1/quick', {'proto': PROTO, 'player_id': B})
    check(j.get('ok') is True, 'other requests from the same address still work while joins are limited')
    call('/v1/quick/cancel', {'player_id': B})

    # --- Abandoned rooms close by themselves (nobody ever connected) ---
    print('waiting for the abandoned rooms to close (45 s after they were made)...', flush=True)
    time.sleep(5)
    check(health()['rooms'] == 0, f'abandoned rooms closed themselves ({health()["rooms"]} left)')
finally:
    for p in procs[1:]:
        if p.poll() is None:
            p.kill()
    lobby.send_signal(signal.SIGTERM)
    try:
        lobby.wait(timeout=5)
    except Exception:
        lobby.kill()
    lobby_log.close()

left = subprocess.run(['pgrep', '-f', 'ServerWorld.tscn -- --port=248'], capture_output=True, text=True).stdout.split()
check(len(left) == 0, f'no room server processes left behind ({len(left)})')
print(f'LobbyTest: {"FAILED " + str(len(fails)) if fails else "all passed"}  (logs {tmp})')
sys.exit(1 if fails else 0)
