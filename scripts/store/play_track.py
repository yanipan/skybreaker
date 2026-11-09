#!/usr/bin/env python3
"""Google Play tracks for com.origami.skybreaker.

    python3 scripts/store/play_track.py tracks
    python3 scripts/store/play_track.py internal builds/skybreaker-1.0.1-vc12.aab "release notes"

`internal` uploads the bundle and puts it on the INTERNAL TESTING track only
(status completed: testers of that track get it; production is not touched).
Service account JSON: ~/keys/mail-2026-10-27/google-play-service-account.json.
"""
import base64, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.parse, urllib.request
PKG = 'com.origami.skybreaker'
API = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}'
UP = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}'
SA = os.path.expanduser('~/keys/mail-2026-10-27/google-play-service-account.json')

def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=')
def mint():
    sa = json.load(open(SA)); now = int(time.time())
    h = b64(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    c = b64(json.dumps({'iss': sa['client_email'], 'scope': 'https://www.googleapis.com/auth/androidpublisher', 'aud': sa['token_uri'], 'iat': now, 'exp': now + 3600}).encode())
    with tempfile.TemporaryDirectory() as d:
        kp = os.path.join(d, 'k.pem'); fd = os.open(kp, os.O_WRONLY | os.O_CREAT, 0o600)
        os.write(fd, sa['private_key'].encode()); os.close(fd)
        sig = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', kp], input=h + b'.' + c, capture_output=True, check=True).stdout
    data = urllib.parse.urlencode({'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion': (h + b'.' + c + b'.' + b64(sig)).decode()}).encode()
    return json.load(urllib.request.urlopen(sa['token_uri'], data))['access_token']
TOK = mint()
def req(method, url, body=None, ctype='application/json'):
    if isinstance(body, (dict, list)): body = json.dumps(body).encode()
    r = urllib.request.Request(url, data=body, method=method, headers={'Authorization': 'Bearer ' + TOK, 'Content-Type': ctype})
    try:
        t = urllib.request.urlopen(r, timeout=1800).read(); return json.loads(t) if t else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'{method} {url.split("/applications/")[-1]} -> {e.code} {e.read().decode()[:600]}')

mode = sys.argv[1] if len(sys.argv) > 1 else 'tracks'
edit = req('POST', API + '/edits', {})['id']; E = f'{API}/edits/{edit}'
if mode == 'tracks':
    for t in req('GET', E + '/tracks').get('tracks', []):
        print('track', t['track'], [(r.get('name'), r.get('status'), r.get('versionCodes')) for r in t.get('releases', [])])
    try: print('internal testers', req('GET', E + '/testers/internal'))
    except RuntimeError as e: print('internal testers:', str(e)[:200])
    req('DELETE', E)
elif mode == 'internal':
    aab, notes = sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else 'Playtest build')
    b = req('POST', f'{UP}/edits/{edit}/bundles?uploadType=media', open(aab, 'rb').read(), 'application/octet-stream')
    vc = b['versionCode']; print('uploaded versionCode', vc)
    tr = req('PUT', E + '/tracks/internal', {'track': 'internal', 'releases': [{'name': f'playtest vc{vc}', 'status': 'completed', 'versionCodes': [str(vc)], 'releaseNotes': [{'language': 'en-US', 'text': notes[:500]}]}]})
    print('track', json.dumps(tr))
    print('commit', req('POST', E + ':commit'))
