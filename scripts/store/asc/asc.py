import json, time, base64, subprocess, urllib.request, urllib.error, sys
KEY='/Users/yanivshimoy/keys/mail-2026-10-27/AuthKey_A726RHWTX7.p8'
KID='A726RHWTX7'; ISS='f2fcaeb1-4500-4e62-89bc-83d05e013db3'
BASE='https://api.appstoreconnect.apple.com'
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()
_tok=[None,0]
def token():
    now=int(time.time())
    if _tok[0] and now<_tok[1]-120: return _tok[0]
    h=b64(json.dumps({'alg':'ES256','kid':KID,'typ':'JWT'}).encode())
    p=b64(json.dumps({'iss':ISS,'iat':now,'exp':now+1140,'aud':'appstoreconnect-v1'}).encode())
    si=(h+'.'+p).encode()
    der=subprocess.run(['openssl','dgst','-sha256','-sign',KEY],input=si,capture_output=True,check=True).stdout
    # parse DER SEQUENCE{INTEGER r, INTEGER s}
    i=2 if der[1]<0x80 else 2+(der[1]&0x7f)
    assert der[i]==2; rl=der[i+1]; r=der[i+2:i+2+rl]; i=i+2+rl
    assert der[i]==2; sl=der[i+1]; s=der[i+2:i+2+sl]
    r=r.lstrip(b'\0').rjust(32,b'\0'); s=s.lstrip(b'\0').rjust(32,b'\0')
    t=h+'.'+p+'.'+b64(r+s); _tok[0]=t; _tok[1]=now+1140; return t
def call(method,path,body=None,retry=True):
    url=path if path.startswith('http') else BASE+path
    deadline=time.time()+300
    while True:
        data=json.dumps(body).encode() if body is not None else None
        req=urllib.request.Request(url,data=data,method=method,headers={'Authorization':'Bearer '+token(),'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(req,timeout=60) as r:
                raw=r.read(); return r.status,(json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw=e.read(); 
            try: j=json.loads(raw)
            except Exception: j={'raw':raw.decode(errors='replace')}
            if e.code==403 and 'REQUIRED_AGREEMENTS' in json.dumps(j) and retry and time.time()<deadline:
                print('agreements 403, retry in 30s',file=sys.stderr); time.sleep(30); continue
            return e.code,j
def ok(st,j,label):
    if st>=300: print(label,'ERROR',st,json.dumps(j)[:1500]); return False
    print(label,'OK',st); return True
