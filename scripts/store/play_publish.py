import json, os, re, subprocess, sys, time, base64, urllib.request, urllib.error, glob, tempfile
S='/private/tmp/claude-501/-Users-yanivshimoy/8a2e45bd-9aa7-423c-a190-2e4aa669295b/scratchpad'
PKG='com.origami.skybreaker'
API=f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}'
UP=f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}'
TOKF='/Users/yanivshimoy/keys/.play_token'
SA='/Users/yanivshimoy/keys/mail-2026-10-27/google-play-service-account.json'
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=')
def mint():
    sa=json.load(open(SA)); now=int(time.time())
    h=b64(json.dumps({'alg':'RS256','typ':'JWT'}).encode()); c=b64(json.dumps({'iss':sa['client_email'],'scope':'https://www.googleapis.com/auth/androidpublisher','aud':sa['token_uri'],'iat':now,'exp':now+3600}).encode())
    fd,kp=tempfile.mkstemp(dir=S); os.chmod(kp,0o600)
    try:
        os.write(fd,sa['private_key'].encode()); os.close(fd)
        sig=subprocess.run(['openssl','dgst','-sha256','-sign',kp],input=h+b'.'+c,capture_output=True,check=True).stdout
    finally: os.remove(kp)
    data=urllib.parse.urlencode({'grant_type':'urn:ietf:params:oauth:grant-type:jwt-bearer','assertion':(h+b'.'+c+b'.'+b64(sig)).decode()}).encode()
    tok=json.load(urllib.request.urlopen(sa['token_uri'],data))['access_token']
    open(TOKF,'w').write(tok); os.chmod(TOKF,0o600); print('minted new token'); return tok
import urllib.parse
TOK=open(TOKF).read().strip()
def req(method,url,body=None,ctype='application/json',retry=True):
    global TOK
    if isinstance(body,(dict,list)): body=json.dumps(body).encode()
    r=urllib.request.Request(url,data=body,method=method,headers={'Authorization':'Bearer '+TOK,'Content-Type':ctype})
    try:
        resp=urllib.request.urlopen(r,timeout=300); t=resp.read(); return json.loads(t) if t else {}
    except urllib.error.HTTPError as e:
        t=e.read().decode()
        if e.code==401 and retry: TOK=mint(); return req(method,url,body,ctype,False)
        raise RuntimeError(f'{method} {url.split(PKG)[-1]} -> {e.code}: {t}')
def block(md,heading_regex):
    m=re.search(heading_regex+r'.*?\n```\n(.*?)\n```',md,re.S); return m.group(1)
md=open('/Users/yanivshimoy/Skybreaker/docs/APP_STORE_COPY.md').read()
title=block(md,r'## App name'); short=block(md,r'\*\*Play Store short description'); full=block(md,r'## Full description'); notes=block(md,r'## What\'s New')
assert 'buy once' not in (full+short+notes).lower() and 'premium' not in (full+short+notes).lower()
print('lens title',len(title),'short',len(short),'full',len(full),'notes',len(notes))
assert len(short)<=80 and len(full)<=4000 and len(notes)<=500
mode=sys.argv[1]
if mode=='publish':
    edit=req('POST',API+'/edits',{})['id']; print('editId',edit); E=f'{API}/edits/{edit}'; EU=f'{UP}/edits/{edit}'
    # bundle via curl, token in header file
    hf=os.path.join(S,'hdr.txt'); fd=os.open(hf,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    os.write(fd,f'Authorization: Bearer {TOK}\n'.encode()); os.close(fd)
    try:
        out=subprocess.run(['curl','-sS','-X','POST','-H','@'+hf,'-H','Content-Type: application/octet-stream','--data-binary','@/Users/yanivshimoy/Skybreaker/builds/skybreaker.aab','--max-time','1800','-w','\nHTTP %{http_code}',EU+'/bundles?uploadType=media'],capture_output=True,text=True)
    finally: os.remove(hf)
    print('bundle:',out.stdout[-1500:],out.stderr[-500:])
    body,code=out.stdout.rsplit('\nHTTP ',1)
    if code!='200': sys.exit('bundle upload failed')
    vc=json.loads(body)['versionCode']; print('versionCode',vc)
    print('listing', req('PUT',E+'/listings/en-US',{'language':'en-US','title':title,'shortDescription':short,'fullDescription':full}).keys())
    imgs={'icon':[S+'/icon_512.png'],'featureGraphic':['/Users/yanivshimoy/Skybreaker/assets/store/feature_graphic_1024x500.png'],
          'phoneScreenshots':sorted(glob.glob('/Users/yanivshimoy/Skybreaker/assets/store/screenshots/android_phone/0[1-8]_*.png')),
          'sevenInchScreenshots':sorted(glob.glob('/Users/yanivshimoy/Skybreaker/assets/store/screenshots/android_tablet/0[1-8]_*.png')),
          'tenInchScreenshots':sorted(glob.glob('/Users/yanivshimoy/Skybreaker/assets/store/screenshots/android_tablet/0[1-8]_*.png'))}
    for t,files in imgs.items():
        req('DELETE',f'{E}/listings/en-US/{t}')
        for f in files:
            r=req('POST',f'{EU}/listings/en-US/{t}?uploadType=media',open(f,'rb').read(),'image/png'); print(t,os.path.basename(f),'ok')
    tr=req('PUT',E+'/tracks/production',{'track':'production','releases':[{'name':'1.0.0','status':'draft','versionCodes':[str(vc)],'releaseNotes':[{'language':'en-US','text':notes}]}]})
    print('track',json.dumps(tr))
    try: print('commit',req('POST',E+':commit'))
    except RuntimeError as e:
        print('COMMIT FAILED',e)
        try: print('commit2',req('POST',E+':commit?changesNotSentForReview=true'))
        except RuntimeError as e2: print('COMMIT2 FAILED',e2); print('edit left uncommitted:',edit)
elif mode=='verify':
    edit=req('POST',API+'/edits',{})['id']; E=f'{API}/edits/{edit}'
    print('track',json.dumps(req('GET',E+'/tracks/production'),indent=1))
    l=req('GET',E+'/listings/en-US'); print('listing title=%r short=%d full=%d'%(l.get('title'),len(l.get('shortDescription','')),len(l.get('fullDescription',''))), 'match', l.get('fullDescription')==full, l.get('shortDescription')==short)
    for t in ['icon','featureGraphic','phoneScreenshots','sevenInchScreenshots','tenInchScreenshots']:
        print(t,len(req('GET',f'{E}/listings/en-US/{t}').get('images',[])))
    print('details',req('GET',E+'/details'))
    req('DELETE',E)
